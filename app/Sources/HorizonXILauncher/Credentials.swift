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

    // MARK: - Keychain

    static func savePassword(_ password: String, for user: String) {
        deletePassword(for: user)
        guard !password.isEmpty else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: user,
            kSecValueData as String: Data(password.utf8),
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func password(for user: String) -> String {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: user,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    static func deletePassword(for user: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: user,
        ]
        SecItemDelete(q as CFDictionary)
    }

    // MARK: - Ashita boot profile

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
