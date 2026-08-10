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
    /// Optional note shown under the server buttons.
    var note: String

    static let builtins: [Server] = [
        Server(name: "HorizonXI", host: "play.horizonxi.com", bootProfile: "horizonxi.ini",
               verified: true, note: "75-era. The server this project was built and tested against."),
        Server(name: "Eden", host: "", bootProfile: "eden.ini",
               verified: false, note: "75-era. Fill in the login host from Eden's own installer."),
        Server(name: "CatsEyeXI", host: "", bootProfile: "catseyexi.ini",
               verified: false, note: "Custom-content server. Host comes from their launcher."),
        Server(name: "Nasomi", host: "", bootProfile: "nasomi.ini",
               verified: false, note: "Classic 75-era. Uses its own loader; likely needs extra work."),
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
            list = s
        } else {
            list = Server.builtins
        }
        let saved = UserDefaults.standard.string(forKey: "server.selected")
        servers = list
        selectedID = list.first(where: { $0.name == saved })?.name ?? list.first?.name ?? ""
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
                              verified: false, note: "Added by you."))
        save()
    }

    func remove(_ s: Server) {
        servers.removeAll { $0.name == s.name }
        if selectedID == s.name { selectedID = servers.first?.name ?? "" }
        save()
    }

    func save() {
        if let d = try? JSONEncoder().encode(servers) { try? d.write(to: Self.url) }
    }
}
