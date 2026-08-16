import Foundation

/// The pre-game version check.
///
/// Every LandSandBoat-based server compares the retail patch level the client reports (packet
/// 0x26, offset 0x74) with its `login.CLIENT_VER`, and with `VER_LOCK` on answers an older client
/// with error 331 — "The game's data has been updated. Please update to continue." That is what
/// CatsEyeXI says to a HorizonXI install: HorizonXI's client was at 30251101_2 on 2026-08-15,
/// CatsEye demands 30251204_1 or newer.
///
/// This file answers "what is installed" and "what does the selected world need"; the update
/// itself is `scripts/update-client.sh` (HorizonXI only — see docs/CLIENT-UPDATES.md for why
/// CatsEye's client cannot be fetched by anything but their own launcher).
enum ClientVersion {
    /// Newest retail patch group recorded in the client's own `patch.cfg`. Best available
    /// stand-in for the version the client sends the login server; nil when there is no client.
    static func installed(in install: Install) -> String? {
        let cfg = install.squareEnix.appendingPathComponent("FINAL FANTASY XI/patch.cfg")
        guard let text = try? String(contentsOf: cfg, encoding: .isoLatin1) else { return nil }
        return newestPatchID(in: text)
    }

    /// HorizonXI's own marketing version for the install (`version.json`), if this is one.
    static func horizonVersion(in install: Install) -> String? {
        let f = install.gameDir.appendingPathComponent("version.json")
        guard let d = try? Data(contentsOf: f),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return nil }
        return o["version"] as? String
    }

    static func newestPatchID(in text: String) -> String? {
        var best: String?
        for m in Self.matches(#"\b30\d{6}_\d\b"#, in: text) where best == nil || m > best! { best = m }
        return best
    }

    /// `CLIENT_VER = '30251204_1'` out of a LandSandBoat login.lua.
    static func parseClientVer(_ lua: String) -> String? {
        matches(#"CLIENT_VER\s*=\s*['"](30\d{6}_\d)['"]"#, in: lua, group: 1).first
    }

    /// Patch ids are fixed-width `YYMMDD_n` under a constant `30`, so string order is date order.
    static func isOlder(_ installed: String, than required: String) -> Bool {
        installed < required
    }

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            let r = $0.range(at: group)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}
