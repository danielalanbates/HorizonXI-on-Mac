import Foundation
import Combine

/// Runs the repair script and the game itself, streaming output back to the UI.
@MainActor
final class Runner: ObservableObject {
    @Published var log: String = ""
    @Published var running = false
    @Published var busy = false

    private var proc: Process?

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
        Credentials.applyIniOverrides(perf.renderer.iniOverrides, to: install, profile: profile)
        appendLine("==> launching \(profile)")
        spawn(install.wine,
              args: ["C:\\HorizonXI\\Ashita-cli.exe", profile],
              env: perf.environment(for: install),
              cwd: install.gameDir) { [weak self] code in
            self?.running = false
            self?.appendLine("==> game exited \(code)")
        }
    }

    func stop(_ install: Install) {
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
