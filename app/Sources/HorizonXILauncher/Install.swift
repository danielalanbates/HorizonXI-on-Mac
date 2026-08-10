import Foundation

/// Locating and describing a Sikarugir/Kegworks-style wine wrapper that holds the HorizonXI prefix.
struct Install: Identifiable, Hashable {
    let wrapper: URL          // .../siku.app
    let prefixName: String    // e.g. prefix10

    var id: String { wrapper.path + "#" + prefixName }

    var sharedSupport: URL { wrapper.appendingPathComponent("Contents/SharedSupport") }
    var wine: URL { sharedSupport.appendingPathComponent("wine/bin/wine") }
    var wineserver: URL { sharedSupport.appendingPathComponent("wine/bin/wineserver") }
    var prefix: URL { sharedSupport.appendingPathComponent(prefixName) }
    var driveC: URL { prefix.appendingPathComponent("drive_c") }
    var gameDir: URL { driveC.appendingPathComponent("HorizonXI") }
    var squareEnix: URL { gameDir.appendingPathComponent("SquareEnix") }
    var ashitaCLI: URL { gameDir.appendingPathComponent("Ashita-cli.exe") }
    var d3dMetal: URL { wrapper.appendingPathComponent("Contents/Frameworks/renderer/d3dmetal/external") }
    var systemReg: URL { prefix.appendingPathComponent("system.reg") }

    /// Volume the wrapper lives on — the usual failure is that it simply is not mounted.
    var volume: URL? {
        let parts = wrapper.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return URL(fileURLWithPath: "/") }
        return URL(fileURLWithPath: "/\(parts[1])/\(parts[2])")
    }

    var isMounted: Bool {
        guard let v = volume else { return false }
        return FileManager.default.fileExists(atPath: v.path)
    }

    // MARK: - Discovery

    /// Search the usual places for a wrapper .app that contains a wine build and a HorizonXI client.
    /// Deliberately shallow: a full-disk crawl on an 8GB machine is not worth it.
    static func discover() -> [Install] {
        let fm = FileManager.default
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
                                                  includingPropertiesForKeys: nil) {
            roots.append(contentsOf: vols)
        }

        var found: [Install] = []
        var seen = Set<String>()

        for root in roots {
            for app in appsUnder(root, depth: 3) {
                guard seen.insert(app.path).inserted else { continue }
                let shared = app.appendingPathComponent("Contents/SharedSupport")
                guard fm.isExecutableFile(atPath: shared.appendingPathComponent("wine/bin/wine").path)
                else { continue }
                guard let kids = try? fm.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil)
                else { continue }
                for kid in kids where kid.lastPathComponent.hasPrefix("prefix") {
                    let candidate = Install(wrapper: app, prefixName: kid.lastPathComponent)
                    if fm.fileExists(atPath: candidate.gameDir.path) { found.append(candidate) }
                }
            }
        }
        // Prefer prefixes whose client is actually present and largest-numbered (newest attempt).
        return found.sorted { $0.prefixName > $1.prefixName }
    }

    private static func appsUnder(_ root: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: root,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for kid in kids {
            let isDir = (try? kid.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            if kid.pathExtension == "app" {
                out.append(kid)
            } else {
                out.append(contentsOf: appsUnder(kid, depth: depth - 1))
            }
        }
        return out
    }
}
