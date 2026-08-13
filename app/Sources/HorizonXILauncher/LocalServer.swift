import Foundation
import Combine

/// The "Local server (LandSandBoat)" world: a complete FFXI server built from source on this Mac,
/// with the client connecting to 127.0.0.1.
///
/// All of the actual work lives in `scripts/lsb-server.sh` — installing Homebrew dependencies,
/// cloning and building LandSandBoat, creating the database, and running the four server
/// processes. This type is the thin part: it asks that script what state things are in, and runs
/// it when the user presses a button. Keeping the logic in the script means the same steps can be
/// re-run by hand from a terminal when something goes wrong, which is most of the value.
@MainActor
final class LocalServer: ObservableObject {

    /// Everything `lsb-server.sh status` reports. Optional until the first refresh finishes, so
    /// the UI can tell "not checked yet" from "checked and nothing is installed".
    struct Status {
        var root = ""
        var freeGB: Double = 0
        var needGB: Double = 12
        var floorGB: Double = 9
        var spaceOK = false
        var brew = false
        var commandLineTools = false
        var depsMissing: [String] = []
        var source = false
        var built = false
        var dbRunning = false
        var dbReady = false
        var running = false
        var up: [String] = []

        /// Ready to play: built, schema imported, nothing left to install.
        var ready: Bool { built && dbReady }

        /// Below the point where the script refuses to start a build.
        var belowFloor: Bool { freeGB < floorGB }

        /// What setup still has to do, phrased for someone who has not read the script.
        var todo: String {
            if !commandLineTools { return "Apple's command line tools" }
            if !brew { return "Homebrew" }
            if !depsMissing.isEmpty { return depsMissing.joined(separator: ", ") }
            if !source { return "the LandSandBoat source" }
            if !dbReady { return "the game database" }
            if !built { return "the server build" }
            return ""
        }
    }

    @Published private(set) var status: Status?
    @Published private(set) var busy = false
    /// What the busy work is, for the button label.
    @Published private(set) var activity = ""

    /// `lsb-server.sh` ships in the bundle; fall back to the repo copy under `swift run`.
    static func script() -> URL? {
        if let u = Bundle.main.url(forResource: "lsb-server", withExtension: "sh") { return u }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HorizonXILauncher
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // app
            .appendingPathComponent("scripts/lsb-server.sh")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    // MARK: - Status

    private var refreshing = false

    func refresh() {
        // Appearing and selecting the local world both ask for a refresh, and on launch they
        // happen together — without this the app runs the status script twice over.
        guard !refreshing, let script = Self.script() else { return }
        refreshing = true
        Task {
            let text = await Self.capture(script: script, arg: "status")
            self.status = Self.parse(text)
            self.refreshing = false
        }
    }

    private static func parse(_ text: String) -> Status {
        var s = Status()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch parts[0] {
            case "root":        s.root = v
            case "freeGB":      s.freeGB = Double(v) ?? 0
            case "needGB":      s.needGB = Double(v) ?? 12
            case "floorGB":     s.floorGB = Double(v) ?? 9
            case "spaceOK":     s.spaceOK = v == "1"
            case "brew":        s.brew = v == "1"
            case "clt":         s.commandLineTools = v == "1"
            case "depsMissing": s.depsMissing = v.split(separator: " ").map(String.init)
            case "source":      s.source = v == "1"
            case "built":       s.built = v == "1"
            case "dbRunning":   s.dbRunning = v == "1"
            case "dbReady":     s.dbReady = v == "1"
            case "running":     s.running = v == "1"
            case "up":          s.up = v.split(separator: " ").map(String.init)
            default: break
            }
        }
        return s
    }

    private static func capture(script: URL, arg: String) async -> String {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [script.path, arg]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()          // status never needs stderr, and it can be noisy
            do { try p.run() } catch { return "" }
            let d = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: d, encoding: .utf8) ?? ""
        }.value
    }

    // MARK: - Actions

    /// Install dependencies, fetch and build the server, create the database. Long — tens of
    /// minutes on a first run — so everything it does is streamed into the launcher's log.
    func setup(force: Bool = false, log: @escaping (String) -> Void,
               done: @escaping (Bool) -> Void = { _ in }) {
        run("setup", activity: "setting up", env: force ? ["LSB_FORCE": "1"] : [:],
            log: log, done: done)
    }

    func start(log: @escaping (String) -> Void, done: @escaping (Bool) -> Void = { _ in }) {
        run("start", activity: "starting", log: log, done: done)
    }

    func stop(log: @escaping (String) -> Void, done: @escaping (Bool) -> Void = { _ in }) {
        run("stop", activity: "stopping", log: log, done: done)
    }

    private func run(_ arg: String, activity: String, env: [String: String] = [:],
                     log: @escaping (String) -> Void, done: @escaping (Bool) -> Void) {
        guard !busy else { return }
        guard let script = Self.script() else {
            log("!! lsb-server.sh is missing from the app bundle")
            done(false)
            return
        }
        busy = true
        self.activity = activity
        log("==> local server: \(arg)")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, arg]
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        // A GUI app inherits a minimal PATH; the script needs to find brew, git and cmake.
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (e["PATH"] ?? "/usr/bin:/bin")
        p.environment = e

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            Task { @MainActor in log(s) }
        }
        p.terminationHandler = { pr in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                self?.busy = false
                self?.activity = ""
                let ok = pr.terminationStatus == 0
                log("==> local server \(arg) exited \(pr.terminationStatus)")
                self?.refresh()
                done(ok)
            }
        }
        do {
            try p.run()
        } catch {
            busy = false
            self.activity = ""
            log("!! could not run lsb-server.sh: \(error.localizedDescription)")
            done(false)
        }
    }
}
