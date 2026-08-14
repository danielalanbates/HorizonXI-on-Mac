import Foundation

/// Ashita's plugin and addon suite, managed the way HorizonXI's own Windows launcher manages it.
///
/// Ashita does not take a list of addons in its .ini. It runs `scripts/default.txt` after
/// injecting, and that script's `/load` and `/addon load` lines are what actually enable
/// anything. HorizonXI's launcher owns two marked blocks in that file and rewrites them; this
/// does the same, touching only what is between the markers so a hand-written custom section
/// below them survives untouched.
struct AddonSuite {
    struct Item: Identifiable, Hashable {
        var name: String
        var isPlugin: Bool
        var enabled: Bool
        var id: String { (isPlugin ? "p:" : "a:") + name.lowercased() }
    }

    static let pluginsStart = "# --HORIZON_PLUGINS_START--"
    static let pluginsStop  = "# --HORIZON_PLUGINS_STOP--"
    static let addonsStart  = "# --HORIZON_ADDONS_START--"
    static let addonsStop   = "# --HORIZON_ADDONS_STOP--"

    static func scriptURL(_ i: Install) -> URL {
        i.gameDir.appendingPathComponent("scripts/default.txt")
    }

    /// Everything installed, with the ones the script currently loads marked enabled.
    static func scan(_ i: Install) -> [Item] {
        let fm = FileManager.default
        let text = (try? String(contentsOf: scriptURL(i), encoding: .utf8)) ?? ""
        let onPlugins = Set(loadedNames(in: text, start: pluginsStart, stop: pluginsStop,
                                        prefix: "/load "))
        let onAddons = Set(loadedNames(in: text, start: addonsStart, stop: addonsStop,
                                       prefix: "/addon load "))

        var out: [Item] = []
        // Plugins are DLLs. `winefix` is this project's own compatibility shim rather than a
        // user-facing feature, and turning it off breaks the game on wine, so it is not offered.
        let pluginDir = i.gameDir.appendingPathComponent("plugins")
        if let kids = try? fm.contentsOfDirectory(at: pluginDir, includingPropertiesForKeys: nil) {
            for k in kids where k.pathExtension.lowercased() == "dll" {
                let name = k.deletingPathExtension().lastPathComponent
                if name.lowercased() == "winefix" { continue }
                out.append(Item(name: name, isPlugin: true,
                                enabled: onPlugins.contains(name.lowercased())))
            }
        }
        // Addons are directories containing <name>.lua.
        let addonDir = i.gameDir.appendingPathComponent("addons")
        if let kids = try? fm.contentsOfDirectory(at: addonDir, includingPropertiesForKeys: nil) {
            for k in kids {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: k.path, isDirectory: &isDir), isDir.boolValue
                else { continue }
                let name = k.lastPathComponent
                guard fm.fileExists(atPath: k.appendingPathComponent("\(name).lua").path)
                else { continue }
                out.append(Item(name: name, isPlugin: false,
                                enabled: onAddons.contains(name.lowercased())))
            }
        }
        return out.sorted { ($0.isPlugin ? 0 : 1, $0.name.lowercased())
                          < ($1.isPlugin ? 0 : 1, $1.name.lowercased()) }
    }

    private static func loadedNames(in text: String, start: String, stop: String,
                                    prefix: String) -> [String] {
        var out: [String] = []
        // A default.txt with no markers is the normal case for an install whose script was
        // written by hand or by a server other than HorizonXI. Reading only between markers
        // there found nothing, so every addon the player actually runs showed as disabled.
        // Without markers, the whole file is the managed region.
        let hasMarkers = text.contains(start) && text.contains(stop)
        var inside = !hasMarkers
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == start { inside = true; continue }
            if line == stop { inside = false; continue }
            guard inside, line.lowercased().hasPrefix(prefix) else { continue }
            out.append(String(line.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespaces).lowercased())
        }
        return out
    }

    /// Rewrite both managed blocks. Returns false if the script is missing its markers, in which
    /// case nothing is written — better to do nothing than to guess where the block belongs in a
    /// file the server's own launcher also edits.
    @discardableResult
    static func write(_ items: [Item], to install: Install) -> Bool {
        let url = scriptURL(install)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Addons live below plugins in the file, so replacing the lower block first keeps the
        // upper block's indices valid.
        let addonBody = items.filter { !$0.isPlugin && $0.enabled }
            .map { "/addon load \($0.name)" }
        let pluginBody = items.filter { $0.isPlugin && $0.enabled }
            .map { "/load \($0.name)" }

        if !(text.contains(pluginsStart) && text.contains(addonsStart)) {
            adoptScript(&lines)
        }

        guard replace(&lines, start: addonsStart, stop: addonsStop, with: addonBody),
              replace(&lines, start: pluginsStart, stop: pluginsStop, with: pluginBody)
        else { return false }

        return (try? lines.joined(separator: "\n").write(to: url, atomically: true,
                                                         encoding: .utf8)) != nil
    }

    /// Put the managed markers into a script that has none, so the launcher can own the load
    /// lines from then on. The existing `/load` and `/addon load` lines are removed and the two
    /// empty blocks take their place; everything else in the file — `/wait`, `/ambient`, aliases,
    /// whatever the player added — keeps its position. `winefix` is deliberately left where it
    /// is: it is this project's compatibility shim, not a user-facing addon, and the UI never
    /// offers it, so it must not be swept into a block the UI rewrites.
    private static func adoptScript(_ lines: inout [String]) {
        var insertAt: Int? = nil
        var kept: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            let isLoad = (t.hasPrefix("/load ") || t.hasPrefix("/addon load "))
                && t != "/load winefix"
            if isLoad {
                if insertAt == nil { insertAt = kept.count }
                continue
            }
            kept.append(line)
        }
        let at = insertAt ?? kept.count
        kept.insert(contentsOf: [pluginsStart, pluginsStop, addonsStart, addonsStop], at: at)
        lines = kept
    }

    private static func replace(_ lines: inout [String], start: String, stop: String,
                                with body: [String]) -> Bool {
        guard let a = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == start }),
              let b = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == stop }),
              a < b
        else { return false }
        lines.replaceSubrange((a + 1)..<b, with: body)
        return true
    }

    /// Ashita refuses any plugin built against a different interface version than its core, and
    /// the client's log is the only place that shows it. Surfacing it matters: a mismatch means
    /// the Lua host (`addons`) does not load either, so *every* addon silently does nothing while
    /// the script still lists them as loaded.
    static func mismatchedPlugins(_ i: Install) -> [String] {
        let logs = i.gameDir.appendingPathComponent("logs")
        guard let kids = try? FileManager.default.contentsOfDirectory(
                at: logs, includingPropertiesForKeys: [.contentModificationDateKey]),
              let newest = kids.filter({ $0.pathExtension == "txt" }).max(by: {
                  (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
                      ?? .distantPast
                  < (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
                      ?? .distantPast
              }),
              let text = try? String(contentsOf: newest, encoding: .utf8)
        else { return [] }

        var out: [String] = []
        for line in text.split(separator: "\n") where line.contains("different interface version") {
            // ...Failed to load plugin 'addons'; plugin is compiled with...
            guard let a = line.range(of: "'"),
                  let b = line.range(of: "'", range: a.upperBound..<line.endIndex)
            else { continue }
            out.append(String(line[a.upperBound..<b.lowerBound]))
        }
        return Array(Set(out)).sorted()
    }
}
