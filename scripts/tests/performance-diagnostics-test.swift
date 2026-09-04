import Foundation

@main
struct PerformanceDiagnosticsTest {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func writeRequest(
        support: URL, game: URL, session: String,
        level: String = "standard", expiresAt: TimeInterval = 2_000
    ) throws {
        let file = PerformanceDiagnostics.requestURL(in: support)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let request = PerformanceDiagnostics.Request(
            session: session, expiresAt: expiresAt,
            gameDirectory: game.path, level: level)
        try JSONEncoder().encode(request).write(to: file, options: .atomic)
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("hxi-performance-diagnostics-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let game = root.appendingPathComponent("HorizonXI", isDirectory: true)
        let other = root.appendingPathComponent("OtherXI", isDirectory: true)
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)

        expect(PerformanceDiagnostics.validSession("20260903-010203-deep"),
               "rejected a generated session name")
        expect(!PerformanceDiagnostics.validSession("../escape"),
               "accepted path traversal as a session")
        expect(!PerformanceDiagnostics.validSession("bad/session"),
               "accepted a path separator as a session")

        try writeRequest(support: support, game: game, session: "wrong-world")
        expect(PerformanceDiagnostics.consume(
            for: other, gameDirectoryWine: "C:\\OtherXI",
            applicationSupport: support, now: 1_000) == nil,
            "consumed a request for another game directory")
        expect(fm.fileExists(atPath: PerformanceDiagnostics.requestURL(in: support).path),
               "deleted a request for another game directory")

        try writeRequest(support: support, game: game, session: "expired", expiresAt: 900)
        expect(PerformanceDiagnostics.consume(
            for: game, gameDirectoryWine: "C:\\HorizonXI",
            applicationSupport: support, now: 1_000) == nil,
            "consumed an expired request")
        expect(!fm.fileExists(atPath: PerformanceDiagnostics.requestURL(in: support).path),
               "left an expired request armed")

        try writeRequest(support: support, game: game, session: "standard")
        guard let standard = PerformanceDiagnostics.consume(
            for: game, gameDirectoryWine: "C:\\HorizonXI",
            applicationSupport: support, now: 1_000) else {
            expect(false, "did not consume a valid request")
            return
        }
        expect(standard.environment["DXVK_FPS_LOG"]?.hasSuffix("\\fps.csv") == true,
               "did not configure the frame log")
        expect(standard.environment["DXVK_WAIT_LOG"]?.hasSuffix("\\waits.csv") == true,
               "did not configure the wait probe")
        expect(standard.environment["DXVK_PRESENT_STAGE_LOG"]?.hasSuffix(
            "\\present-stages.csv") == true,
            "did not configure the non-invasive Present watchdog")
        expect(standard.environment["DXVK_SUBMIT_STAGE_LOG"]?.hasSuffix(
            "\\submit-stages.csv") == true,
            "did not configure the non-invasive submit watchdog")
        expect(standard.environment["DXVK_UP_STAGE_LOG"]?.hasSuffix(
            "\\draw-up-stages.csv") == true,
            "did not configure the in-flight DrawPrimitiveUP watchdog")
        expect(standard.environment["X87_LOGS"] == "1",
               "did not enable cooperative x87 handshake logging")
        expect(standard.environment["X87_LOG_THROUGHPUT"] == "1",
               "did not enable x87 throughput logging")
        expect(standard.environment["X87_SAMPLE"]?.hasSuffix(
            "/x87-sample-%p.prof") == true,
               "did not give each x87 sampler a target-pid profile path")
        expect(standard.environment["X87_SAMPLE_HZ"] == "1000",
               "did not select the low-overhead guest sample rate")
        expect(standard.environment["X87_SAMPLE_REPORT"] == "10",
               "did not select ten-second sample windows")
        expect(standard.environment["X87_GUEST_RANGE"] == "0x10000-0x800000000000",
               "did not discover across the full guest address space")
        expect(standard.environment["X87_SAMPLE_STICKY"] == "1",
               "did not keep sampling the discovered game thread")
        expect(standard.environment["DXVK_DRAW_PROBE"] == nil,
               "enabled the expensive draw probe in a standard capture")
        expect(fm.fileExists(atPath: standard.directory
            .appendingPathComponent("launcher-capture.json").path),
            "did not leave launcher metadata in the capture")
        expect(PerformanceDiagnostics.consume(
            for: game, gameDirectoryWine: "C:\\HorizonXI",
            applicationSupport: support, now: 1_000) == nil,
            "the one-shot request was consumed twice")

        try writeRequest(support: support, game: game, session: "nosample",
                         level: "standard-nosample")
        guard let noSample = PerformanceDiagnostics.consume(
            for: game, gameDirectoryWine: "C:\\HorizonXI",
            applicationSupport: support, now: 1_000) else {
            expect(false, "did not consume a standard-nosample request")
            return
        }
        expect(noSample.level == "standard-nosample",
               "did not preserve the standard-nosample level")
        expect(noSample.environment["DXVK_FPS_LOG"] != nil,
               "disabled standard renderer probes with the guest sampler")
        expect(noSample.environment["X87_LOG_THROUGHPUT"] == "1",
               "disabled x87 throughput logging with the guest sampler")
        expect(noSample.environment["X87_SAMPLE"] == nil,
               "enabled the guest-PC sampler in standard-nosample mode")

        try writeRequest(support: support, game: game, session: "deep", level: "deep")
        guard let deep = PerformanceDiagnostics.consume(
            for: game, gameDirectoryWine: "C:\\HorizonXI",
            applicationSupport: support, now: 1_000) else {
            expect(false, "did not consume a deep request")
            return
        }
        expect(deep.environment["DXVK_DRAW_PROBE"]?.hasSuffix("\\draw.csv") == true,
               "did not configure the deep draw probe")
        expect(deep.environment["DXVK_UP_PROBE"]?.hasSuffix("\\draw-up.csv") == true,
               "did not configure the DrawPrimitiveUP stage probe")
        expect(deep.environment["DXVK_SAMPLE_LOG"] == nil,
               "enabled the intrusive thread-suspension profiler")

        print("ok: capture validation, expiry, install matching, probe levels, and one-shot use")
    }
}
