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
              args: ["C:\\HorizonXI\\Ashita-cli.exe", profile],
              env: env,
              cwd: install.gameDir) { [weak self] code in
            self?.running = false
            self?.appendLine("==> game exited \(code)")
            self?.x87Proc?.terminate()
            self?.x87Proc = nil
        }
        // The game runs in a child process (horizon-loader.exe) that does not exist yet at this
        // point -- Ashita-cli.exe has to inject into it first. Wait for it off the main actor,
        // then attach; see X87Sidecar.attachWhenReady.
        Task { [weak self] in
            let p = await X87Sidecar.attachWhenReady { [weak self] in self?.appendLine($0) }
            self?.x87Proc = p
        }
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
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.log += s }
        }
        p.terminationHandler = { pr in
            pipe.fileHandleForReading.readabilityHandler = nil
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
