import Foundation

/// audiofollow: makes a running FFXI follow the Mac's **Sound Output** setting.
///
/// Wine's CoreAudio backend (winecoreaudio.drv, under mmdevapi/dsound) creates an AUHAL output
/// unit and names a device on it once, at the moment the game first plays a sound. macOS's Sound
/// Output control changes the system *default device*; it does not move AudioUnits that have
/// already named one. The result is the bug Daniel hit: plug in headphones mid-session and every
/// other app moves over while FFXI keeps playing to the speakers, with no fix short of quitting.
///
/// `audio/audiofollow.c` is a small dylib inserted into the wine process. It interposes
/// `AudioComponentInstanceNew` to learn which output units exist, listens for
/// `kAudioHardwarePropertyDefaultOutputDevice`, and re-points those units when the setting
/// changes. See that file's header for the full reasoning and `docs/AUDIO.md` for the pathways
/// that were considered and rejected.
enum AudioFollow {
    /// The bundled dylib, or the repo's build of it under `swift run`. Returns nil unless the
    /// file exists *and* carries the architecture wine will be running as — a
    /// `DYLD_INSERT_LIBRARIES` naming a missing or wrong-arch file is a good way to turn a
    /// working launch into a failed one, and nothing about this feature justifies that risk.
    static func dylib() -> URL? {
        var candidate: URL?
        if let u = Bundle.main.url(forResource: "audiofollow", withExtension: "dylib") {
            candidate = u
        } else {
            let dev = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // HorizonXILauncher
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // app
                .appendingPathComponent("Resources/audiofollow.dylib")
            if FileManager.default.fileExists(atPath: dev.path) { candidate = dev }
        }
        guard let url = candidate, hasX86Slice(url) else { return nil }
        return url
    }

    /// Wine on Apple Silicon runs under Rosetta, so the slice that has to be present is x86_64.
    /// Read the Mach-O header directly rather than shelling out to `lipo`, which is not
    /// guaranteed to exist on a Mac without the developer tools.
    private static func hasX86Slice(_ url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 4096), head.count >= 8 else { return false }

        func be32(_ o: Int) -> UInt32 {
            UInt32(head[o]) << 24 | UInt32(head[o + 1]) << 16 | UInt32(head[o + 2]) << 8 | UInt32(head[o + 3])
        }
        func le32(_ o: Int) -> UInt32 {
            UInt32(head[o + 3]) << 24 | UInt32(head[o + 2]) << 16 | UInt32(head[o + 1]) << 8 | UInt32(head[o])
        }

        let cpuTypeX86_64: UInt32 = 0x0100_0007
        let magic = be32(0)

        // Fat binary (the normal case — build-audiofollow.sh lipos arm64 + x86_64 together).
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let count = Int(be32(4))
            let entry = magic == 0xCAFE_BABE ? 20 : 32
            for i in 0..<count {
                let off = 8 + i * entry
                guard off + 4 <= head.count else { break }
                if be32(off) == cpuTypeX86_64 { return true }
            }
            return false
        }
        // Thin Mach-O: cputype is the second word, little-endian on everything we ship to.
        if magic == 0xCFFA_EDFE || magic == 0xCEFA_EDFE { return le32(4) == cpuTypeX86_64 }
        return false
    }
}
