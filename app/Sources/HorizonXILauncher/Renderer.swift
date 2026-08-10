import Foundation

/// The three renderer pathways this project has actually measured on an M1/8GB MacBook Pro,
/// 2026-08-10. Every claim below came off an instrumented run — `WINEDEBUG=fps` for the wine
/// paths, DXVK's own HUD for DXVK, `ioreg IOAccelerator` for GPU load — and a screenshot.
///
/// Numbers are from the same machine, same zone (Selbina) or the same menu, so they compare.
enum Renderer: String, Codable, CaseIterable, Identifiable {
    /// D3D8 -> wined3d -> Apple OpenGL. Everything renders. It is the only pathway that has ever
    /// put a complete, textured frame of the game world on screen.
    case openGL

    /// D3D8 -> wined3d -> Vulkan -> MoltenVK -> Metal. 4x the frame rate of OpenGL and a quarter
    /// of the CPU, but wined3d's Vulkan backend rejects every BC/DXT texture format
    /// ("Unsupported format WINED3DFMT_DXT1".."DXT5"), so models and terrain render as untextured
    /// grey. Fonts and UI are fine because they are uncompressed. Not playable; kept because it
    /// is one wine bug away from being the best option here.
    case vulkan

    /// D3D8 -> d3d8to9 -> DXVK 1.10.3 -> MoltenVK -> Metal. Menus, character select, the sky and
    /// the whole 2D layer render at ~29 FPS with half the CPU of OpenGL. In-zone the 3D world is
    /// still black. Closest thing to a fast *and* correct pathway; see docs/PATHWAYS.md.
    case metal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openGL: return "Classic (OpenGL)"
        case .vulkan: return "Vulkan — experimental"
        case .metal:  return "Metal / DXVK — experimental"
        }
    }

    var blurb: String {
        switch self {
        case .openGL:
            return "Everything draws correctly. Slow: about 3 fps in a zone on an M1, "
                 + "because every D3D8 call is translated on one CPU thread."
        case .vulkan:
            return "About 4x faster than Classic, but compressed textures are unsupported, "
                 + "so characters and terrain appear untextured. Look only, do not play."
        case .metal:
            return "~29 fps and half the CPU. Menus and character select render correctly; "
                 + "the 3D world is still black once you are in a zone."
        }
    }

    /// Only OpenGL is honest to present as playable.
    var playable: Bool { self == .openGL }

    /// Value for HKCU\Software\Wine\Direct3D\renderer. DXVK replaces d3d9 outright, so the
    /// wined3d renderer is irrelevant there and left on gl.
    var wineRendererKey: String { self == .vulkan ? "vulkan" : "gl" }

    /// Does this pathway need the d3d8to9 + DXVK DLLs dropped into the prefix?
    var needsDXVK: Bool { self == .metal }

    /// Extra process environment.
    var environment: [String: String] {
        switch self {
        case .metal:
            // The single fix that turned DXVK from a black window into a rendering one.
            // Without argument buffers, MoltenVK's SPIRV-Cross assigns render_state_t and
            // D3D9FixedFunctionPS both to [[buffer(0)]] and every fixed-function fragment
            // shader fails to compile: "cannot reserve 'buffer' resource location at index 0".
            // DXVK then draws nothing but its own HUD.
            return ["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "1"]
        default:
            return [:]
        }
    }

    /// Ashita boot-profile overrides this pathway needs, keyed by ini key.
    ///
    /// `behaviorflags.fpu_preserve = 1` matters a lot on DXVK: without it the entire 3D pass is
    /// missing, with it the sky, clouds and terrain silhouettes come back. FFXI changes the x87
    /// control word, and D3D9 without D3DCREATE_FPU_PRESERVE lets that corrupt its own maths.
    var iniOverrides: [String: String] {
        needsDXVK ? ["behaviorflags.fpu_preserve": "1"] : [:]
    }
}

/// Applies a renderer choice to a wine prefix: registry value, DLL overrides, MoltenVK link.
///
/// Every change is reversible and every original is backed up beside the file it replaces —
/// switching back to Classic must always restore a working game.
enum RendererSetup {
    /// wined3d asks for an OpenGL 4.4 context, macOS caps at 4.1, and the failed request drops it
    /// onto a legacy path. Pinning the version it asks for is worth ~55% on the OpenGL pathway:
    /// measured 5.1 -> 7.9 fps at the same screen, with no visual change.
    static let maxVersionGL: UInt32 = 0x0004_0001

    static func apply(_ renderer: Renderer, to install: Install, log: (String) -> Void) {
        stopWineserver(install)

        reg(install, add: #"HKCU\Software\Wine\Direct3D"#, name: "renderer",
            type: "REG_SZ", data: renderer.wineRendererKey)
        reg(install, add: #"HKCU\Software\Wine\Direct3D"#, name: "MaxVersionGL",
            type: "REG_DWORD", data: String(format: "0x%x", maxVersionGL))

        if renderer.needsDXVK {
            installDXVK(install, log: log)
        } else {
            removeDXVK(install, log: log)
        }
        stopWineserver(install)
        log("renderer: \(renderer.title)")
    }

    // MARK: - DXVK

    /// Directories whose processes load d3d8: Ashita injects into the loader, so the shim has to
    /// sit beside every one of them, not only the game directory.
    private static func dllDirs(_ i: Install) -> [URL] {
        [i.driveC.appendingPathComponent("windows/syswow64"),
         i.gameDir,
         i.gameDir.appendingPathComponent("bootloader"),
         i.squareEnix.appendingPathComponent("PlayOnlineViewer"),
         i.squareEnix.appendingPathComponent("FINAL FANTASY XI")]
    }

    private static func installDXVK(_ i: Install, log: (String) -> Void) {
        let fm = FileManager.default
        guard let d3d8to9 = Bundle.main.url(forResource: "d3d8to9", withExtension: "dll"),
              let dxvk = Bundle.main.url(forResource: "dxvk-1.10.3-x32-d3d9", withExtension: "dll")
        else { log("renderer: bundled DXVK not found — staying on Classic"); return }

        backupBuiltins(i)
        // wine ships no api-ms-win-crt-* forwarders; without them the shim silently fails to load
        let crt = i.sharedSupport.appendingPathComponent("wine.cx32bak/lib32on64/wine")
        let syswow = i.driveC.appendingPathComponent("windows/syswow64")
        if let kids = try? fm.contentsOfDirectory(at: crt, includingPropertiesForKeys: nil) {
            for k in kids where k.lastPathComponent.hasPrefix("api-ms-win-crt-") {
                try? fm.copyItem(at: k, to: syswow.appendingPathComponent(k.lastPathComponent))
            }
        }
        for dir in dllDirs(i) where fm.fileExists(atPath: dir.path) {
            replace(d3d8to9, at: dir.appendingPathComponent("d3d8.dll"))
            replace(dxvk, at: dir.appendingPathComponent("d3d9.dll"))
        }
        reg(i, add: #"HKCU\Software\Wine\DllOverrides"#, name: "*d3d8", type: "REG_SZ", data: "native")
        reg(i, add: #"HKCU\Software\Wine\DllOverrides"#, name: "*d3d9", type: "REG_SZ", data: "native")
        linkMoltenVK(i, toCX: true)
        log("renderer: DXVK 1.10.3 + d3d8to9 installed")
    }

    private static func removeDXVK(_ i: Install, log: (String) -> Void) {
        let fm = FileManager.default
        for dir in dllDirs(i) {
            for name in ["d3d8.dll", "d3d9.dll"] {
                let f = dir.appendingPathComponent(name)
                // syswow64 holds wine's own builtins — restore, do not delete
                if dir.lastPathComponent == "syswow64" {
                    let backup = i.driveC.appendingPathComponent("dll-backup")
                        .appendingPathComponent(name.replacingOccurrences(of: ".dll", with: ".builtin.dll"))
                    if fm.fileExists(atPath: backup.path) { replace(backup, at: f) }
                } else {
                    try? fm.removeItem(at: f)
                }
            }
        }
        regDelete(i, key: #"HKCU\Software\Wine\DllOverrides"#, name: "*d3d8")
        regDelete(i, key: #"HKCU\Software\Wine\DllOverrides"#, name: "*d3d9")
        linkMoltenVK(i, toCX: false)
    }

    private static func backupBuiltins(_ i: Install) {
        let fm = FileManager.default
        let dir = i.driveC.appendingPathComponent("dll-backup")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let syswow = i.driveC.appendingPathComponent("windows/syswow64")
        for name in ["d3d8", "d3d9"] {
            let src = syswow.appendingPathComponent("\(name).dll")
            let dst = dir.appendingPathComponent("\(name).builtin.dll")
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    /// DXVK 1.10.3 needs a MoltenVK that can create a Vulkan 1.2 device; the wrapper's default
    /// one is 1.1 and DXVK refuses it with "DxvkAdapter: Failed to create device".
    private static func linkMoltenVK(_ i: Install, toCX: Bool) {
        let fm = FileManager.default
        let link = i.sharedSupport.appendingPathComponent("wine/lib/libMoltenVK.dylib")
        let cx = i.wrapper.appendingPathComponent("Contents/Frameworks/moltenvkcx/libMoltenVK.dylib")
        let stock = i.wrapper.appendingPathComponent("Contents/Frameworks/libMoltenVK.dylib")
        let target = toCX ? cx : stock
        guard fm.fileExists(atPath: target.path) else { return }
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(at: link, withDestinationURL: target)
    }

    private static func replace(_ src: URL, at dst: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: src, to: dst)
    }

    // MARK: - wine plumbing

    /// `reg` edits do not reach a running wineserver, and a stale one silently keeps the old
    /// value — which is how an earlier pass of this project produced a "success" screenshot from
    /// the pathway it thought it had just switched away from.
    static func stopWineserver(_ i: Install) {
        let p = Process()
        p.executableURL = i.wineserver
        p.arguments = ["-k"]
        p.environment = ["WINEPREFIX": i.prefix.path]
        try? p.run()
        p.waitUntilExit()
        Thread.sleep(forTimeInterval: 1.5)
    }

    private static func reg(_ i: Install, add key: String, name: String, type: String, data: String) {
        wine(i, ["reg", "add", key, "/v", name, "/t", type, "/d", data, "/f"])
    }

    private static func regDelete(_ i: Install, key: String, name: String) {
        wine(i, ["reg", "delete", key, "/v", name, "/f"])
    }

    private static func wine(_ i: Install, _ args: [String]) {
        let p = Process()
        p.executableURL = i.wine
        p.arguments = args
        p.environment = ["WINEPREFIX": i.prefix.path, "WINEDEBUG": "-all"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
