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

    /// Seeded from the community-maintained directory at github.com/XiPrivateServers/Servers
    /// plus public population trackers (August 2026). Hosts marked unverified are the *web*
    /// domains those projects publish — the actual login host often differs and must come from
    /// that server's own installer, which is why the field is editable.
    static let builtins: [Server] = [
        Server(name: "HorizonXI", host: "play.horizonxi.com", bootProfile: "horizonxi.ini",
               verified: true,
               note: "The server this project was built and tested against.",
               era: "Chains of Promathia · 75 cap", population: 9500, pinned: true),
        Server(name: "Eden", host: "", bootProfile: "eden.ini", verified: false,
               note: "Retail-like. Login host comes from Eden's own installer.",
               era: "Wings of the Goddess · 75 cap", population: 4200),
        Server(name: "CatsEyeXI", host: "", bootProfile: "catseyexi.ini", verified: false,
               note: "Custom content. Host comes from their launcher.",
               era: "Custom · 75 cap", population: 2600),
        Server(name: "Nasomi", host: "", bootProfile: "nasomi.ini", verified: false,
               note: "Classic. Uses its own loader; likely needs extra work.",
               era: "Wings of the Goddess · 75 cap", population: 2100),
        Server(name: "Omega", host: "", bootProfile: "omega.ini", verified: false,
               note: "Retail-like rates.", era: "Wings of the Goddess · 75 cap", population: 1500),
        Server(name: "Era", host: "", bootProfile: "era.ini", verified: false,
               note: "Custom content.", era: "Wings of the Goddess · 75 cap", population: 1200),
        Server(name: "WingsXI", host: "", bootProfile: "wings.ini", verified: false,
               note: "Community server.", era: "Wings of the Goddess", population: 900),
        Server(name: "Gaia XI", host: "", bootProfile: "gaiaxi.ini", verified: false,
               note: "Custom content.", era: "Wings of the Goddess · 75 cap", population: 700),
        Server(name: "Valhalla", host: "", bootProfile: "valhalla.ini", verified: false,
               note: "Custom content.", era: "Abyssea · 90 cap", population: 500),
        Server(name: "Demiurge", host: "", bootProfile: "demiurge.ini", verified: false,
               note: "Custom content.", era: "Chains of Promathia · 75 cap", population: 400),
        Server(name: "Supernova", host: "", bootProfile: "supernova.ini", verified: false,
               note: "Custom content.", era: "Wings of the Goddess · 75 cap", population: 300),
        Server(name: "LevelDown", host: "", bootProfile: "leveldown.ini", verified: false,
               note: "Custom content, all expansions.", era: "All expansions · 99 cap", population: 250),
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
