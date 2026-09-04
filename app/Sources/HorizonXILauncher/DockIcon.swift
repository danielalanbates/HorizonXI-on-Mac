import Foundation

/// What the Dock shows while a world is running.
///
/// The game is a wine process, and the Dock takes a process's tile from the bundle its executable
/// lives inside. The patched Wine runtime used for the game lives under Application Support,
/// outside an app bundle, so without an override the tile appears as plain "wine".
///
/// So before each launch, stamp the wrapper: this project's gold crystal in place of the
/// wrapper's icon, and the world's name as the bundle name. The original icon is kept beside it
/// the first time, so this is reversible with `restore`.
///
/// Two things this deliberately does not do:
/// * It does not touch the code signature. The wrapper is ad-hoc signed with `Info.plist=not
///   bound`, so renaming it is safe; replacing a *Mach-O* would not be.
/// * Stamping the wrapper alone does not affect the patched runtime, which lives outside any app
///   bundle. `cxRoot` supplies the icon to that Wine process separately.
enum DockIcon {
    /// The route that actually works (2026-08-26): CrossOver's winemac.drv reads the Dock tile
    /// from the exe's first RT_GROUP_ICON resource, and `horizon-loader.exe` has none -- so it
    /// falls through to CrossOver Hack 13440, which loads
    /// `$CX_ROOT/../../Resources/exeIcon.icns` (dlls/winemac.drv/window.c, set_app_icon). No
    /// wine rebuild, no touching the server's binary: build a bundle-shaped folder holding our
    /// icon and point CX_ROOT at it. Verified on an icon-less test exe under wine-coop; the
    /// gold crystal came up in the Dock with the running dot under it (docs/DOCK-ICON.md).
    ///
    /// CX_ROOT is otherwise only read by localspl (ps2pdf for printing) and the round-rect icon
    /// mask (a PNG we deliberately do not ship, so the icon is used as drawn).
    static func cxRoot(for world: String, log: (String) -> Void = { _ in }) -> URL? {
        let fm = FileManager.default
        guard let src = source else { return nil }
        let safe = world.isEmpty ? "world" : world.replacingOccurrences(of: "/", with: "-")
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorizonXI-on-Mac/dock/\(safe)", isDirectory: true)
        let resources = base.appendingPathComponent("Contents/Resources", isDirectory: true)
        let cxRoot = base.appendingPathComponent("Contents/SharedSupport/wine", isDirectory: true)
        let icon = resources.appendingPathComponent("exeIcon.icns")
        do {
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try fm.createDirectory(at: cxRoot, withIntermediateDirectories: true)
            let ours = try Data(contentsOf: src)
            if (try? Data(contentsOf: icon)) != ours {
                try? fm.removeItem(at: icon)
                try ours.write(to: icon)
            }
            return cxRoot
        } catch {
            log("i  Dock icon: \(error.localizedDescription)")
            return nil
        }
    }

    /// Our icon, shipped in the launcher bundle; falls back to the repo copy under `swift run`.
    private static var source: URL? {
        if let u = Bundle.main.url(forResource: "GameIcon", withExtension: "icns") { return u }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GameIcon.icns")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// The wrapper .app that owns this install's wine: siku.app, two levels above SharedSupport.
    private static func wrapper(for install: Install) -> URL? {
        let app = install.wine                      // …/siku.app/Contents/SharedSupport/wine/bin/wine
            .deletingLastPathComponent()            // bin
            .deletingLastPathComponent()            // wine
            .deletingLastPathComponent()            // SharedSupport
            .deletingLastPathComponent()            // Contents
            .deletingLastPathComponent()            // siku.app
        return app.pathExtension == "app" ? app : nil
    }

    /// Make the running world's Dock tile say `world`, under this project's icon. Idempotent and
    /// silent on failure: a Dock tile is never worth failing a launch over.
    @discardableResult
    static func apply(to install: Install, world: String, log: (String) -> Void = { _ in }) -> Bool {
        let fm = FileManager.default
        guard let app = wrapper(for: install), let src = source else { return false }
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard var info = NSMutableDictionary(contentsOf: plist) as? [String: Any] else { return false }

        // Whatever the wrapper names its icon, that is the file the Dock reads.
        let iconName = (info["CFBundleIconFile"] as? String ?? "AppIcon")
            .replacingOccurrences(of: ".icns", with: "")
        let icon = app.appendingPathComponent("Contents/Resources/\(iconName).icns")
        let backup = app.appendingPathComponent("Contents/Resources/\(iconName).original.icns")

        do {
            if fm.fileExists(atPath: icon.path), !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: icon, to: backup)
            }
            // Only rewrite when something actually differs -- this runs on every Play.
            let ours = try Data(contentsOf: src)
            if (try? Data(contentsOf: icon)) != ours {
                try? fm.removeItem(at: icon)
                try ours.write(to: icon)
            }
            let title = "FFXI — \(world)"
            if info["CFBundleName"] as? String != title {
                info["CFBundleName"] = title
                info["CFBundleDisplayName"] = title
                try (info as NSDictionary).write(to: plist)
            }
            // Nudge LaunchServices: it caches a bundle's icon and name by mtime.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
            return true
        } catch {
            log("i  Dock icon: \(error.localizedDescription)")
            return false
        }
    }

    /// Put the wrapper back the way it shipped. Not wired to a button yet; here so the change is
    /// reversible by hand and by whatever settings UI wants it later.
    static func restore(_ install: Install) {
        let fm = FileManager.default
        guard let app = wrapper(for: install),
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                as? [String: Any] else { return }
        let iconName = (info["CFBundleIconFile"] as? String ?? "AppIcon")
            .replacingOccurrences(of: ".icns", with: "")
        let icon = app.appendingPathComponent("Contents/Resources/\(iconName).icns")
        let backup = app.appendingPathComponent("Contents/Resources/\(iconName).original.icns")
        guard fm.fileExists(atPath: backup.path) else { return }
        try? fm.removeItem(at: icon)
        try? fm.copyItem(at: backup, to: icon)
    }
}
