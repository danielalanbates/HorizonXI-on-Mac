import Foundation

/// The Wine build used to run the game.
///
/// The Sikarugir Wine inside the wrapper still owns prefix setup and registry maintenance, but it
/// exits this client shortly after login. The game therefore runs with athei's CrossOver-derived
/// build, which also contains the cooperative x87sidecar handshake used by `ROSETTA_X87_PATH`.
enum WineRuntime {
    static let version = "wine-cx-26.3.0-1"
    static let downloadURL = URL(string:
        "https://github.com/athei/wine-build/releases/download/cx-26.3.0-1/"
        + "wine-cx-26.3.0-1-macos-x86_64.tar.xz")!
    static let downloadBytes = 203_696_924
    static let sha256 = "ec2a9e4d438917a26e381c01367773df79c3b0d6f0504b8183464619cad7e661"

    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func root(in applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("HorizonXI-on-Mac/runtimes", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    static func executable(in applicationSupport: URL) -> URL {
        root(in: applicationSupport).appendingPathComponent("wine/bin/wine")
    }

    static var executable: URL { executable(in: applicationSupport) }

    static func installedExecutable(in applicationSupport: URL) -> URL? {
        let url = executable(in: applicationSupport)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var installedExecutable: URL? { installedExecutable(in: applicationSupport) }

    /// Verify and unpack the pinned archive into a versioned directory on the user's internal
    /// drive. Extraction happens beside the destination and is moved into place only after the
    /// expected executable is present, so an interrupted setup cannot leave a partial runtime at
    /// the path the launcher trusts.
    static func install(archive: URL, expectedSHA256: String = sha256,
                        in applicationSupport: URL = applicationSupport,
                        log: @escaping @Sendable (String) -> Void) throws {
        log("verifying the patched game Wine")
        let actual = try digest(of: archive)
        guard actual == expectedSHA256 else {
            throw Err("The patched Wine download did not match its expected checksum, so it was "
                      + "not installed. Try setup again.")
        }

        let fm = FileManager.default
        let destination = root(in: applicationSupport)
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".install-\(version)-\(UUID().uuidString)",
                                                   isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        log("unpacking the patched game Wine")
        let unpack = run("/usr/bin/tar", ["-xJf", archive.path, "-C", staging.path])
        guard unpack.status == 0 else {
            throw Err("Could not unpack the patched game Wine: "
                      + unpack.output.suffix(400).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let stagedWine = staging.appendingPathComponent("wine/bin/wine")
        guard fm.isExecutableFile(atPath: stagedWine.path) else {
            throw Err("The patched Wine archive had an unexpected layout. Expected wine/bin/wine.")
        }

        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        guard fm.isExecutableFile(atPath: executable(in: applicationSupport).path) else {
            throw Err("The patched game Wine was unpacked but its executable is unavailable.")
        }
        log("installed patched game Wine at \(destination.path)")
    }

    static func digest(of file: URL) throws -> String {
        let result = run("/usr/bin/shasum", ["-a", "256", file.path])
        guard result.status == 0 else {
            throw Err("Could not verify the patched Wine download: "
                      + result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(result.output.prefix(64))
    }

    private static func run(_ executable: String,
                            _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() }
        catch { return (-1, error.localizedDescription) }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    struct Err: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
