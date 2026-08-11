import Foundation

/// Host-side performance knobs. Only things whose effect is real and explainable — no cargo cult.
struct PerfSettings: Codable {
    /// msync is the macOS-native fast synchronisation path in CX/Sikarugir wine. Falls back
    /// harmlessly if the build does not support it.
    var msync = true
    /// esync as a second-choice sync primitive; ignored when msync is active.
    var esync = false
    /// WINEDEBUG=-all. Wine's debug channels are extremely expensive even when nothing consumes
    /// them; leaving them on costs frames.
    var silenceWineDebug = true
    /// Metal HUD overlay — used to actually measure the frame rate rather than guess at it.
    var metalHUD = false
    /// Keep the game off macOS App Nap / timer coalescing when it loses focus.
    var disableAppNap = true
    /// Large address aware heap hint for the 32-bit client.
    var largeAddressAware = true
    /// Extra environment, one KEY=VALUE per line, for experiments.
    var extraEnv = ""
    /// Which renderer pathway to run. Metal/DXVK reaches FFXI's 30 fps cap with the world
    /// drawing correctly, so it is the default; Vulkan and Classic are fallbacks.
    var renderer: Renderer = .metal

    static let key = "perf.settings"

    static func load() -> PerfSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(PerfSettings.self, from: d) else { return .init() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    /// Environment applied to the wine process.
    func environment(for install: Install) -> [String: String] {
        var env: [String: String] = [:]
        env["WINEPREFIX"] = install.prefix.path
        env["D3DMETAL_FRAMEWORK_PATH"] = install.d3dMetal.path
        // Wine loads libMoltenVK and the rest of the wrapper's dylibs through this. The
        // wrapper's own launch script sets it; without it the Vulkan renderers come up to a
        // black window and sit there, which is a very confusing way to fail.
        env["DYLD_FALLBACK_LIBRARY_PATH"] = install.frameworks.path + ":/usr/lib"
        if silenceWineDebug { env["WINEDEBUG"] = "-all" }
        env["WINEMSYNC"] = msync ? "1" : "0"
        env["WINEESYNC"] = (esync && !msync) ? "1" : "0"
        if metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if disableAppNap { env["LSAppNapIsDisabled"] = "1" }
        if largeAddressAware { env["WINE_LARGE_ADDRESS_AWARE"] = "1" }
        for (k, v) in renderer.environment { env[k] = v }
        for line in extraEnv.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                env[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return env
    }
}
