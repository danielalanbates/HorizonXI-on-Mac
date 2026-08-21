import Foundation
import Combine
import AppKit

/// Runs the repair script and the game itself, streaming output back to the UI.
@MainActor
final class Runner: ObservableObject {
    @Published var log: String = ""
    @Published var running = false
    @Published var busy = false

    private var proc: Process?
    private var x87Proc: Process?
    /// Executable Ashita boots the game in for the current launch (the boot profile's
    /// `[ashita.boot] file`): horizon-loader.exe on HorizonXI, pol.exe on CatsEyeXI, xiloader.exe
    /// elsewhere. Both the exit watcher and the x87 sidecar look for this, by name.
    private var gameExe = "horizon-loader.exe"
    static var currentGameExe = "horizon-loader.exe"

    /// Every FFXI graphics setting at max, 4K resolution. Registry keys documented in
    /// `[ffxi.registry]` of any Ashita boot .ini; mirrors `scripts/max4k.json`, which is the
    /// version the benchmark harness actually validated (25.6 fps in-world, up from an 11.3 fps
    /// pre-x87sidecar baseline). 0001/0002 are screen width/height; the rest are background and
    /// texture resolution, sound channels and mip mapping -- see max4k.json's own comment.
    private static let max4KRegistry: [String: String] = [
        "0000": "6", "0001": "3840", "0002": "2160", "0003": "4096", "0004": "4096",
        "0011": "2", "0018": "2", "0019": "1", "0021": "1", "0029": "20",
        "0007": "1", "0035": "1",
    ]

    /// Raw stream text, which arrives mid-line and unbounded — a whole session of wine and Ashita
    /// output is megabytes, and SwiftUI re-lays-out the entire string on every change, so the cap
    /// matters for responsiveness as much as for memory.
    /// Everything that reaches the log pane also goes to disk, so a failed launch can be read
    /// after the fact (and pasted into a bug report) without scrolling a UI. Overwritten per
    /// app run; the previous run is kept as launcher.log.1.
    static let logFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorizonXI-on-Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("launcher.log")
        let prev = dir.appendingPathComponent("launcher.log.1")
        try? FileManager.default.removeItem(at: prev)
        try? FileManager.default.moveItem(at: f, to: prev)
        FileManager.default.createFile(atPath: f.path, contents: nil)
        return f
    }()
    private lazy var logHandle: FileHandle? = try? FileHandle(forWritingTo: Self.logFile)

    private func tee(_ s: String) {
        guard let h = logHandle, let d = s.data(using: .utf8) else { return }
        h.seekToEndOfFile(); h.write(d)
    }

    /// The boot loader's verdict when a login is refused ("Failed to login. Invalid username or
    /// password." / "…Account already logged in." / "…xiloader version mismatch…"). Every xiloader
    /// fork prints one of these and then sits at an interactive menu that no window ever shows,
    /// so the launcher would otherwise look hung. Surfaced to the UI and the loader is stopped.
    @Published var loginFailure: String = ""
    private var currentInstall: Install?

    func appendChunk(_ s: String) {
        tee(s)
        // Every xiloader fork prints one of these and drops to an interactive menu no window shows.
        let failMarkers = ["Failed to login", "Bad json reply from remote", "Error from remote",
                           "version mismatch", "xi_connect", "Account already logged in"]
        if loginFailure.isEmpty, let hit = failMarkers.first(where: { s.contains($0) }),
           let r = s.range(of: hit) {
            let raw = String(s[r.lowerBound...]).split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? hit
            let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \u{1b}[m")).trimmingCharacters(in: .whitespaces)
            loginFailure = hit == "Bad json reply from remote"
                ? "The login server sent a reply this client could not read. Usually the wrong password, an account that does not exist, or a client-version mismatch."
                : (clean.isEmpty ? hit : clean)
            appendLine("!! login refused: \(loginFailure) — stopping the loader")
            if let i = currentInstall { stop(i) }
        }
        log += s
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    func appendLine(_ s: String) {
        tee(s.hasSuffix("\n") ? s : s + "\n")
        log += s.hasSuffix("\n") ? s : s + "\n"
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    /// install.sh ships inside the app bundle; fall back to the repo copy when running from
    /// `swift run`.
    static func repairScript() -> URL? {
        if let u = Bundle.main.url(forResource: "install", withExtension: "sh") { return u }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HorizonXILauncher
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // app
            .appendingPathComponent("scripts/install.sh")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    func repair(_ install: Install) {
        guard let script = Self.repairScript() else {
            appendLine("!! install.sh not found in the bundle"); return
        }
        busy = true
        appendLine("==> repairing \(install.wrapper.path) [\(install.prefixName)]")
        // Cheap, local, and the difference between "logs in then quits" and a playable game.
        Sandbox.repair(install) { [weak self] in self?.appendLine($0) }
        spawn(URL(fileURLWithPath: "/bin/zsh"),
              args: [script.path, install.wrapper.path, install.prefixName],
              env: [:], cwd: script.deletingLastPathComponent()) { [weak self] code in
            self?.busy = false
            self?.appendLine("==> repair exited \(code)")
        }
    }

    /// `scripts/update-client.sh` ships next to install.sh in the bundle.
    static func updateScript() -> URL? {
        if let u = Bundle.main.url(forResource: "update-client", withExtension: "sh") { return u }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/update-client.sh")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    /// Apply every pending HorizonXI game update (torrent, so it can take a while), then report.
    func updateHorizon(_ install: Install, done: @escaping (Bool) -> Void) {
        guard !busy, !running else { appendLine("!! something else is running in the wrapper — try again when it finishes"); done(false); return }
        guard let script = Self.updateScript() else {
            appendLine("!! update-client.sh not found in the bundle"); done(false); return
        }
        busy = true
        appendLine("==> updating HorizonXI game files in \(install.gameDir.path)")
        var env: [String: String] = [:]
        // aria2c comes from Homebrew; a bundled app's PATH does not include it.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        spawn(URL(fileURLWithPath: "/bin/zsh"),
              args: [script.path, "horizon", install.gameDir.path],
              env: env, cwd: script.deletingLastPathComponent()) { [weak self] code in
            self?.busy = false
            self?.appendLine("==> update exited \(code)")
            done(code == 0)
        }
    }

    /// Run CatsEyeXI's own launcher inside the prefix (scripts/catseye-launcher.sh). Their
    /// client only comes from that launcher; running it under wine is the whole integration.
    /// Make `C:\Games\<name>` inside the prefix point at the folder the user chose, so a Windows
    /// installer's default path lands the files where the launcher will look for them.
    static func linkGamesFolder(_ name: String, to dataPath: String, in install: Install) {
        guard !dataPath.isEmpty else { return }
        let games = install.driveC.appendingPathComponent("Games")
        try? FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        let link = games.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: dataPath))
    }

    /// Make sure the wrapper's installer prefix exists (see `Install.installerPrefix`). Slow the
    /// first time only; runs off the main actor and calls back on it.
    func ensureInstallerPrefix(_ install: Install, then: @escaping (Install) -> Void) {
        let ip = install.installerPrefix
        if FileManager.default.fileExists(atPath: ip.systemReg.path) { then(ip); return }
        appendLine("==> creating \(ip.prefixName) (a second wine prefix for installers, so a download is never killed by Play) — about 30 s")
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = ip.prefix.path; env["WINEDEBUG"] = "-all"
        env.removeValue(forKey: "DYLD_FALLBACK_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_LIBRARY_PATH")
        Task.detached {
            let p = Process()
            p.executableURL = ip.wine; p.arguments = ["wineboot", "-u"]; p.environment = env
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            let k = Process(); k.executableURL = ip.wineserver; k.arguments = ["-k"]; k.environment = ["WINEPREFIX": ip.prefix.path]
            try? k.run(); k.waitUntilExit()
            await MainActor.run { then(ip) }
        }
    }

    /// Download a server's Windows installer and run it inside the *installer* prefix. The user
    /// drives the installer's own UI; `dataPath` is pre-linked as `C:\Games\<name>` for it to
    /// install into (and the same link is made in the game prefix, so a path the installer wrote
    /// into a config file resolves at play time too).
    func runInstaller(from url: URL, in gameInstall: Install, dataPath: String, name: String = "") {
        guard !busy, !running else { return }
        busy = true
        let nm = name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
        Self.linkGamesFolder(nm, to: dataPath, in: gameInstall)
        ensureInstallerPrefix(gameInstall) { [weak self] install in
            guard let self else { return }
            Self.linkGamesFolder(nm, to: dataPath, in: install)
            self.runInstallerNow(from: url, in: install, name: nm)
        }
    }

    private func runInstallerNow(from url: URL, in install: Install, name nm: String) {
        // Installers are big (Eden's is 5.8 GB) and served from places that support ranges, so
        // fetch with curl: resumable (-C -), retried, and its progress bar streams into the log.
        // Saved next to the world's data rather than in the prefix -- that is where the space is.
        let dl = install.driveC.appendingPathComponent("Games/\(nm)/installer-downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        let file = dl.appendingPathComponent(Self.downloadName(for: url, world: nm))
        appendLine("==> downloading \(url.absoluteString)\n    to \(file.path)")
        spawn(URL(fileURLWithPath: "/usr/bin/curl"),
              args: ["-fL", "--retry", "5", "--retry-delay", "3", "-C", "-", "--progress-bar",
                     "-A", "FFXI-on-Mac", "-o", file.path, url.absoluteString],
              env: [:], cwd: dl) { [weak self] code in
            guard let self else { return }
            // curl 33 = server refused the range because the file is already complete.
            guard code == 0 || (code == 33 && FileManager.default.fileExists(atPath: file.path)) else {
                self.appendLine("!! download failed (curl \(code)). If \(nm) has moved its installer, get it from their site and use Run installer….")
                self.busy = false
                if let page = self.installPageFallback { NSWorkspace.shared.open(page) }
                return
            }
            self.appendLine("==> downloaded \(file.lastPathComponent)")
            self.runDownloadedInstaller(file, in: install, name: nm)
        }
    }

    /// Download a plain client archive and unpack it into the world's data folder. No Windows
    /// installer is involved, so nothing has to be driven and no second prefix is needed.
    /// Resumable: a part-downloaded archive is continued, and the size is checked against what
    /// the server reports before unpacking, because a truncated archive that is never verified is
    /// how "Eden didn't work" happened (3.30 GB of 5.77 GB, silently).
    func installClientZip(from url: URL, into dataPath: String, name nm: String) {
        guard !busy, !running else { return }
        guard !dataPath.isEmpty else { appendLine("!! no folder chosen for \(nm)"); return }
        busy = true
        let dest = URL(fileURLWithPath: dataPath, isDirectory: true)
        let dl = dest.appendingPathComponent("installer-downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        let file = dl.appendingPathComponent(Self.downloadName(for: url, world: nm))
        appendLine("==> downloading \(nm)'s client\n    \(url.absoluteString)\n    to \(file.path)")
        spawn(URL(fileURLWithPath: "/usr/bin/curl"),
              args: ["-fL", "--retry", "5", "--retry-delay", "3", "-C", "-", "--progress-bar",
                     "-A", "FFXI-on-Mac", "-o", file.path, url.absoluteString],
              env: [:], cwd: dl) { [weak self] code in
            guard let self else { return }
            guard code == 0 || (code == 33 && FileManager.default.fileExists(atPath: file.path)) else {
                self.appendLine("!! download failed (curl \(code)).")
                self.busy = false
                if let page = self.installPageFallback { NSWorkspace.shared.open(page) }
                return
            }
            self.appendLine("==> unpacking \(file.lastPathComponent) into \(dest.path) — this takes a while for a client-sized archive")
            self.spawn(URL(fileURLWithPath: "/usr/bin/ditto"),
                       args: ["-x", "-k", file.path, dest.path], env: [:], cwd: dest) { [weak self] rc in
                guard let self else { return }
                self.busy = false
                if rc == 0 {
                    self.appendLine("==> \(nm) unpacked. Press ↻ — the checks re-run against the new files.")
                } else {
                    self.appendLine("!! unpacking failed (ditto \(rc)). The archive is kept at \(file.path); a truncated download is the usual cause — run this again and it resumes.")
                }
            }
        }
    }

    /// Where to send the user if the direct download for the world dies (set by the caller).
    var installPageFallback: URL? = nil

    /// A sensible file name for a download whose URL may end in a query string (Google Drive).
    static func downloadName(for url: URL, world: String) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/", last.contains(".") { return last }
        return world.replacingOccurrences(of: " ", with: "") + "-installer.zip"
    }

    /// Unpack a zip if it is one, find the installer .exe, run it.
    private func runDownloadedInstaller(_ file: URL, in install: Install, name nm: String) {
        var exe = file
        let isZip = file.pathExtension.lowercased() == "zip" || Self.looksLikeZip(file)
        if isZip {
            let out = file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-unpacked", isDirectory: true)
            appendLine("==> unpacking \(file.lastPathComponent)")
            try? FileManager.default.removeItem(at: out)
            let d = Process(); d.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); d.arguments = ["-x", "-k", file.path, out.path]
            d.standardOutput = Pipe(); d.standardError = Pipe()
            try? d.run(); d.waitUntilExit()
            guard d.terminationStatus == 0, let found = Self.firstExe(under: out) else {
                appendLine("!! could not unpack \(file.lastPathComponent) or no .exe inside it"); busy = false; return
            }
            exe = found
        }
        launchInstaller(exe: exe, in: install, name: nm)
    }

    static func looksLikeZip(_ file: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? h.close() }
        let d = h.readData(ofLength: 4)
        return d.count == 4 && d[0] == 0x50 && d[1] == 0x4B
    }

    /// Run an installer the user already has on disk (their server's site, Discord, a USB stick)
    /// inside the installer prefix. Zips are unpacked first and the first .exe inside is run.
    func runLocalInstaller(_ file: URL, in gameInstall: Install, dataPath: String, name: String) {
        guard !busy, !running else { return }
        busy = true
        Self.linkGamesFolder(name, to: dataPath, in: gameInstall)
        ensureInstallerPrefix(gameInstall) { [weak self] install in
            guard let self else { return }
            Self.linkGamesFolder(name, to: dataPath, in: install)
            self.runDownloadedInstaller(file, in: install, name: name)
        }
    }

    static func firstExe(under dir: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var hits: [URL] = []
        for case let u as URL in e where u.pathExtension.lowercased() == "exe" { hits.append(u) }
        // Prefer a launcher/installer/setup name at the shallowest depth.
        return hits.sorted { a, b in
            let da = a.pathComponents.count, db = b.pathComponents.count
            if da != db { return da < db }
            let sa = a.lastPathComponent.lowercased(), sb = b.lastPathComponent.lowercased()
            let ka = ["launcher", "install", "setup"].contains { sa.contains($0) }, kb = ["launcher", "install", "setup"].contains { sb.contains($0) }
            if ka != kb { return ka }
            return sa < sb
        }.first
    }

    /// Does this PE identify itself as a Nullsoft (NSIS) installer? Those take `/S` (silent) and
    /// `/D=<dir>` (target), which is the difference between a world that installs unattended and
    /// one that needs somebody sitting in front of a wine window clicking Next. Verified
    /// 2026-08-21 on Eden's `Installer.exe` (NSIS 3.06.1) and FFEra's `FFEraInstaller-Jan2023.exe`
    /// (NSIS 3.08). Note `/D=` is advisory: Eden's script overrides it and installs to its own
    /// `C:\Eden` regardless, which is why `findInstalledClient` runs afterwards.
    static func isNSIS(_ exe: URL) -> Bool {
        guard let d = try? Data(contentsOf: exe, options: .mappedIfSafe) else { return false }
        let needle = Array("Nullsoft.NSIS.exehead".utf8)
        // The marker sits in the manifest near the front of the file; a few MB is plenty and
        // beats mapping a 157 MB installer's worth of pages through a search.
        let window = d.prefix(4 << 20)
        return window.range(of: Data(needle)) != nil
    }

    /// Where a just-run installer actually put the client: the newest folder under the prefix's
    /// `drive_c` (or under the world's own folder) holding an Ashita launcher. Needed because an
    /// NSIS script may ignore `/D=` entirely.
    static func findInstalledClient(in install: Install, world: String) -> URL? {
        let roots = [install.driveC, install.driveC.appendingPathComponent("Games")]
        let fm = FileManager.default
        for root in roots {
            guard let kids = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for kid in kids {
                for probe in ["Ashita-cli.exe", "Ashita/Ashita-cli.exe", "Ashita.exe", "Ashita/Ashita.exe"]
                where fm.fileExists(atPath: kid.appendingPathComponent(probe).path) {
                    return kid
                }
            }
        }
        return nil
    }

    /// Called with the folder an installer left the client in, when one is found.
    var onClientInstalled: ((URL) -> Void)? = nil

    /// Start `exe` under wine in `install` and stream its output. `busy` clears when it exits.
    private func launchInstaller(exe: URL, in install: Install, name nm: String) {
        var args = [Install.winePath(exe, driveC: install.driveC)]
        let silent = Self.isNSIS(exe)
        if silent {
            // /D must be last and unquoted -- that is NSIS's rule, not a preference.
            args += ["/S", "/D=C:\\Games\\" + nm]
            appendLine("==> running \(exe.lastPathComponent) in \(install.prefixName) — Nullsoft installer, running it unattended (/S). Nothing to click; this takes a while for a client-sized payload.")
        } else {
            appendLine("==> running \(exe.lastPathComponent) in \(install.prefixName) — install into C:\\Games\\\(nm)")
        }
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = install.prefix.path; env["WINEDEBUG"] = "-all"
        env.removeValue(forKey: "DYLD_FALLBACK_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_LIBRARY_PATH")
        spawn(install.wine, args: args,
              env: env, cwd: exe.deletingLastPathComponent()) { [weak self] code in
            guard let self else { return }
            self.busy = false
            self.appendLine("==> installer exited \(code)")
            guard let found = Self.findInstalledClient(in: install, world: nm) else {
                if silent { self.appendLine("!! \(nm)'s installer finished but no client folder was found under \(install.driveC.path). Check the log above.") }
                return
            }
            self.appendLine("==> \(nm)'s client is at \(found.path)")
            self.onClientInstalled?(found)
        }
    }

    /// `scripts/retail-client.sh`: Square Enix's free client + PlayOnline update + Ashita/xiloader
    /// (+ the world's patch/DATs) into the world's folder. Bring-your-own-retail worlds only.
    func installRetail(for s: Server, in gameInstall: Install) {
        guard !busy, !running else { return }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/retail-client.sh")
        guard let script = Bundle.main.url(forResource: "retail-client", withExtension: "sh")
                ?? (FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil) else {
            appendLine("!! retail-client.sh not found in the bundle"); return
        }
        busy = true
        Self.linkGamesFolder(s.name, to: s.dataPath, in: gameInstall)
        ensureInstallerPrefix(gameInstall) { [weak self] ip in
            guard let self else { return }
            Self.linkGamesFolder(s.name, to: s.dataPath, in: ip)
            self.appendLine("==> retail client for \(s.name) into \(s.dataPath) (Square Enix's 7.7 GB download, then PlayOnline's update — leave this running)")
            var env: [String: String] = [:]
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            self.spawn(URL(fileURLWithPath: "/bin/zsh"),
                       args: [script.path, ip.wrapper.path, ip.prefixName, s.dataPath, s.name],
                       env: env, cwd: script.deletingLastPathComponent()) { [weak self] code in
                self?.busy = false
                self?.appendLine("==> retail install exited \(code)")
            }
        }
    }

    /// Stop whatever is running in the installer prefix.
    func cancelInstaller(_ gameInstall: Install) {
        let ip = gameInstall.installerPrefix
        let k = Process(); k.executableURL = ip.wineserver; k.arguments = ["-k"]; k.environment = ["WINEPREFIX": ip.prefix.path]
        try? k.run()
        appendLine("==> installer prefix stopped")
    }

    /// Fresh HorizonXI client into `dir` via their published torrent + updates (update-client.sh install).
    func installHorizon(into dir: URL) {
        guard !busy, !running, let script = Self.updateScript() else { return }
        busy = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        appendLine("==> installing HorizonXI into \(dir.path) (9.4 GB torrent — leave this running)")
        var env: [String: String] = [:]
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        spawn(URL(fileURLWithPath: "/bin/zsh"), args: [script.path, "install", dir.path],
              env: env, cwd: script.deletingLastPathComponent()) { [weak self] code in
            self?.busy = false; self?.appendLine("==> install exited \(code)")
        }
    }

    func runCatsEyeLauncher(_ gameInstall: Install, dataPath: String = "") {
        Self.linkGamesFolder("CatsEyeXI", to: dataPath, in: gameInstall)
        guard !busy, !running else { return }
        busy = true
        ensureInstallerPrefix(gameInstall) { [weak self] ip in
            self?.busy = false
            Self.linkGamesFolder("CatsEyeXI", to: dataPath, in: ip)
            self?.runCatsEyeLauncherNow(ip)
        }
    }

    private func runCatsEyeLauncherNow(_ install: Install) {
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/catseye-launcher.sh")
        guard let script = Bundle.main.url(forResource: "catseye-launcher", withExtension: "sh")
                ?? (FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil) else {
            appendLine("!! catseye-launcher.sh not found in the bundle"); return
        }
        busy = true
        appendLine("==> CatsEyeXI launcher in \(install.prefixName)")
        spawn(URL(fileURLWithPath: "/bin/zsh"),
              args: [script.path, install.wrapper.path, install.prefixName],
              env: [:], cwd: script.deletingLastPathComponent()) { [weak self] code in
            self?.busy = false
            self?.appendLine("==> CatsEyeXI launcher exited \(code)")
        }
    }

    func launch(_ install: Install, perf: PerfSettings, profile: String = "horizonxi.ini",
                useX87: Bool = true) {
        guard !running else { return }
        running = true
        loginFailure = ""
        currentInstall = install
        // The renderer lives in the prefix's registry and DLLs, not in the environment, so it has
        // to be written before the process starts — and after any wineserver holding the old copy
        // of the registry has exited.
        // A wrapper that has been copied or moved still has its dylib links aimed at the old
        // copy; fix that before anything tries to load one. See relinkStrayDylibs.
        RendererSetup.relinkStrayDylibs(install) { [weak self] in self?.appendLine($0) }
        RendererSetup.apply(perf.renderer, to: install) { [weak self] in self?.appendLine($0) }
        // Same moment, same reason: the registry has to name *this* world's SquareEnix folder.
        GameRegistry.point(install) { [weak self] in self?.appendLine($0) }
        Self.cleanStaleWineSockets()
        gameExe = Credentials.bootLoaderName(in: install, profile: profile) ?? "horizon-loader.exe"
        Self.currentGameExe = gameExe
        Credentials.applyIniOverrides(perf.renderer.iniOverrides, to: install, profile: profile)
        // Launching with Sandbox loaded and its interface bypass off produces the worst failure
        // this project has: a clean login followed by a silent exit, no window, no error. Put it
        // back rather than letting the user hit that. See Sandbox.swift.
        if Sandbox.isBroken(install, profile: profile) {
            Sandbox.repair(install) { [weak self] in self?.appendLine($0) }
        }
        // The local server is the one everything else here is a test against (see
        // docs/X87-WALL.md and scripts/max4k.json, which this mirrors) -- 4K, every graphics
        // setting maxed. Never applied to a live server profile: that would silently change
        // someone's real account's display settings out from under them.
        if profile == "lsb.ini" {
            Credentials.applyIniOverrides(Self.max4KRegistry, to: install, profile: profile)
        }
        // Every launch: make sure no addon can take the LuaJIT trace-patch fault that Ashita 4.3
        // hits on this Mac (see LuaJITGuard). Idempotent, so this is cheap after the first run.
        LuaJITGuard.apply(install) { [weak self] in self?.appendLine($0) }
        appendLine("==> launching \(install.bootProfileName(profile)) (Ashita \(install.ashitaGeneration.rawValue))")
        var env = perf.environment(for: install)
        // x87 acceleration, two generations:
        //  * Cooperative (preferred): x87sidecar --cooperative launching the patched CX wine
        //    (athei/wine-build at COOP_WINE). Every wine process — including horizon-loader,
        //    a *grandchild* via Ashita — does its own handshake and flushes its own i-cache,
        //    which is the only reliable way since macOS 26.5.2's Rosetta. No entitlements.
        //  * attach-by-pid (legacy, x87sidecar_entitled in Resources): broken on 26.5.2 —
        //    cross-process i-cache flush is unreliable, the client page-faults minutes after
        //    attach. Kept only as a fallback for older macOS; the binary is currently NOT
        //    bundled for that reason.
        // ROSETTA_DISABLE_AOT only pays off when a sidecar actually patches x87; without one
        // it forces Rosetta's slow path and costs ~half the stock frame rate (measured
        // 2026-08-19: ~5 fps vs ~11 stock). Set it only when acceleration will engage.
        // A world may have to run without x87 acceleration (see Server.x87).
        // x87 acceleration is OFF by default as of 2026-08-21, because measuring it on this
        // macOS (26.5.2) says every version of it is now a large net loss:
        //
        //   no sidecar, Rosetta AOT enabled ............ median 58.0 fps
        //   cooperative sidecar + ROSETTA_DISABLE_AOT ... median  3.0 fps
        //   attach-by-pid + ROSETTA_DISABLE_AOT ......... client dies ~5s after launch
        //
        // (Same 382-draw screen, same settings, 60 samples each, DXVK_FPS_LOG.) The mechanism is
        // not subtle: ROSETTA_DISABLE_AOT is what makes the sidecar's hook reachable, and it
        // forces Rosetta's slow path on everything. That is a fine trade when the JIT engages --
        // it was worth 2.5x in-world when attach-by-pid worked -- and a catastrophic one when it
        // does not. It does not: the cooperative handshake now fails outright
        // ("[rosettax87] cooperative handshake receive failed ... (ipc/rcv) timed out"), so the
        // client pays the AOT penalty and gets nothing back.
        //
        // Set FFXI_ON_MAC_X87=1 to opt back in while working on it. See docs/X87-WALL.md.
        let x87Wanted = useX87 && ProcessInfo.processInfo.environment["FFXI_ON_MAC_X87"] == "1"
        let coop = x87Wanted ? X87Sidecar.cooperative() : nil
        if !useX87 {
            appendLine("i  x87 acceleration is off for this world — its client exits at boot with it on.")
        } else if !x87Wanted {
            appendLine("i  x87 sidecar disabled: it costs ~19x on this macOS (docs/X87-WALL.md). "
                       + "FFXI_ON_MAC_X87=1 re-enables it.")
        }
        if x87Wanted, coop != nil {
            for (k, v) in X87Sidecar.requiredEnvironment { env[k] = v }
        }
        // Spawned through a shell with a *file* redirect, not Foundation.Process pipes.
        // 2026-08-19: after the wrapper moved to the x10, every game launched the old way died
        // one second after "Connected to server!" — while a byte-identical spawn (same exe,
        // args, cwd, and the full 58-variable environment, verified via last-spawn.txt) from a
        // shell with stdout on a file ran to character select every single time. Sidecar off,
        // wineserver stopped, strays killed — the only surviving difference was how Foundation
        // wires the child. So launch the way that demonstrably works and tail the file for the
        // log pane.
        let exe: URL
        let args: [String]
        // Ashita v4 injects with `Ashita-cli.exe <profile>.ini`; Eden's v3 client with
        // `injector.exe <profile>.xml`. Same shape, different names — see Install.AshitaGeneration.
        let injector = install.gameDirWine + "\\" + install.ashitaCLI.lastPathComponent
        let bootFile = install.bootProfileName(profile)
        if let coop {
            // The sidecar lives exactly as long as the process it launched. Launching the
            // injector directly means it lives ~2 seconds: Ashita-cli.exe injects and exits,
            // the sidecar follows it out, and the client Ashita just spawned is left running
            // with nothing to handshake with -- the 5 fps. Give the sidecar a child that
            // outlives the injector instead: run the injector, then idle until the client
            // process is gone. Every wine process the patched CX wine starts in between
            // re-execs through this same sidecar and does its own handshake.
            let cmd = shellQuote(coop.wine.path) + " " + shellQuote(injector) + " "
                + shellQuote(bootFile)
                + "; while /usr/bin/pgrep -qf " + shellQuote(Self.currentGameExe)
                + "; do /bin/sleep 5; done"
            exe = coop.sidecar
            args = ["--cooperative", "/bin/sh", "-c", cmd]
            appendLine("==> x87 cooperative: \(coop.wine.path) (sidecar held open for the client)")
        } else {
            exe = install.wine
            args = [injector, bootFile]
        }
        spawnViaShell(exe,
              args: args,
              env: env,
              cwd: install.gameDir) { [weak self] code in
            // This is Ashita-cli.exe, the *injector*. It exits within seconds of a successful
            // injection, while the game carries on in horizon-loader.exe -- so its exit is not
            // the game's exit, and tearing down the sidecar here killed the client roughly ten
            // seconds after every launch ("connects to nothing, window never appears"). Wait for
            // the actual client process instead.
            self?.appendLine("==> injector exited \(code)")
            self?.watchGameProcess()
        }
        // The game runs in a child process (horizon-loader.exe) that does not exist yet at this
        // point -- Ashita-cli.exe has to inject into it first. Attach as soon as it is safe
        // (X87Sidecar waits for the pid plus a short injection grace): Rosetta caches its
        // translations, so any code translated before the sidecar attaches keeps the slow x87
        // path for the life of the process. A late attach "works" but leaves most of the game
        // at stock speed. (The 2026-08-19 attach crashes were a stale sidecar binary built for
        // pre-26.5.2 Rosetta, not the timing — rebuild the sidecar after every macOS update.)
        // Cooperative mode needs no attach at all: the patched wine handshakes on its own.
        if x87Wanted, coop == nil, X87Sidecar.binary() != nil {
            Task { [weak self] in
                let p = await X87Sidecar.attachWhenReady { [weak self] in self?.appendLine($0) }
                self?.x87Proc = p
            }
        }
    }

    /// Poll for the client itself, and only tear the sidecar down once it is really gone.
    /// x87sidecar holds a live patch inside the target's Rosetta translation; terminating it
    /// while the game is running takes the game with it.
    private func watchGameProcess() {
        Task { [weak self] in
            // Give the injector's child a moment to appear before deciding it never did.
            for _ in 0..<300 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Self.gameIsRunning() { break }
            }
            // Two consecutive misses, because pgrep can miss the process for a beat while wine
            // re-execs it during start-up.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Self.gameIsRunning() { self?.watchGameProcess(); return }
            await MainActor.run {
                guard let self else { return }
                self.running = false
                self.appendLine("==> game exited")
                self.x87Proc?.terminate()
                self.x87Proc = nil
            }
        }
    }

    private static func gameIsRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", currentGameExe]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// `RendererSetup.apply` just did `wineserver -k` and waited for it to actually exit, so any
    /// `server-*` socket directory left under `/tmp/.wine-<uid>/` at this point belongs to a
    /// wineserver that is no longer running -- not necessarily this launch's, since the same
    /// crash or force-kill that orphans one can orphan others. A stale socket there makes the
    /// *next* launch's injection intermittently corrupt itself ("wine client error: write: Bad
    /// file descriptor", "Injection failed!") without ever touching wine's own cleanup path,
    /// because Ashita-cli connects to whatever socket file it finds rather than starting fresh.
    /// This app is the only wine user on the machine, so clearing all of them here is safe.
    private static func cleanStaleWineSockets() {
        // Only when no wineserver is alive: deleting the socket dir of a *live* server (one the
        // user's own manual wine session started, say) orphans every process attached to it.
        let chk = Process()
        chk.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        chk.arguments = ["-x", "wineserver"]
        chk.standardOutput = Pipe(); chk.standardError = Pipe()
        if (try? chk.run()) != nil { chk.waitUntilExit(); if chk.terminationStatus == 0 { return } }
        let dir = URL(fileURLWithPath: "/tmp/.wine-\(getuid())")
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for kid in kids where kid.lastPathComponent.hasPrefix("server-") {
            try? FileManager.default.removeItem(at: kid)
        }
    }

    func stop(_ install: Install) {
        x87Proc?.terminate()
        x87Proc = nil
        proc?.terminate()
        let k = Process()
        k.executableURL = install.wineserver
        k.arguments = ["-k"]
        k.environment = ["WINEPREFIX": install.prefix.path]
        try? k.run()
    }

    /// See the call site in `launch`: the game must be started the way a shell starts it.
    /// stdout/stderr go to a temp file that a DispatchSource tails into the log pane, so the
    /// child never holds a Foundation pipe. The tail keeps reading until the file stops growing
    /// *and* the game is gone, because horizon-loader outlives the injector this spawns.
    /// Single-quote one word for /bin/sh. The cooperative launch builds a small shell command
    /// (run the injector, then idle while the client lives), and every path in it can contain
    /// spaces -- the wine wrapper lives under "/Volumes/Video Games/…" on this Mac.
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func spawnViaShell(_ exe: URL, args: [String], env: [String: String], cwd: URL,
                               done: @escaping (Int32) -> Void) {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffxi-on-mac-game-\(getpid()).log")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let quoted = ([exe.path] + args).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "exec \(quoted) >> '\(out.path)' 2>&1"]
        p.currentDirectoryURL = cwd
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        p.environment = e
        // Record exactly what was spawned. Diffing this against a hand-run that works is how
        // the launch-death and Gaia XI exits were bisected; it costs one small file per launch.
        let spawnLog = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorizonXI-on-Mac/last-spawn.txt")
        let dump = "exe: \(exe.path)\nargs: \(args)\ncwd: \(cwd.path)\n"
            + e.keys.sorted().map { "\($0)=\(e[$0] ?? "")" }.joined(separator: "\n") + "\n"
        try? dump.write(to: spawnLog, atomically: true, encoding: .utf8)
        p.terminationHandler = { pr in
            Task { @MainActor in done(pr.terminationStatus) }
        }
        // Tail the file: poll is plenty (the pane is human-read), and unlike a pipe it cannot
        // block the writer.
        let handle = try? FileHandle(forReadingFrom: out)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
        timer.setEventHandler { [weak self] in
            guard let d = try? handle?.read(upToCount: 1 << 16), !d.isEmpty,
                  let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendChunk(s) }
        }
        timer.resume()
        tailTimer?.cancel()
        tailTimer = timer
        do {
            try p.run()
            proc = p
        } catch {
            appendLine("!! failed to start \(exe.path): \(error.localizedDescription)")
            timer.cancel()
            done(-1)
        }
    }

    private var tailTimer: DispatchSourceTimer?

    private func spawn(_ exe: URL, args: [String], env: [String: String], cwd: URL,
                       done: @escaping (Int32) -> Void) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.currentDirectoryURL = cwd
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        p.environment = e
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        // The pipe has to keep being drained for as long as *anything* is writing to it, and
        // that outlives this process: horizon-loader.exe inherits these descriptors from
        // Ashita-cli.exe and keeps logging into them for the whole session. Dropping the reader
        // when the injector exited left the game writing into a pipe nobody emptied -- 64 KB
        // later it blocked in write() forever, which looked exactly like the client freezing on
        // the HorizonXI splash screen. Read to EOF instead, which is when the last writer has
        // closed, and never key it off a process exit.
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }   // EOF
            guard let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.appendChunk(s) }
        }
        p.terminationHandler = { pr in
            Task { @MainActor in done(pr.terminationStatus) }
        }
        do {
            try p.run()
            proc = p
        } catch {
            appendLine("!! failed to start \(exe.path): \(error.localizedDescription)")
            done(-1)
        }
    }
}
