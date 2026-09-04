import Foundation

// Servers.swift only needs the renderer's persisted identity. Keep this focused test independent
// from the renderer installer and its Wine-facing dependencies.
enum Renderer: String, Codable, Hashable {
    case openGL
}

// Build and run with:
//   swiftc app/Sources/HorizonXILauncher/Servers.swift \
//     scripts/tests/server-compatibility-test.swift -o /tmp/server-compatibility-test
//   /tmp/server-compatibility-test
@main
@MainActor
struct ServerCompatibilityTest {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        guard var horizon = Server.builtins.first(where: { $0.name == "HorizonXI" }),
              var gaia = Server.builtins.first(where: { $0.name == "Gaia XI" }) else {
            expect(false, "missing built-in test worlds")
            return
        }

        expect(horizon.x87 == true, "HorizonXI should default to x87 acceleration")

        // Reproduce a servers.json saved while HorizonXI's accelerator was disabled during the
        // cold-upload-buffer investigation and before Gaia XI's incompatibilities were known.
        horizon.x87 = false
        gaia.x87 = true
        gaia.msync = true
        let custom = Server(name: "Custom XI", host: "127.0.0.2", bootProfile: "custom.ini",
                            verified: false, note: "test", x87: false, msync: false)
        let merged = ServerStore.merge(saved: [horizon, gaia, custom])

        expect(merged.first(where: { $0.name == "HorizonXI" })?.x87 == true,
               "did not restore x87 acceleration for HorizonXI")
        expect(merged.first(where: { $0.name == "Gaia XI" })?.x87 == false,
               "did not restore Gaia XI's x87 compatibility rule")
        expect(merged.first(where: { $0.name == "Gaia XI" })?.msync == false,
               "did not restore Gaia XI's msync compatibility rule")
        expect(merged.first(where: { $0.name == "Custom XI" })?.x87 == false,
               "overwrote a custom world's x87 value")

        print("ok: built-in x87 and msync rules refresh without changing custom worlds")
    }
}
