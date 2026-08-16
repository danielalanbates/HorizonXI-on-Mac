import Foundation

/// A private server the launcher can connect to.
///
/// Only HorizonXI is verified — its host is the one this project actually logs into. The other
/// entries are seeded with the login hosts those communities publish, but they are **untested
/// here**, which is why every field is editable and why `verified` is surfaced in the UI rather
/// than hidden. Do not present an unverified host as if it were known-good.
struct Server: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var host: String
    /// Ashita boot profile under `config/boot/`. Each server community ships its own.
    var bootProfile: String
    var verified: Bool
    /// Optional note shown under the server picker.
    var note: String
    /// Era / level cap, shown as a subtitle in the dropdown.
    var era: String = ""
    /// Rough community size, used **only** for ordering the dropdown. Never shown as a number:
    /// these are estimates from public trackers and would be stale within a month. Ordering by
    /// them is useful; publishing them as fact is not.
    var population: Int = 0
    /// Pinned entries sort above everything else regardless of population.
    var pinned: Bool = false
    /// A server that runs on this Mac. Selecting it turns the launcher into an installer for
    /// LandSandBoat as well: see `LocalServer` and `scripts/lsb-server.sh`. Optional in the
    /// decoder so a `servers.json` written by an older build still loads.
    var local: Bool = false
    /// Where this server publishes the retail client version it insists on (its LandSandBoat
    /// `login.lua`, `CLIENT_VER`). Blank when it publishes nothing; the pre-game check then only
    /// has the compiled-in `requiredClient` snapshot to go on.
    var requiredClientURL: String = ""
    /// Retail patch level (e.g. `30251204_1`) the login server rejects anything older than with
    /// "The game's data has been updated". Snapshot; refreshed from `requiredClientURL` on start.
    var requiredClient: String = ""

    // A hand-written decoder because the synthesised one treats a missing key as an error rather
    // than as "use the default". `servers.json` on disk was written by whichever build the user
    // had before, so every field added since then is missing from it — and a decode failure here
    // throws the file away and silently resets the login hosts they typed in.
    init(name: String, host: String, bootProfile: String, verified: Bool, note: String,
         era: String = "", population: Int = 0, pinned: Bool = false, local: Bool = false,
         requiredClientURL: String = "", requiredClient: String = "") {
        self.name = name; self.host = host; self.bootProfile = bootProfile
        self.verified = verified; self.note = note; self.era = era
        self.population = population; self.pinned = pinned; self.local = local
        self.requiredClientURL = requiredClientURL; self.requiredClient = requiredClient
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name        = try c.decode(String.self, forKey: .name)
        host        = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        bootProfile = try c.decodeIfPresent(String.self, forKey: .bootProfile) ?? "horizonxi.ini"
        verified    = try c.decodeIfPresent(Bool.self,   forKey: .verified) ?? false
        note        = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        era         = try c.decodeIfPresent(String.self, forKey: .era) ?? ""
        population  = try c.decodeIfPresent(Int.self,    forKey: .population) ?? 0
        pinned      = try c.decodeIfPresent(Bool.self,   forKey: .pinned) ?? false
        local       = try c.decodeIfPresent(Bool.self,   forKey: .local) ?? false
        requiredClientURL = try c.decodeIfPresent(String.self, forKey: .requiredClientURL) ?? ""
        requiredClient    = try c.decodeIfPresent(String.self, forKey: .requiredClient) ?? ""
        // Older servers.json files predate the version check; give the built-in entry's values
        // back to a server the user has not renamed, so the check works without a reset.
        if requiredClientURL.isEmpty, requiredClient.isEmpty,
           let b = Server.builtins.first(where: { $0.name == name }) {
            requiredClientURL = b.requiredClientURL; requiredClient = b.requiredClient
        }
    }

    /// Ranking and population from nostalgic.gg's live-tracked FFXI private-server list
    /// (checked 2026-08-13; it tracks nine servers despite its "Top 10" title, hence Local
    /// server standing in as the round tenth). Login hosts below are copied verbatim from each
    /// server's own connect/setup page or wiki — real values, not guesses — but `verified` is
    /// still false for all of them except HorizonXI: published-by-the-server and
    /// tested-by-this-project are different claims, and only the second earns the badge. Two
    /// servers (Gaia XI, Tabula Rasa XI) publish no login host anywhere this project could find;
    /// those stay blank on purpose rather than guessing.
    static let builtins: [Server] = [
        Server(name: "HorizonXI", host: "play.horizonxi.com", bootProfile: "horizonxi.ini",
               verified: true,
               note: "The server this project was built and tested against.",
               era: "Chains of Promathia · 75 cap", population: 9495, pinned: true),
        Server(name: "Local server", host: "127.0.0.1", bootProfile: "lsb.ini",
               verified: true,
               note: "LandSandBoat, built and run on this Mac. Nobody else can reach it.",
               era: "LandSandBoat · your own world", population: 9494, pinned: true,
               local: true),
        Server(name: "CatsEyeXI", host: "server.catseyexi.com", bootProfile: "catseyexi.ini",
               verified: false,
               note: "Login host from CatsEyeXI's own connect page. Untested by this project.",
               era: "Custom content · 75 cap", population: 2722,
               // CatsEyeXI's server settings are public; CLIENT_VER there is what its login
               // server enforces (VER_LOCK = 2, "this version or newer"). 30251204_1 as of
               // 2026-08-15. HorizonXI's client was at 30251101_2 that day, which is exactly
               // why logging into CatsEye from a HorizonXI install fails.
               requiredClientURL: "https://raw.githubusercontent.com/CatsAndBoats/catseyexi/base/settings/default/login.lua",
               requiredClient: "30251204_1"),
        Server(name: "Eden", host: "play.edenxi.com", bootProfile: "eden.ini", verified: false,
               note: "Login host from Eden's own new-player wiki. Untested by this project.",
               era: "Classic · 75 cap", population: 1925),
        Server(name: "FFEra", host: "ffera.com", bootProfile: "ffera.ini", verified: false,
               note: "Longest-running 75-cap community server. Login host from FFEra's own "
                     + "wiki. Untested by this project.",
               era: "Wings of the Goddess · 75 cap", population: 218),
        Server(name: "Gaia XI", host: "", bootProfile: "gaiaxi.ini", verified: false,
               note: "No login host published anywhere this project could find — get it from "
                     + "Gaia XI's own launcher.",
               era: "75 cap", population: 276),
        Server(name: "ValhallaXI", host: "45.79.6.92", bootProfile: "valhallaxi.ini",
               verified: false,
               note: "Login host from Valhalla's own connect page — a raw IP, so it may change "
                     + "without this list knowing. Untested by this project.",
               era: "90 cap", population: 216),
        Server(name: "Supernova", host: "login.supernovaffxi.com", bootProfile: "supernova.ini",
               verified: false,
               note: "Login host from Supernova's own Ashita setup guide. Untested by this "
                     + "project.",
               era: "75 cap", population: 155),
        Server(name: "OmicronXI", host: "OmicronFFXI.com", bootProfile: "omicronxi.ini",
               verified: false,
               note: "Heavily customized. Login host from Omicron's own wiki. Untested by this "
                     + "project.",
               era: "99 cap", population: 105),
        Server(name: "Tabula Rasa XI", host: "", bootProfile: "tabularasa.ini", verified: false,
               note: "No login host published anywhere this project could find — get it from "
                     + "their own launcher.",
               era: "75 cap", population: 70),
    ]
}

/// The server list, stored next to the app's other state so the user can edit or extend it.
@MainActor
final class ServerStore: ObservableObject {
    @Published var servers: [Server]
    @Published var selectedID: String

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorizonXI-on-Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    init() {
        let list: [Server]
        if let d = try? Data(contentsOf: Self.url),
           let s = try? JSONDecoder().decode([Server].self, from: d), !s.isEmpty {
            list = Self.merge(saved: s)
        } else {
            list = Server.builtins
        }
        let saved = UserDefaults.standard.string(forKey: "server.selected")
        servers = list
        selectedID = list.first(where: { $0.name == saved })?.name ?? list.first?.name ?? ""
    }

    /// Keep the user's edited hosts, but pick up servers added to `builtins` in later releases.
    private static func merge(saved: [Server]) -> [Server] {
        var out = saved
        for b in Server.builtins where !saved.contains(where: { $0.name == b.name }) {
            out.append(b)
        }
        // refresh the ordering metadata, which is ours to curate, not the user's to maintain
        for i in out.indices {
            if let b = Server.builtins.first(where: { $0.name == out[i].name }) {
                out[i].population = b.population
                out[i].pinned = b.pinned
                out[i].era = b.era
                // Not the user's to edit, and an old servers.json predates the flag entirely.
                out[i].local = b.local
                if b.local { out[i].host = b.host }
            }
        }
        return out
    }

    /// HorizonXI first because Daniel asked for it and because it is the only verified entry;
    /// everything else by community size, largest first. The numbers stay out of the UI.
    var ordered: [Server] {
        servers.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.population != $1.population { return $0.population > $1.population }
            return $0.name < $1.name
        }
    }

    var selected: Server? { servers.first { $0.name == selectedID } }

    func select(_ s: Server) {
        selectedID = s.name
        UserDefaults.standard.set(s.name, forKey: "server.selected")
    }

    func update(_ s: Server) {
        if let i = servers.firstIndex(where: { $0.name == s.name }) { servers[i] = s }
        save()
    }

    func add(name: String, host: String, profile: String) {
        guard !name.isEmpty, !servers.contains(where: { $0.name == name }) else { return }
        servers.append(Server(name: name, host: host,
                              bootProfile: profile.isEmpty ? "horizonxi.ini" : profile,
                              verified: false, note: "Added by you.", era: "", population: 0))
        save()
    }

    func remove(_ s: Server) {
        servers.removeAll { $0.name == s.name }
        if selectedID == s.name { selectedID = ordered.first?.name ?? "" }
        save()
    }

    func save() {
        if let d = try? JSONEncoder().encode(servers) { try? d.write(to: Self.url) }
    }
}
