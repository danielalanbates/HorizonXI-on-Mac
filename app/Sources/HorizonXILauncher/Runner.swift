import Foundation
import Combine

/// Runs the repair script and the game itself, streaming output back to the UI.
@MainActor
final class Runner: ObservableObject {
    @Published var log: String = ""
    @Published var running = false
    @Published var busy = false

    private var proc: Process?
    private var x87Proc: Process?

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
    func appendChunk(_ s: String) {
        log += s
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    func appendLine(_ s: String) {
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
        guard !busy, !running, let script = Self.updateScript() else {
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

    /// Download a server's Windows installer and run it inside the prefix. The user drives the
    /// installer's own UI; `dataPath` is pre-linked as `C:\Games\<name>` for it to install into.
    func runInstaller(from url: URL, in install: Install, dataPath: String, name: String = "") {
        guard !busy, !running else { return }
        busy = true
        let nm = name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
        Self.linkGamesFolder(nm, to: dataPath, in: install)
        let dl = install.driveC.appendingPathComponent("Installers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        let exe = dl.appendingPathComponent(url.lastPathComponent.isEmpty ? "installer.exe" : url.lastPathComponent)
        appendLine("==> downloading \(url.absoluteString)")
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, err in
            Task { @MainActor in
                guard let self else { return }
                guard let tmp, err == nil else {
                    self.appendLine("!! download failed: \(err?.localizedDescription ?? "?")"); self.busy = false; return
                }
                try? FileManager.default.removeItem(at: exe)
                do { try FileManager.default.moveItem(at: tmp, to: exe) } catch {
                    self.appendLine("!! could not save installer: \(error.localizedDescription)"); self.busy = false; return
                }
                self.appendLine("==> running \(exe.lastPathComponent) in \(install.prefixName) — install into C:\\Games\\\(nm)")
                var env = ProcessInfo.processInfo.environment
                env["WINEPREFIX"] = install.prefix.path; env["WINEDEBUG"] = "-all"
                env.removeValue(forKey: "DYLD_FALLBACK_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_LIBRARY_PATH")
                self.spawn(install.wine, args: ["Z:" + exe.path.replacingOccurrences(of: "/", with: "\\")],
                           env: env, cwd: dl) { [weak self] code in
                    self?.busy = false
                    self?.appendLine("==> installer exited \(code)")
                }
            }
        }
        task.resume()
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

    func runCatsEyeLauncher(_ install: Install, dataPath: String = "") {
        Self.linkGamesFolder("CatsEyeXI", to: dataPath, in: install)
        guard !busy, !running else { return }
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
        // The renderer lives in the prefix's registry and DLLs, not in the environment, so it has
        // to be written before the process starts — and after any wineserver holding the old copy
        // of the registry has exited.
        RendererSetup.apply(perf.renderer, to: install) { [weak self] in self?.appendLine($0) }
        Self.cleanStaleWineSockets()
        Credentials.applyIniOverrides(perf.renderer.iniOverrides, to: install, profile: profile)
        // The local server is the one everything else here is a test against (see
        // docs/X87-WALL.md and scripts/max4k.json, which this mirrors) -- 4K, every graphics
        // setting maxed. Never applied to a live server profile: that would silently change
        // someone's real account's display settings out from under them.
        if profile == "lsb.ini" {
            Credentials.applyIniOverrides(Self.max4KRegistry, to: install, profile: profile)
        }
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
        p.arguments = ["-f", "horizon-loader.exe"]
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
