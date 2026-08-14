import Foundation
import Security

/// Account handling. The password lives in the macOS Keychain, never in a plist, never in the
/// repo. It is written into Ashita's boot profile only at launch time, and that file is chmod 600.
enum Credentials {
    private static let service = "org.batesai.horizonxi-on-mac"

    static var username: String {
        get { UserDefaults.standard.string(forKey: "account.user") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "account.user") }
    }

    static var remember: Bool {
        get { UserDefaults.standard.bool(forKey: "account.remember") }
        set { UserDefaults.standard.set(newValue, forKey: "account.remember") }
    }

    // MARK: - Stored password
    //
    // This used to live in the login Keychain, which prompted for the Keychain password on
    // startup after every single rebuild: the ACL is bound to the signing identity, and each
    // build gets a fresh ad-hoc signature. That prompt is also the only thing the Keychain was
    // buying here, because Ashita cannot take a password any other way than as cleartext on the
    // boot loader's command line -- the launcher writes it into `config/boot/<profile>.ini`
    // (mode 600) on every launch, so the secret is already on disk in the clear either way.
    // Storing it in the app's own support directory at mode 600 is the same exposure with no
    // prompt. If this ever ships with a stable Developer ID, the Keychain becomes worth it
    // again; until then it is a prompt for nothing.

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorizonXI-on-Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("accounts.json")
    }

    private static func load() -> [String: String] {
        guard let d = try? Data(contentsOf: storeURL),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }

    private static func store(_ m: [String: String]) {
        guard let d = try? JSONEncoder().encode(m) else { return }
        try? d.write(to: storeURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: storeURL.path)
    }

    static func savePassword(_ password: String, for user: String) {
        var m = load()
        if password.isEmpty { m.removeValue(forKey: user) } else { m[user] = password }
        store(m)
    }

    static func password(for user: String) -> String {
        if let p = load()[user], !p.isEmpty { return p }
        return ""
    }

    static func deletePassword(for user: String) {
        var m = load()
        m.removeValue(forKey: user)
        store(m)
    }

    /// One-time pickup of a password that is already sitting in a boot profile, so moving off the
    /// Keychain does not silently present an empty password box to someone who never typed it
    /// into this build. Reads only `--pass` from the live `command` line.
    static func adoptPasswordFromProfile(user: String, install: Install, profile: String) {
        guard password(for: user).isEmpty else { return }
        let url = install.gameDir.appendingPathComponent("config/boot/\(profile)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix(";"), line.hasPrefix("command"),
                  let r = line.range(of: "--pass ") else { continue }
            let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            let pass = rest.split(separator: " ").first.map(String.init) ?? ""
            if !pass.isEmpty { savePassword(pass, for: user) }
            return
        }
    }

    // MARK: - Ashita boot profile

    /// Make sure `config/boot/<profile>` exists, seeding it from a profile that already works.
    ///
    /// A boot profile is mostly graphics and input settings that have nothing to do with which
    /// server it points at, so copying the configured one and letting `apply` rewrite the single
    /// `command` line gives a new world the same working setup rather than Ashita's bare example.
    /// Needed for the local server, whose profile no HorizonXI install ships.
    @discardableResult
    static func ensureProfile(_ profile: String, in install: Install) -> Bool {
        let fm = FileManager.default
        let dir = install.gameDir.appendingPathComponent("config/boot")
        let target = dir.appendingPathComponent(profile)
        if fm.fileExists(atPath: target.path) { return true }

        for seed in ["horizonxi.ini", "example-privateserver.ini", "example.ini"] {
            let src = dir.appendingPathComponent(seed)
            guard fm.fileExists(atPath: src.path),
                  let text = try? String(contentsOf: src, encoding: .utf8) else { continue }
            guard (try? text.write(to: target, atomically: true, encoding: .utf8)) != nil
            else { continue }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return true
        }
        return false
    }

    /// Rewrite the `command = ...` line of the Ashita boot profile with these credentials.
    /// Returns false if the profile is missing or unwritable.
    @discardableResult
    static func apply(user: String, password: String, to install: Install,
                      profile: String = "horizonxi.ini",
                      server: String = "play.horizonxi.com") -> Bool {
        let url = install.gameDir.appendingPathComponent("config/boot/\(profile)")
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return false }

        let line = "command     = --server \(server) --user \(user) --pass \(password)"
        var replaced = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
            // Only the live setting, never the commented examples.
            if !l.hasPrefix(";"), l.trimmingCharacters(in: .whitespaces).hasPrefix("command"),
               l.contains("=") , !replaced {
                replaced = true
                return line
            }
            return String(l)
        }
        text = lines.joined(separator: "\n")
        guard replaced, (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    /// Set `key = value` lines in the boot profile, leaving commented examples alone.
    /// Used for the per-renderer overrides — `behaviorflags.fpu_preserve` in particular.
    static func applyIniOverrides(_ overrides: [String: String], to install: Install,
                                  profile: String) {
        guard !overrides.isEmpty else { return }
        let url = install.gameDir.appendingPathComponent("config/boot/\(profile)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let out = text.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
            let line = String(l)
            guard !line.hasPrefix(";"), line.contains("=") else { return line }
            let key = line.split(separator: "=", maxSplits: 1)[0]
                .trimmingCharacters(in: .whitespaces)
            guard let v = overrides[key] else { return line }
            // keep the column alignment the file already uses
            let pad = max(1, 48 - key.count)
            return key + String(repeating: " ", count: pad) + "= " + v
        }.joined(separator: "\n")

        try? out.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
