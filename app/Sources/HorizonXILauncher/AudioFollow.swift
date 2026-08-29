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
        guard let url = candidate, MachOSlice.hasX86(url) else { return nil }
        return url
    }
}
