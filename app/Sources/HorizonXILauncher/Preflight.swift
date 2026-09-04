import Foundation

/// One verifiable precondition for the game launching. Every check here corresponds to a failure
/// that was actually hit and diagnosed — see docs/FINDINGS.md.
struct Check: Identifiable {
    enum State { case ok, bad, warn }
    let id: String
    let title: String
    let state: State
    let detail: String
}

enum Preflight {

    static func run(_ install: Install, profile: String = "horizonxi.ini") -> [Check] {
        let fm = FileManager.default
        var out: [Check] = []

        func add(_ id: String, _ title: String, _ ok: Bool, _ okText: String, _ badText: String,
                 warnOnly: Bool = false) {
            out.append(Check(id: id, title: title,
                             state: ok ? .ok : (warnOnly ? .warn : .bad),
                             detail: ok ? okText : badText))
        }

        add("volume", "Volume mounted", install.isMounted,
            install.volume?.path ?? "/",
            "\(install.volume?.path ?? "?") is not mounted — plug the drive in")

        guard install.isMounted else { return out }

        // A drive that is also the Time Machine destination is protected as a whole: macOS gives
        // "Operation not permitted" to any app without Full Disk Access, and never prompts. That
        // is exactly what happened when the game data moved to such a drive — every file check
        // below failed with EPERM while Finder and Terminal could read it fine. Say so up front,
        // because the individual failures below look like a broken install rather than a
        // permission.
        if let vol = install.volume, vol.path != "/" {
            var denied = false
            do { _ = try fm.contentsOfDirectory(atPath: install.sharedSupport.path) }
            catch let e as NSError { denied = e.code == NSFileReadNoPermissionError || ((e.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EPERM)) }
            if denied {
                add("fda", "Drive readable by this app", false, "",
                    "macOS is refusing to let this app read \(vol.path)"
                    + (Self.isTimeMachineDestination(vol) ? " — it is your Time Machine backup drive, which only apps with Full Disk Access may read." : ".")
                    + " Give FFXI on Mac Full Disk Access (System Settings › Privacy & Security › Full Disk Access), then press ↻ — or keep the game on a different drive.")
                return out
            }
        }

        add("wine", "Wrapper Wine tools", fm.isExecutableFile(atPath: install.wine.path),
            install.wine.path, "missing \(install.wine.path)")

        add("gamewine", "Patched game Wine", WineRuntime.installedExecutable != nil,
            WineRuntime.executable.path,
            "missing \(WineRuntime.executable.path) — open Setup & Diagnostics, then run Install wine. "
            + "The wrapper's Wine is not a compatible substitute and causes severe slowdowns or an exit after login.")

        add("client", "Game folder", fm.fileExists(atPath: install.gameDir.path),
            install.gameDir.path, "no client at \(install.gameDir.path)")

        let se = install.squareEnix
        add("squareenix", "FINAL FANTASY XI data", fm.fileExists(atPath: se.appendingPathComponent("FINAL FANTASY XI").path),
            se.path, "no SquareEnix/FINAL FANTASY XI under \(se.deletingLastPathComponent().path)")

        add("ashita", "Ashita-cli.exe", fm.fileExists(atPath: install.ashitaCLI.path),
            "present — launch must go through Ashita, not xiloader",
            "missing \(install.ashitaCLI.path)")

        // The wrong-client trap. A world pointed at a folder that holds several clients gets
        // whichever one the search reached first, and every downstream step then succeeds --
        // Ashita injects, the loader connects, the registry points somewhere valid -- against
        // another world's game data. It cost this project a full "Eden doesn't work" cycle in
        // August 2026. Blocking, not a warning: there is no safe guess to fall back to.
        if let why = install.clientAmbiguity {
            add("worldclient", "Client belongs to this world", false, "", why)
        } else if let w = install.worldName, install.dataRoot != nil || !install.ownsWrapperClient {
            add("worldclient", "Client belongs to this world", true, install.gameDir.path,
                "not \(w)'s own client")
        }

        // FINDINGS #1/#2: the wrapper's rpath points at SharedSupport/wine/lib, the dylibs ship in
        // Contents/Frameworks. Symlinking is what removes the DYLD_* dependency that SIP strips.
        let libDir = install.sharedSupport.appendingPathComponent("wine/lib")
        var libErr = ""
        let linked: Int
        do { linked = try fm.contentsOfDirectory(atPath: libDir.path).filter { $0.hasSuffix(".dylib") }.count }
        catch { linked = 0; libErr = " (\(error.localizedDescription))" }
        add("rpath", "dylib rpath fix", linked > 0,
            "\(linked) dylibs linked into wine/lib",
            "no dylibs in wine/lib\(libErr) — wineserver will fail to load (run Repair)")

        // FINDINGS #3: must exist in the 32-bit (Wow6432Node) view or the game reads nothing.
        var regErr = ""
        let reg: String
        do { reg = try String(contentsOf: install.systemReg, encoding: .utf8) }
        catch { reg = ""; regErr = " (\(error.localizedDescription))" }
        let hasWow = reg.contains(#"Wow6432Node\\PlayOnlineUS\\InstallFolder"#)
            || reg.contains(#"[Software\\Wow6432Node\\PlayOnlineUS\\InstallFolder]"#)
            || reg.range(of: "Wow6432Node\\\\+PlayOnlineUS", options: .regularExpression) != nil
        add("reg32", "PlayOnline registry (32-bit view)", hasWow,
            "Wow6432Node\\PlayOnlineUS present",
            "missing from the 32-bit view\(regErr) — the game will exit silently (run Repair)")

        // The layout itself: 0001 must be the FINAL FANTASY XI dir, not PlayOnlineViewer.
        let layoutOK = reg.range(of: #""0001"=".*FINAL FANTASY XI""#, options: .regularExpression) != nil
        add("reglayout", "InstallFolder layout", layoutOK,
            "0001 = FINAL FANTASY XI (correct)",
            "0001 does not point at the FINAL FANTASY XI dir — FFXiMain.dll will not load")

        // FINDINGS #4: three in-proc COM servers, all required.
        let comOK = reg.contains("FFXi.FFXiEntry") && reg.contains("FFXiMain.GameMain")
        add("com", "FFXI COM servers registered", comOK,
            "FFXi.FFXiEntry + FFXiMain.GameMain registered",
            "COM servers not registered (run Repair)")

        let polcore = install.squareEnix
            .appendingPathComponent("PlayOnlineViewer/viewer/com/polcore.dll")
        add("polcore", "polcore.dll", fm.fileExists(atPath: polcore.path),
            "present", "missing \(polcore.path)", warnOnly: true)

        // The single setting that silently kills the game: Sandbox's patch.ver interface-id
        // bypass. Off + sandbox loaded == "Successfully logged in", then exit two seconds later,
        // with no window and no error anywhere. See Sandbox.swift for the measured table.
        let sbOn = Sandbox.isEnabled(in: install, profile: profile)
        let sbBypass = Sandbox.interfaceBypass(install)
        if sbOn {
            add("sandbox", "Sandbox interface bypass", sbBypass != false,
                sbBypass == nil ? "not set — Ashita's default (on) applies" : "on",
                "off, while the Sandbox POL plugin is loaded — the game will log in and then "
                + "exit about two seconds later with no error. Run Repair, or set "
                + "use_interface_bypass = 1 in config/sandbox/sandbox.ini.")
        }

        add("d3dmetal", "D3DMetal renderer", fm.fileExists(atPath: install.d3dMetal.path),
            install.d3dMetal.path,
            "no D3DMetal in the wrapper — falls back to wine's slower GL path", warnOnly: true)

        return out
    }

    static var blocking: (([Check]) -> Bool) = { $0.contains { $0.state == .bad } }

    /// `tmutil destinationinfo` lists the mount points Time Machine backs up to.
    static func isTimeMachineDestination(_ vol: URL) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil"); p.arguments = ["destinationinfo"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("Mount Point   : \(vol.path)")
    }
}
