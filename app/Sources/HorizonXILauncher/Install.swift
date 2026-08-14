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
    var frameworks: URL { wrapper.appendingPathComponent("Contents/Frameworks") }
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

    // MARK: - Remembering the last good install

    private static let key = "install.last"

    /// The install used last time, if it is still on disk. Lets the UI be usable before the
    /// volume scan finishes.
    static func remembered() -> Install? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = s.components(separatedBy: "#")
        guard parts.count == 2 else { return nil }
        let i = Install(wrapper: URL(fileURLWithPath: parts[0]), prefixName: parts[1])
        return FileManager.default.fileExists(atPath: i.gameDir.path) ? i : nil
    }

    func remember() {
        UserDefaults.standard.set(id, forKey: Self.key)
    }

    // MARK: - Discovery

    /// Search the usual places for a wrapper .app that contains a wine build and a HorizonXI client.
    /// Deliberately shallow: a full-disk crawl on an 8GB machine is not worth it.
    static func discover() -> [Install] {
        let fm = FileManager.default
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            // Wrapper apps are large, so people keep them with their games rather than in
            // /Applications. Missing this one is why the launcher was running the copy on an
            // external drive while an identical install sat on the internal SSD.
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Games"),
            // Downloads is deliberately *not* scanned -- see `tccGatedNames`. An install that
            // really is in Downloads is reached by the "Choose install…" button instead.
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
        // Rank by how many preconditions the prefix already satisfies, so a half-finished
        // experiment never outranks a configured one. Equal scores fall back to name order,
        // which puts the plain `prefixNN` prefixes ahead of suffixed experiments.
        return found.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            // An install on an external volume works right up until the drive is unplugged, and
            // it reads slower besides. Prefer an equally-good one on the internal disk.
            let ea = a.wrapper.path.hasPrefix("/Volumes/"), eb = b.wrapper.path.hasPrefix("/Volumes/")
            if ea != eb { return !ea }
            return a.prefixName < b.prefixName
        }
    }

    /// Every install a given wrapper .app holds, whether or not it sits anywhere `discover()`
    /// looks. This is what the "Choose install…" button hands its result to.
    static func installs(inWrapper app: URL) -> [Install] {
        let fm = FileManager.default
        let shared = app.appendingPathComponent("Contents/SharedSupport")
        guard fm.isExecutableFile(atPath: shared.appendingPathComponent("wine/bin/wine").path),
              let kids = try? fm.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil)
        else { return [] }
        return kids
            .filter { $0.lastPathComponent.hasPrefix("prefix") }
            .map { Install(wrapper: app, prefixName: $0.lastPathComponent) }
            .filter { fm.fileExists(atPath: $0.gameDir.path) }
            .sorted { $0.prefixName < $1.prefixName }
    }

    private static func score(_ i: Install) -> Int {
        Preflight.run(i).reduce(0) { $0 + ($1.state == .ok ? 1 : 0) }
    }

    /// Directories macOS gates behind TCC. Touching one at all — even just asking whether it is
    /// a directory — pops "FFXI-on-Mac would like to access files in your Downloads folder"
    /// before the user has pressed anything, which is a terrible first thing for a game launcher
    /// to do. They are never scanned; the "Choose install…" button reaches them instead, and
    /// picking through a panel is what actually grants the access.
    ///
    /// Matched by name rather than by path: `/Volumes` holds an entry for the boot volume, so the
    /// volume scan reaches `/Volumes/Macintosh HD/Users/<user>/` and arrives at the same folders
    /// from the other side — and that entry is an APFS *firmlink*, which
    /// `resolvingSymlinksInPath()` does not collapse, so the two spellings never compare equal.
    ///
    /// **This does not yet make the prompt go away, and the launcher still raises it on first
    /// run.** Measured 2026-08-14: removing Downloads from `roots`, then adding both guards
    /// below, then disabling the `/Volumes` scan entirely, all still produced the prompt, so the
    /// access is somewhere else and is not yet identified. The guards are kept because skipping
    /// three folders the game is never installed in is free and correct either way. Whoever
    /// picks this up: find the actual accessor first (`sudo fs_usage -w -f filesys` filtered to
    /// the launcher's pid catches it; `log stream` on a TCC predicate did not).
    private static let tccGatedNames: Set<String> = ["Downloads", "Desktop", "Documents"]

    private static func appsUnder(_ root: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        guard !tccGatedNames.contains(root.lastPathComponent) else { return [] }
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: root,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for kid in kids {
            // Checked before asking anything about the file: even a metadata query against a
            // gated folder is enough to raise the prompt.
            if tccGatedNames.contains(kid.lastPathComponent) { continue }
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
