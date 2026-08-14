import Foundation

/// FFXI's graphics settings.
///
/// Retail FFXI exposes these through `FINAL FANTASY XI Config.exe`, which HorizonXI's install
/// does not ship — the launcher's old "Graphics…" button tried to run it and silently did
/// nothing. Ashita applies the same values itself: every key under `[ffxi.registry]` in the boot
/// profile is written into the registry before the client starts, so writing that section is
/// equivalent to using the retail config tool, and it is per-profile rather than global.
///
/// Only keys whose meaning is established are exposed. FFXI's registry is a flat list of
/// numbered values and several are still guesswork; a settings panel that writes a guess into
/// somebody's config is worse than one that leaves it alone.
struct GraphicsSettings: Codable, Equatable {
    /// Renderer resolution — what the world is actually drawn at (`0001`/`0002`).
    var width: Int = 1280
    var height: Int = 720
    /// Menu/UI resolution (`0037`/`0038`). Kept equal to the renderer resolution: FFXI scales
    /// the interface from these independently, and mismatching them is how the UI ends up
    /// enormous or postage-stamp sized at 4K.
    var uiFollowsResolution: Bool = true
    /// Background (environment) texture resolution, `0003`, and its texture-set twin `0004`.
    /// 512 / 1024 / 2048 / 4096; the stock HorizonXI profile ships 2048, "max" is 4096.
    var textureResolution: Int = 2048
    /// Mip mapping, `0018`. 0–4, higher is more aggressive filtering of distant textures.
    var mipMapping: Int = 2
    /// Texture compression, `0011`. 0 = uncompressed (best), 2 = compressed.
    var textureCompression: Int = 2
    /// Bump mapping, `0019`.
    var bumpMapping: Bool = true
    /// Environmental animation (water, weather effects), `0021`.
    var environmentAnimation: Bool = true
    /// Sound channels, `0029`. Not graphics, but it lives in the same section and the max-
    /// settings profile raises it, so leaving it out would mean "max" silently was not max.
    var soundChannels: Int = 12

    static let key = "graphics.settings"

    static let resolutions: [(String, Int, Int)] = [
        ("1280 × 720", 1280, 720),
        ("1920 × 1080", 1920, 1080),
        ("2560 × 1440", 2560, 1440),
        ("3840 × 2160 (4K)", 3840, 2160),
    ]

    /// The configuration every performance measurement in this project was taken against
    /// (`scripts/max4k.json`, `docs/X87-WALL.md`).
    static var max4K: GraphicsSettings {
        GraphicsSettings(width: 3840, height: 2160, uiFollowsResolution: true,
                         textureResolution: 4096, mipMapping: 2, textureCompression: 2,
                         bumpMapping: true, environmentAnimation: true, soundChannels: 20)
    }

    static var balanced: GraphicsSettings {
        GraphicsSettings(width: 1920, height: 1080, uiFollowsResolution: true,
                         textureResolution: 2048, mipMapping: 2, textureCompression: 2,
                         bumpMapping: true, environmentAnimation: true, soundChannels: 12)
    }

    /// The `[ffxi.registry]` keys this represents, in the form `applyIniOverrides` wants.
    var iniOverrides: [String: String] {
        var out: [String: String] = [
            "0001": String(width),
            "0002": String(height),
            "0003": String(textureResolution),
            "0004": String(textureResolution),
            "0011": String(textureCompression),
            "0018": String(mipMapping),
            "0019": bumpMapping ? "1" : "0",
            "0021": environmentAnimation ? "1" : "0",
            "0029": String(soundChannels),
        ]
        if uiFollowsResolution {
            out["0037"] = String(width)
            out["0038"] = String(height)
        }
        return out
    }

    static func load() -> GraphicsSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(GraphicsSettings.self, from: d) else { return .init() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    /// Read what is actually in the profile, so the panel opens showing the real state rather
    /// than whatever this app last wrote.
    static func read(from install: Install, profile: String) -> GraphicsSettings? {
        let url = install.gameDir.appendingPathComponent("config/boot/\(profile)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var vals: [String: Int] = [:]
        var inSection = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inSection = line.hasPrefix("[ffxi.registry]"); continue }
            guard inSection, !line.hasPrefix(";"), let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if let n = Int(v) { vals[k] = n }
        }
        guard !vals.isEmpty else { return nil }
        var g = GraphicsSettings()
        g.width = vals["0001"] ?? g.width
        g.height = vals["0002"] ?? g.height
        g.textureResolution = vals["0003"] ?? g.textureResolution
        g.mipMapping = vals["0018"] ?? g.mipMapping
        g.textureCompression = vals["0011"] ?? g.textureCompression
        g.bumpMapping = (vals["0019"] ?? 1) != 0
        g.environmentAnimation = (vals["0021"] ?? 1) != 0
        g.soundChannels = vals["0029"] ?? g.soundChannels
        g.uiFollowsResolution = (vals["0037"] ?? g.width) == g.width
        return g
    }

    func write(to install: Install, profile: String) {
        Credentials.applyIniOverrides(iniOverrides, to: install, profile: profile)
    }
}
