import Foundation

/// One-shot performance captures armed by `scripts/harness/capture-performance.py`.
///
/// The recorder writes a small request into Application Support, then waits for the user to
/// press Play normally. Reading the request here lets every Wine child inherit the DXVK probe
/// paths without teaching the recorder about account credentials or reconstructing the launch.
enum PerformanceDiagnostics {
    struct Request: Codable {
        let session: String
        let expiresAt: TimeInterval
        let gameDirectory: String
        let level: String
    }

    struct Capture {
        let session: String
        let directory: URL
        let level: String
        let environment: [String: String]
    }

    static let requestName = "performance-capture-request.json"
    static let captureDirectoryName = "performance-captures"

    static func requestURL(in applicationSupport: URL? = nil) -> URL {
        let support = applicationSupport ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("HorizonXI-on-Mac", isDirectory: true)
            .appendingPathComponent(requestName)
    }

    /// Consume an unexpired request for this install and return the environment for its next
    /// launch. Requests for another world remain armed instead of attaching to the wrong game.
    static func consume(
        for gameDirectory: URL,
        gameDirectoryWine: String,
        applicationSupport: URL? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Capture? {
        let requestFile = requestURL(in: applicationSupport)
        guard let data = try? Data(contentsOf: requestFile),
              let request = try? JSONDecoder().decode(Request.self, from: data) else { return nil }

        guard validSession(request.session) else {
            try? FileManager.default.removeItem(at: requestFile)
            return nil
        }
        guard request.expiresAt >= now else {
            try? FileManager.default.removeItem(at: requestFile)
            return nil
        }
        guard samePath(request.gameDirectory, gameDirectory.path) else { return nil }

        let level: String
        switch request.level {
        case "deep", "standard-nosample": level = request.level
        default: level = "standard"
        }
        let directory = gameDirectory.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent(captureDirectoryName, isDirectory: true)
            .appendingPathComponent(request.session, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("request.json"), options: .atomic)
            try FileManager.default.removeItem(at: requestFile)
        } catch {
            return nil
        }

        let wineDirectory = gameDirectoryWine + "\\logs\\" + captureDirectoryName
            + "\\" + request.session
        func output(_ name: String) -> String { wineDirectory + "\\" + name }
        // These probes aggregate once per second and have low enough overhead for normal play.
        // Unknown variables are ignored by older diagnostic DLLs, which keeps the capture usable
        // while comparing more than one build.
        var environment = [
            "DXVK_FPS_LOG": output("fps.csv"),
            "DXVK_PRESENT_PROBE": output("present.csv"),
            "DXVK_PRESENT_STAGE_LOG": output("present-stages.csv"),
            "DXVK_SUBMIT_STAGE_LOG": output("submit-stages.csv"),
            "DXVK_UP_STAGE_LOG": output("draw-up-stages.csv"),
            "DXVK_STALL_LOG": output("stalls.csv"),
            "DXVK_WAIT_LOG": output("waits.csv"),
            "DXVK_FLUSH_LOG": output("flushes.csv"),
            "DXVK_QUEUE_LOG": output("queue.csv"),
            "D3D9_LOCKIMAGE_PROBE": output("lock-images.csv"),
            "DXVK_LOG_LEVEL": "info",
            "DXVK_LOG_PATH": wineDirectory,
            // Prove that both Ashita's injector and the actual game process completed the
            // cooperative handshake. Throughput distinguishes a live x87 JIT from a sidecar
            // that started successfully but never received work.
            "X87_LOGS": "1",
            "X87_LOG_THROUGHPUT": "1",
        ]

        if level != "standard-nosample" {
            // Sample the guest x86 program counter without suspending the game thread. Wine
            // starts one sidecar for the injector and another for the client; the patched
            // sidecar expands `%p` to its target pid so those profiles cannot overwrite each
            // other. Discover across the full guest address space, choose the thread seen
            // running guest code most often, then keep that thread through DLL calls, Rosetta
            // runtime code, syscalls, and stalls. One kHz costs about 1% of one core and
            // ten-second windows let the recorder compare loading stalls with the same scene
            // after it settles. `standard-nosample` preserves every other probe for a clean
            // A/B check of the sampler itself.
            environment["X87_SAMPLE"] = directory
                .appendingPathComponent("x87-sample-%p.prof").path
            environment["X87_SAMPLE_HZ"] = "1000"
            environment["X87_SAMPLE_REPORT"] = "10"
            environment["X87_SAMPLE_WINDOWS"] = "1"
            environment["X87_GUEST_RANGE"] = "0x10000-0x800000000000"
            environment["X87_SAMPLE_STICKY"] = "1"
        }

        if level == "deep" {
            // These per-call probes perturb timing more than the standard set. They are useful
            // for a short diagnosis at 1080p, but the draw probe is known to be unstable with the
            // x87 sidecar at 4K. Do not enable the old SuspendThread instruction sampler here: it
            // can alter Wine scheduling and cannot follow the frame thread when that thread exits.
            environment["DXVK_DRAW_PROBE"] = output("draw.csv")
            environment["DXVK_UP_PROBE"] = output("draw-up.csv")
            environment["DXVK_FB_PROBE"] = output("framebuffers.log")
            environment["DXVK_PASS_PROBE"] = output("passes.log")
        }

        let metadata: [String: Any] = [
            "session": request.session,
            "level": level,
            "launcher_enabled_at": now,
            "probe_files": environment.keys.sorted(),
        ]
        if JSONSerialization.isValidJSONObject(metadata),
           let metadataData = try? JSONSerialization.data(
               withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            try? metadataData.write(
                to: directory.appendingPathComponent("launcher-capture.json"), options: .atomic)
        }

        return Capture(session: request.session, directory: directory, level: level,
                       environment: environment)
    }

    static func validSession(_ value: String) -> Bool {
        guard (1...64).contains(value.count),
              let first = value.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.resolvingSymlinksInPath().path ==
            URL(fileURLWithPath: rhs).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
