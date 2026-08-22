import Foundation

/// What the Dock shows while a world is running.
///
/// The game is a wine process, and the Dock takes a process's tile from the bundle its executable
/// lives inside. With x87 acceleration off (the default since 2026-08-21) that is the Sikarugir
/// wrapper's own wine at `siku.app/Contents/SharedSupport/wine/bin/wine`, so the tile said
/// "Sikarugir" under a generic wrapper icon no matter which world was running.
///
/// So before each launch, stamp the wrapper: this project's gold crystal in place of the
/// wrapper's icon, and the world's name as the bundle name. The original icon is kept beside it
/// the first time, so this is reversible with `restore`.
///
/// Two things this deliberately does not do:
/// * It does not touch the code signature. The wrapper is ad-hoc signed with `Info.plist=not
///   bound`, so renaming it is safe; replacing a *Mach-O* would not be.
/// * It does not work for a launch through the x87 cooperative wine, which lives outside any
///   bundle (`/Volumes/Games/FFXI/wine-coop/...`) and therefore has no tile to stamp. Running a
///   bare executable is exactly why that pathway shows up as plain "wine".
enum DockIcon {
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
