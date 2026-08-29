import Foundation

/// winecursor: keeps the mouse cursor visible while FFXI runs under Wine.
///
/// FFXI hides the Windows cursor (`ShowCursor(FALSE)`) and draws its own sprite, which DXVK does
/// not render, so the pointer vanishes inside the game window on every server. Wine's Mac driver
/// (winemac.drv) performs the hide with AppKit's `+[NSCursor hide]` -- confirmed from the driver's
/// symbols. `cursor/winecursor.m` is a small dylib, inserted into the Wine process exactly like
/// `audiofollow.dylib`, that neutralises `+[NSCursor hide]`/`+[NSCursor unhide]` so the system
/// arrow stays put. See `docs/CURSOR.md`.
///
/// Why a dylib and not the `winecursor` Ashita addon: this is a platform compatibility shim,
/// touching no game/Wine/Square Enix data, so it is NOT governed by a server's addon allowlist
/// and works on HorizonXI without loading an unlisted addon.
enum WineCursor {
    /// The bundled dylib, or the repo's build under `swift run`. Returns nil unless the file
    /// exists AND carries the x86_64 slice Wine runs as under Rosetta -- a `DYLD_INSERT_LIBRARIES`
    /// naming a missing or wrong-arch file can abort the launch, and the cursor fix is not worth
    /// that risk.
    static func dylib() -> URL? {
        var candidate: URL?
        if let u = Bundle.main.url(forResource: "winecursor", withExtension: "dylib") {
            candidate = u
        } else {
            let dev = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // HorizonXILauncher
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // app
                .appendingPathComponent("Resources/winecursor.dylib")
            if FileManager.default.fileExists(atPath: dev.path) { candidate = dev }
        }
        guard let url = candidate, MachOSlice.hasX86(url) else { return nil }
        return url
    }
}
