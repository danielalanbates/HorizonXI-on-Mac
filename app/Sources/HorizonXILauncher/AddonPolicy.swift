import Foundation

/// What a private server permits its players to run.
///
/// This is a rules question, not a technical one, and getting it wrong has a real cost: on
/// HorizonXI, loading an addon that is not on their approved list is a bannable offence. So the
/// launcher only ever restricts the addon screen when it has an actual published list to restrict
/// it *by*, and it always says where that list came from. A server whose policy this project has
/// not sourced is marked `.unknown` and nothing is hidden — presenting a guessed allowlist as if
/// it were the server's own rules would be worse than showing everything and saying so.
enum AddonPolicy: Hashable {
    /// No published policy this project has been able to source. Nothing is filtered; the UI says
    /// so and points the player at the server's own channels.
    case unknown
    /// The server publishes a list of approved addons and forbids everything else.
    case allowlist(Set<String>, source: String)
    /// The server allows anything. Only used where a server says so explicitly — notably the
    /// local LandSandBoat world, where the only player is the person running it.
    case unrestricted(reason: String)

    /// Case-insensitive, and tolerant of the punctuation and suffixes that differ between a
    /// published list and a folder on disk: published names carry spaces, apostrophes, slashes
    /// and parenthesised author tags ("Chains (Sippius)", "InvTracker / InventoryTracker",
    /// "HXUI / ConsolidatedUI"), while the addon directory is a bare lowercase token.
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        if let paren = s.firstIndex(of: "(") { s = String(s[s.startIndex..<paren]) }
        s = s.replacingOccurrences(of: ".lua", with: "")
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// A published entry can name several equivalent addons ("Recast (Ashita)" and
    /// "Recast (XITools)" are both `recast`; "InvTracker / InventoryTracker" is either name).
    private static func variants(_ published: String) -> [String] {
        published.components(separatedBy: "/").map(normalize).filter { !$0.isEmpty }
    }

    /// Ashita's own machinery, which no server's published list mentions because it is not an
    /// addon anybody chooses — it is what makes addons work at all. `Addons` is the Lua host:
    /// filtering it out and switching it off, which an allowlist would otherwise do, silently
    /// disables every Lua addon in the game. These are never hidden and never force-disabled.
    static let infrastructure: Set<String> = [
        "addons", "thirdparty", "screenshot", "winefix", "libs",
    ]

    func allows(_ installedName: String) -> Bool {
        let key = AddonPolicy.normalize(installedName)
        if AddonPolicy.infrastructure.contains(key) { return true }
        switch self {
        case .unknown, .unrestricted:
            return true
        case let .allowlist(names, _):
            return names.contains(key)
        }
    }

    var isRestricting: Bool {
        if case .allowlist = self { return true }
        return false
    }

    var source: String? {
        switch self {
        case let .allowlist(_, source): return source
        case let .unrestricted(reason): return reason
        case .unknown: return nil
        }
    }

    static func allowlist(published: [String], source: String) -> AddonPolicy {
        var set = Set<String>()
        for entry in published { set.formUnion(variants(entry)) }
        return .allowlist(set, source: source)
    }
}

/// The policies this project has actually sourced. Everything absent from here is `.unknown`,
/// deliberately — see the note on `AddonPolicy`.
enum AddonPolicies {
    /// HorizonXI's approved list, transcribed from <https://horizonxi.info/addons> on
    /// 2026-08-14 — the list HorizonXI's own wiki directs players to. Their rule is an
    /// allowlist: anything not on it risks a ban, so the launcher hides the rest rather than
    /// merely warning.
    ///
    /// Names are kept verbatim as published, including the parenthesised author tags and the
    /// "A / B" alternates, so that a future re-check is a straight diff against the page.
    static let horizonPlugins = [
        "Toon", "Sequencer", "FPS", "Minimap", "Nameplate",
    ]

    static let horizonAddons = [
        "Allmaps", "Antiemote", "ASCII-Joy", "Ashitacast", "AshitaFishAid", "Aspect", "Att",
        "Attendance", "AutoFPS", "Balloon", "Barfiller", "Battlemod", "BigMode", "Cfhblock",
        "calc", "Chains (Sippius)", "Chains (HorizonXI / NerfOnline)", "Chaintimer", "Changecall",
        "Chatmon", "Checker", "Claimbar", "Clammy", "CleanCS", "Clearpartybars", "Clock",
        "ClockVana", "Config", "Cosplay", "Craftmon", "Crossbar", "Crosshair", "CTimers",
        "CurrentTime", "Customhud", "Debuffed", "Deeps", "DigDig", "DiscordRPC", "Distance",
        "DKPBids", "Don't Drop The Soap", "DrawDistance", "Duration", "Emotes", "EnemyBuffs",
        "ENMs", "Enternity", "EquipViewer", "Equipmon", "EventTracker", "Expmon", "Fadeout",
        "FastCS", "FastSwap", "Fillmode", "Filterless", "Filters", "Find", "Findall", "FishAid",
        "FishingInfo", "GBinder", "GearFinder", "GearLock", "Giltracker", "GlamourUI",
        "HardwareMouse", "HGather", "Hideconsole", "HideParty", "HitPoints", "HTicks", "Hush",
        "hxiclam", "HXIFish", "HXUI / ConsolidatedUI", "Ibar", "IME", "ImGuistyle", "InstantAH",
        "InstantChat", "InvTracker / InventoryTracker", "InventoryCounter", "Itemwatch",
        "LegacyAC", "Links", "Logger", "Logincmd", "Logs", "Lootz", "lschat", "LuAshitacast",
        "Macrofix", "MacroMaster", "Mapdot", "Me", "Meteorologist", "Metrics", "Minimap-Helper",
        "Minimapmon", "Mipmap", "MobDB", "Mountmuzzle", "Move", "NoName", "NoLock", "NoMount",
        "Nocombat", "Packetflow", "Packrat", "Parse", "Partybuffs", "Pbar", "PetInfo (Ashita)",
        "PetInfo (ayechonk)", "PetMe", "PlayerInfo", "Points", "PriceCheck", "Quicksets",
        "Rcheck", "Recast (Ashita)", "Recast (XITools)", "Rest", "RSVP", "Scoreboard",
        "Sexchange", "Shorthand", "Simplelog", "Singlerace", "Skillchain", "Skillchains",
        "Status", "Statustimers", "Stfu", "Stylist", "TargetInfo", "TargetLines", "tCrossBar",
        "Tgt", "tHotBar", "Ticker", "Timers", "Timestamp", "Tparty", "Tracker", "Translataru",
        "TreasurePool (ayechonk)", "TreasurePool (ShiyoKozuki)", "tTimers", "Us", "WatchEXP",
        "WhoGot", "XICamera", "XIChats", "XIPivot", "XITools", "XIVBar", "XIVHotbar", "XivParty",
        "XIVUI", "Yield", "ZoneName", "ZoneTimer", "Zoom",
    ]

    static let horizon = AddonPolicy.allowlist(
        published: horizonPlugins + horizonAddons,
        source: "HorizonXI's approved list, horizonxi.info/addons (checked 2026-08-14)")

    /// A world running on this Mac with one player in it. There is nobody to be fair to and
    /// nobody to enforce anything, so nothing is filtered.
    static let localWorld = AddonPolicy.unrestricted(
        reason: "Your own LandSandBoat world — no server rules to break.")

    /// The page a server publishes its approved list on, where one exists and is machine-readable.
    /// Checked 2026-08-14; only HorizonXI has one. `horizonxi.com/players/Addons` returns 403 to
    /// anything that is not a browser, which is why the `.info` mirror -- the page HorizonXI's own
    /// wiki links players to -- is what gets fetched.
    static func publishedListURL(for server: Server) -> URL? {
        switch server.name {
        case "HorizonXI": return URL(string: "https://horizonxi.info/addons")
        default: return nil
        }
    }

    /// `fetched` is whatever `ServerFeeds` pulled from the server's own page this launch, which
    /// takes precedence over the list compiled into the app -- that one is a snapshot and goes
    /// stale. Falls back to the snapshot when the fetch failed or the machine is offline.
    static func policy(for server: Server,
                       fetched: [String: AddonPolicy] = [:]) -> AddonPolicy {
        if server.local { return localWorld }
        if let live = fetched[server.name] { return live }
        switch server.name {
        case "HorizonXI": return horizon
        default: return .unknown
        }
    }
}
