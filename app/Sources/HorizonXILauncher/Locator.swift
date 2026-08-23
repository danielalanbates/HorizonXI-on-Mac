import Foundation

/// Find a world's client on this Mac, instead of asking the player where it is.
///
/// Daniel, 2026-08-22: *"none of the private servers seem to know where the downloads are.
/// maybe we should build a locate feature next to the download."* He is right — every world
/// that was not installed through this launcher starts out with an empty `dataPath`, and the
/// only remedy on offer was "Choose folder…", which asks the person who just installed
/// something to remember where their installer put it.
///
/// So: search the handful of places an FFXI client actually ends up, and offer what is found.
enum Locator {

    /// One candidate install.
    struct Hit: Identifiable, Hashable {
        var url: URL
        /// The folder to hand to `Server.dataPath` — the *parent* of the Ashita folder when the
        /// two sit side by side, because that is what `Install.resolveAshitaDir` expects.
        var dataPath: URL
        var why: String
        /// Higher is a better guess for this world.
        var score: Int
        var id: String { url.path }
    }

    /// Where clients live on this machine. Anything unreadable is skipped silently: an
    /// unplugged drive is not an error, it is just not there today.
    static func roots() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var out: [URL] = [
            home.appendingPathComponent("Games"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications"),
        ]
        // External drives, where a 20 GB client usually ends up on a laptop.
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
                                                 includingPropertiesForKeys: nil) {
            out.append(contentsOf: vols)
        }
        return out.filter { fm.fileExists(atPath: $0.path) }
    }

    /// The files that say "an FFXI client lives here".
    private static let markers = ["Ashita-cli.exe", "Ashita.exe", "xiloader.exe", "pol.exe"]

    /// Walk each root a few levels deep looking for those markers.
    ///
    /// Depth 4 and a skip-list keep this honest on a spinning external drive: the ROM trees
    /// under a client hold tens of thousands of files and none of them are what we are looking
    /// for, so descending into them would turn a two-second search into a two-minute one.
    static func search(depth: Int = 4) -> [URL] {
        let fm = FileManager.default
        let skip: Set<String> = ["ROM", "ROM2", "ROM3", "ROM4", "ROM5", "ROM6", "ROM7", "ROM8",
                                 "ROM9", "sound", "sound2", "movie", "Contents", "node_modules",
                                 ".git", "Library", "System"]
        var found: [URL] = []
        var queue: [(URL, Int)] = roots().map { ($0, 0) }

        while !queue.isEmpty {
            let (dir, level) = queue.removeFirst()
            guard level <= depth else { continue }
            guard let kids = try? fm.contentsOfDirectory(at: dir,
                                                         includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { continue }
            var isClient = false
            for k in kids where markers.contains(k.lastPathComponent) { isClient = true }
            if isClient { found.append(dir); continue }   // no need to go deeper into a client
            for k in kids {
                let name = k.lastPathComponent
                guard !skip.contains(name), !name.hasSuffix(".app") || level == 0 else { continue }
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: k.path, isDirectory: &isDir), isDir.boolValue {
                    queue.append((k, level + 1))
                }
            }
        }
        return found
    }

    /// Candidates for one world, best guess first.
    ///
    /// Scoring is deliberately simple and explainable, because the player is going to be shown
    /// the reason: a path that names the server beats one that does not, a client with a
    /// SquareEnix folder beside it beats one without, and this project's own wrapper is ranked
    /// last so "Locate" never quietly points a world at HorizonXI's client — the mistake
    /// `Install.clientAmbiguity` exists to catch.
    static func candidates(for server: Server, in dirs: [URL]? = nil) -> [Hit] {
        let fm = FileManager.default
        let key = AddonPolicy.normalize(server.name)
        var out: [Hit] = []

        for dir in dirs ?? search() {
            let path = AddonPolicy.normalize(dir.path)
            var score = 0
            var why: [String] = []

            if !key.isEmpty && path.contains(key) {
                score += 10; why.append("the path names \(server.name)")
            }
            let parent = dir.deletingLastPathComponent()
            let hasSE = fm.fileExists(atPath: dir.appendingPathComponent("SquareEnix").path)
                     || fm.fileExists(atPath: parent.appendingPathComponent("SquareEnix").path)
                     || fm.fileExists(atPath: parent.appendingPathComponent("Game/SquareEnix").path)
            if hasSE { score += 4; why.append("game data beside it") }
            if fm.fileExists(atPath: dir.appendingPathComponent("addons").path) {
                score += 1; why.append("addons folder")
            }
            // This project's own wrapper: correct for HorizonXI and the local world, wrong for
            // everybody else, and a silent wrong answer here plays another server's data.
            if dir.path.contains("siku.app") || dir.path.contains("/Contents/SharedSupport/") {
                score += (server.local || server.name == "HorizonXI") ? 6 : -20
                why.append("inside this launcher's wrapper")
            }
            guard score > 0 else { continue }

            // `dataPath` wants the folder the *layout* starts at: the Ashita folder's parent
            // when a SquareEnix folder is its sibling, otherwise the folder itself.
            let data = fm.fileExists(atPath: parent.appendingPathComponent("SquareEnix").path)
                    || fm.fileExists(atPath: parent.appendingPathComponent("Game/SquareEnix").path)
                ? parent : dir
            out.append(Hit(url: dir, dataPath: data,
                           why: why.joined(separator: ", "), score: score))
        }
        return out.sorted { $0.score > $1.score }
    }
}
