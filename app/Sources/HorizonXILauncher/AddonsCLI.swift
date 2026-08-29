import AppKit
import Foundation

/// `--addons` — read and change a world's addon list from the command line. No window, nothing
/// launched, and it can run while somebody is playing: it touches one script file.
///
///     FFXI-on-Mac --addons [list] [--world <name>]
///     FFXI-on-Mac --addons enable <name>[,<name>…] [--world <name>] [--force]
///     FFXI-on-Mac --addons disable <name>[,<name>…] [--world <name>] [--force]
///     FFXI-on-Mac --addons narration on|off
///     FFXI-on-Mac --addons script [--world <name>]
///
/// It exists because the Addons sheet was the only other way, and on 2026-08-29 the sheet wrote
/// the wrong world's script (see AddonSuite.scriptURL). What this writes is exactly what Apply
/// in the sheet writes, for the world named, and it prints the file it wrote and reads it back.
///
/// The server's rules are enforced the same way as in the sheet: on a world with a published
/// allowlist (HorizonXI), enabling an addon that is not on it is refused unless `--force`,
/// because loading one there is a bannable offence. The local LandSandBoat world has no rules.
///
/// Exit status: 0 done · 1 refused by the world's rules · 2 usage, unknown name or no install ·
/// 3 the script could not be written (its launcher markers are missing).
enum AddonsCLI {
    @MainActor static func run(_ args: [String]) -> Int32 {
        guard let at = args.firstIndex(of: "--addons") else { return 2 }
        var rest = Array(args[(at + 1)...])
        var world: String? = nil
        if let w = rest.firstIndex(of: "--world"), w + 1 < rest.count {
            world = rest[w + 1]; rest.removeSubrange(w...(w + 1))
        }
        let force = rest.contains("--force")
        rest.removeAll { $0 == "--force" }
        let verb = rest.first.map { $0.lowercased() } ?? "list"
        let names = rest.count > 1
            ? rest[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : []

        if verb == "narration" { return narration(names.first ?? rest.dropFirst().first ?? "") }
        guard ["list", "enable", "disable", "script"].contains(verb) else {
            err("usage: --addons [list|enable <names>|disable <names>|narration on|off|script] [--world <name>] [--force]")
            return 2
        }

        guard let base = Install.remembered() ?? Install.discover().first else {
            err("no wrapper/install found"); return 2
        }
        let store = ServerStore()
        guard let server = world.map({ name in store.servers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } })
                ?? store.selected else {
            err("no such world: \(world ?? "?")  (worlds: \(store.servers.map(\.name).joined(separator: ", ")))")
            return 2
        }
        let install = base.forServer(server)
        let script = Narration.scriptName(in: install, profile: server.bootProfile)
        let scriptURL = AddonSuite.scriptURL(install, profile: server.bootProfile)
        let policy = AddonPolicies.policy(for: server, fetched: ServerFeeds().fetchedAddonLists)
        var items = AddonSuite.scan(install, profile: server.bootProfile)

        if verb == "script" { print(scriptURL.path); return 0 }

        func rules() -> String {
            switch policy {
            case .unknown: return "no published addon rules sourced for this world; nothing is filtered"
            case let .allowlist(_, source): return "allowlist from \(source)"
            case let .unrestricted(reason): return reason
            }
        }

        if verb == "list" {
            print("world:  \(server.name)  (profile \(install.bootProfileName(server.bootProfile)))")
            print("script: \(scriptURL.path)")
            print("rules:  \(rules())")
            if items.isEmpty { print("(nothing installed under \(install.gameDir.path))"); return 0 }
            print("")
            for it in items {
                let mark = it.enabled ? "on " : "off"
                let kind = it.isPlugin ? "plugin" : "addon "
                var line = "\(mark)  \(kind)  \(it.name)"
                if !it.byline.isEmpty { line += "  (\(it.byline))" }
                if it.manual { line += "  [loaded by a line outside the launcher's block]" }
                if policy.isRestricting, !policy.allows(it.name) { line += "  ** not approved here" }
                print(line)
            }
            return 0
        }

        // enable / disable
        guard !names.isEmpty else { err("--addons \(verb): name at least one addon"); return 2 }
        var changed: [String] = []
        for raw in names {
            let wantPlugin = raw.lowercased().hasPrefix("plugin:")
            let key = (wantPlugin ? String(raw.dropFirst("plugin:".count)) : raw).lowercased()
            // An addon and a plugin can share a name ("Addons" is both a plugin and a folder);
            // a bare name means the addon, `plugin:<name>` the DLL.
            let matches = items.indices.filter {
                items[$0].name.lowercased() == key && (wantPlugin ? items[$0].isPlugin : true)
            }
            guard let idx = matches.first(where: { !items[$0].isPlugin }) ?? matches.first else {
                err("no addon or plugin called \"\(raw)\" is installed under \(install.gameDir.path)/addons (try --addons list)")
                return 2
            }
            let it = items[idx]
            if verb == "enable" {
                if policy.isRestricting, !policy.allows(it.name), !force {
                    err("refused: \(server.name) does not approve \"\(it.name)\" (\(rules())). Loading it there can get the account banned. --force writes it anyway.")
                    return 1
                }
                items[idx].enabled = true
            } else {
                if AddonPolicy.infrastructure.contains(AddonPolicy.normalize(it.name)), !force {
                    err("refused: \"\(it.name)\" is Ashita's own machinery; every Lua addon needs it. --force disables it anyway.")
                    return 1
                }
                items[idx].enabled = false
            }
            changed.append(it.name)
        }
        guard AddonSuite.write(items, to: install, profile: server.bootProfile) else {
            err("could not write \(scriptURL.path): its launcher markers (\(AddonSuite.addonsStart) … \(AddonSuite.addonsStop)) are missing")
            return 3
        }
        // Read it back rather than trusting the write.
        let after = AddonSuite.scan(install, profile: server.bootProfile)
        var ok = true
        for name in changed {
            let now = after.first { $0.name == name }?.enabled ?? false
            let want = (verb == "enable")
            print("\(now == want ? "ok " : "!! ")  \(name): \(now ? "on" : "off") in scripts/\(script)")
            if now != want { ok = false }
        }
        print("wrote \(scriptURL.path) — takes effect the next time you press Play for \(server.name)")
        if verb == "enable", changed.contains(where: { $0.lowercased() == "vanavoice" }),
           !PerfSettings.load().narrateCutscenes {
            print("note: narration is OFF in the launcher, and Play removes the vanavoice line when it is off. Run: --addons narration on")
        }
        return ok ? 0 : 3
    }

    /// The launcher's "Read cutscenes aloud (VanaVoice)" setting, which decides whether Play
    /// installs the narrator addon and its load line or strips them.
    @MainActor private static func narration(_ value: String) -> Int32 {
        let v = value.lowercased()
        guard v == "on" || v == "off" else { err("usage: --addons narration on|off"); return 2 }
        var perf = PerfSettings.load()
        perf.narrateCutscenes = (v == "on")
        perf.save()
        print("narration: \(v)  (perf.settings in \(Bundle.main.bundleIdentifier ?? "org.batesai.horizonxi-on-mac"))")
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == (Bundle.main.bundleIdentifier ?? "org.batesai.horizonxi-on-mac")
                && $0.processIdentifier != me
        }
        if !others.isEmpty {
            print("note: the launcher window is open (pid \(others.map { String($0.processIdentifier) }.joined(separator: ", "))). It holds its own copy of the settings and writes them back when you change anything there; flip the toggle under SETUP & DIAGNOSTICS too, or quit and reopen it.")
        }
        return 0
    }

    private static func err(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }
}
