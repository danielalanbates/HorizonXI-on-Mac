import Foundation

/// Refreshes what the launcher knows about each server from that server's own published pages,
/// on startup, in the background.
///
/// ## What is actually fetchable, checked 2026-08-14
///
/// **Addon lists: yes, for HorizonXI.** <https://horizonxi.info/addons> is plain HTML and is the
/// page HorizonXI's own wiki sends players to. It parses reliably. No other server on the list
/// publishes its addon rules anywhere this project could find.
///
/// **News: no, for everybody.** This was checked properly before writing any of it, because a
/// banner that invents its contents is worse than no banner:
///
/// - `horizonxi.com` is a client-rendered SPA. `/rss.xml`, `/feed` and `/api/news` all return the
///   app shell, not data. Its real backend is `api.horizonxi.com`, which answers 404 on every
///   obvious news path; the paths in its JS bundle are front-end routes, not endpoints.
/// - CatsEyeXI, Eden, FFEra: no feed. `/feed` is 404 or the SPA shell.
/// - Most of these communities publish news to Discord, which is not fetchable without a bot
///   token and a server invite.
///
/// So `NewsItem`s are **not scraped and never fabricated**. The banner rotates what the launcher
/// genuinely knows: the selected server's era and note, whether this project has verified it,
/// and the state of its addon policy. `feedURL` exists on `Server` so that the day any server
/// ships an RSS or JSON feed, it is one line to turn on — `parseFeed` already handles RSS and
/// JSON Feed.
@MainActor
final class ServerFeeds: ObservableObject {
    struct NewsItem: Identifiable, Hashable {
        var id: String { title + source }
        var title: String
        var source: String
        /// nil for items the launcher derived itself rather than fetched.
        var url: URL?
        var fetched: Bool
    }

    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var lastRefresh: Date?
    /// Server name -> the addon list fetched from that server, if the fetch worked.
    @Published private(set) var fetchedAddonLists: [String: AddonPolicy] = [:]

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorizonXI-on-Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("addon-lists.json")
    }

    init() { loadCache() }

    /// Called once when the launcher window appears. Never blocks the UI, and a failure is
    /// silent by design: a launcher that cannot reach the internet must still start the game.
    func refresh(servers: [Server]) {
        Task { await refreshAsync(servers: servers) }
    }

    func refreshAsync(servers: [Server]) async {
        var lists: [String: AddonPolicy] = [:]
        var cacheable: [String: [String]] = [:]

        for server in servers {
            guard let url = AddonPolicies.publishedListURL(for: server) else { continue }
            guard let names = await fetchAddonNames(from: url) else { continue }

            // Sanity-bound the parse before trusting it. The parser is deliberately loose -- it
            // is reading somebody else's HTML -- so it also picks up headings and stray page
            // text, and an over-permissive allowlist is the dangerous direction: it would permit
            // an addon the server does not, which is what gets accounts banned.
            //
            // Against the known-good page it yields 189 candidates for 158 published entries,
            // about 1.2x. A parse far outside that band means the page was redesigned, and the
            // compiled-in snapshot is the safer thing to keep using.
            let expected = AddonPolicies.horizonPlugins.count + AddonPolicies.horizonAddons.count
            guard names.count >= expected / 2, names.count <= expected * 2 else { continue }
            lists[server.name] = AddonPolicy.allowlist(
                published: names,
                source: "\(url.host ?? "the server's site"), fetched \(Self.today())")
            cacheable[server.name] = names
        }

        fetchedAddonLists = lists
        lastRefresh = Date()
        saveCache(cacheable)
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func fetchAddonNames(from url: URL) async -> [String]? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("FFXI-on-Mac launcher", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        return Self.namesFromHTML(html)
    }

    /// Pull candidate addon names out of a published list page. Deliberately loose: the page is
    /// somebody else's HTML and will be redesigned without warning, so this takes text out of
    /// list items and links and lets `AddonPolicy.normalize` do the matching.
    nonisolated static func namesFromHTML(_ html: String) -> [String] {
        var out: [String] = []
        var text = ""
        var inTag = false
        var tagName = ""
        for ch in html {
            if ch == "<" { inTag = true; tagName = ""; flush(&text, into: &out); continue }
            if ch == ">" { inTag = false; continue }
            if inTag { tagName.append(ch); continue }
            text.append(ch)
        }
        flush(&text, into: &out)
        return Array(Set(out)).sorted()
    }

    nonisolated private static func flush(_ text: inout String, into out: inout [String]) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        guard !t.isEmpty, t.count <= 40 else { return }
        // Split "A, B, C" runs, which is how the known page lays the addons out.
        for piece in t.components(separatedBy: ",") {
            let p = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard p.count >= 2, p.count <= 32 else { continue }
            guard p.rangeOfCharacter(from: .letters) != nil else { continue }
            guard !p.contains("."), !p.contains(":"), !p.contains("©") else { continue }
            out.append(p)
        }
    }

    private func saveCache(_ lists: [String: [String]]) {
        guard let d = try? JSONEncoder().encode(lists) else { return }
        try? d.write(to: Self.cacheURL)
    }

    private func loadCache() {
        guard let d = try? Data(contentsOf: Self.cacheURL),
              let lists = try? JSONDecoder().decode([String: [String]].self, from: d)
        else { return }
        for (name, names) in lists where names.count > 10 {
            fetchedAddonLists[name] = AddonPolicy.allowlist(
                published: names, source: "cached from that server's published list")
        }
    }

    /// What the banner rotates through for the selected server. These are facts the launcher
    /// holds, not headlines invented to fill a banner: if a server ever publishes a real feed,
    /// fetched items are prepended and marked.
    func bannerItems(for server: Server?, policy: AddonPolicy) -> [NewsItem] {
        guard let server else { return [] }
        var out = items.filter { $0.fetched }

        if !server.era.isEmpty {
            out.append(NewsItem(title: "\(server.name) — \(server.era)",
                                source: server.name, url: nil, fetched: false))
        }
        if !server.note.isEmpty {
            out.append(NewsItem(title: server.note, source: server.name, url: nil, fetched: false))
        }
        switch policy {
        case let .allowlist(names, source):
            out.append(NewsItem(title: "\(names.count) approved addons — \(source)",
                                source: server.name,
                                url: AddonPolicies.publishedListURL(for: server), fetched: false))
        case .unknown:
            out.append(NewsItem(
                title: "\(server.name)'s addon rules are not published anywhere this launcher "
                     + "can read — check before you load anything.",
                source: server.name, url: nil, fetched: false))
        case let .unrestricted(reason):
            out.append(NewsItem(title: reason, source: server.name, url: nil, fetched: false))
        }
        if !server.verified {
            out.append(NewsItem(
                title: "This project has not tested \(server.name) itself — its login host comes "
                     + "from the server's own published setup guide.",
                source: server.name, url: nil, fetched: false))
        }
        return out
    }
}
