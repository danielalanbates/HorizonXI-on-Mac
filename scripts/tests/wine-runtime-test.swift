import Foundation

// Build and run with:
//   swiftc app/Sources/HorizonXILauncher/WineRuntime.swift \
//     scripts/tests/wine-runtime-test.swift -o /tmp/wine-runtime-test
//   /tmp/wine-runtime-test
@main
struct WineRuntimeTest {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func fixtureArchive(in root: URL) throws -> URL {
        let payload = root.appendingPathComponent("payload/wine/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let wine = payload.appendingPathComponent("wine")
        try Data("fixture wine".utf8).write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)

        let archive = root.appendingPathComponent("wine.tar.xz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-cJf", archive.path, "-C",
                             root.appendingPathComponent("payload").path, "wine"]
        try process.run()
        process.waitUntilExit()
        expect(process.terminationStatus == 0, "could not make fixture archive")
        return archive
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("hxi-wine-runtime-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let fakeSupport = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        expect(WineRuntime.executable(in: fakeSupport).path ==
               "/Users/test/Library/Application Support/HorizonXI-on-Mac/runtimes/"
               + "wine-cx-26.3.0-1/wine/bin/wine", "runtime path is not portable")

        let archive = try fixtureArchive(in: root)
        let support = root.appendingPathComponent("Application Support")
        let digest = try WineRuntime.digest(of: archive)
        try WineRuntime.install(archive: archive, expectedSHA256: digest, in: support,
                                log: { _ in })

        guard let executable = WineRuntime.installedExecutable(in: support) else {
            expect(false, "installed runtime was not detected")
            return
        }
        let installedData = try Data(contentsOf: executable)
        expect(installedData == Data("fixture wine".utf8), "installed the wrong executable")

        let rejectedSupport = root.appendingPathComponent("Rejected Application Support")
        do {
            try WineRuntime.install(archive: archive,
                                    expectedSHA256: String(repeating: "0", count: 64),
                                    in: rejectedSupport, log: { _ in })
            expect(false, "accepted an archive with the wrong checksum")
        } catch {
            expect(WineRuntime.installedExecutable(in: rejectedSupport) == nil,
                   "created a runtime after checksum rejection")
        }

        print("ok: portable path, checksum rejection, and atomic runtime installation")
    }
}
