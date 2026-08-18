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

    /// Start `exe` under wine in `install` and stream its output. `busy` clears when it exits.
    private func launchInstaller(exe: URL, in install: Install, name nm: String) {
        appendLine("==> running \(exe.lastPathComponent) in \(install.prefixName) — install into C:\\Games\\\(nm)")
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = install.prefix.path; env["WINEDEBUG"] = "-all"
        env.removeValue(forKey: "DYLD_FALLBACK_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_LIBRARY_PATH")
        spawn(install.wine, args: [Install.winePath(exe, driveC: install.driveC)],
              env: env, cwd: exe.deletingLastPathComponent()) { [weak self] code in
            self?.busy = false
            self?.appendLine("==> installer exited \(code)")
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

    func launch(_ install: Install, perf: PerfSettings, profile: String = "horizonxi.ini") {
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
        appendLine("==> launching \(profile)")
        var env = perf.environment(for: install)
        for (k, v) in X87Sidecar.requiredEnvironment { env[k] = v }
        spawn(install.wine,
              args: [install.gameDirWine + "\\Ashita-cli.exe", profile],
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
        // point -- Ashita-cli.exe has to inject into it first. Wait for it off the main actor,
        // then attach; see X87Sidecar.attachWhenReady.
        Task { [weak self] in
            let p = await X87Sidecar.attachWhenReady { [weak self] in self?.appendLine($0) }
            self?.x87Proc = p
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
