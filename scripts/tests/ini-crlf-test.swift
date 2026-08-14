// Regression test for the CRLF bug: Swift treats "\r\n" as ONE Character, so
// split(separator: "\n") returns a CRLF file as a single line and every line-based
// rewrite silently does nothing. horizonxi.ini ships CRLF, so nothing the graphics
// panel wrote ever reached it. See TextFile.swift.
//
//   swiftc -o /tmp/it scripts/tests/ini-crlf-test.swift <a Credentials stub> \
//       app/Sources/HorizonXILauncher/Graphics.swift \
//       app/Sources/HorizonXILauncher/TextFile.swift && /tmp/it <prefix-with-config/boot/t.ini>
//
// Expected: "read back: world 3840x2160 ui 960x540 follows=false", CRLF preserved.

import Foundation
struct Install { var gameDir: URL }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let inst = Install(gameDir: dir)
let ini = dir.appendingPathComponent("config/boot/t.ini")
print("exists:", FileManager.default.fileExists(atPath: ini.path))
let before = (try? String(contentsOf: ini, encoding: .utf8)) ?? ""
print("read \(before.count) chars; CRLF:", before.contains("\r\n"))

var g = GraphicsSettings()
g.width = 3840; g.height = 2160
g.uiFollowsResolution = false
g.uiWidth = 960; g.uiHeight = 540
print("overrides:", g.iniOverrides.filter { ["0001","0002","0037","0038"].contains($0.key) })
g.write(to: inst, profile: "t.ini")

let after = (try? String(contentsOf: ini, encoding: .utf8)) ?? ""
for line in after.split(separator: "\n") {
    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("0001") || t.hasPrefix("0002") || t.hasPrefix("0037") || t.hasPrefix("0038") {
        print("  AFTER: \(t)")
    }
}
if let back = GraphicsSettings.read(from: inst, profile: "t.ini") {
    print("read back: world \(back.width)x\(back.height) ui \(back.uiWidth)x\(back.uiHeight) follows=\(back.uiFollowsResolution)")
} else { print("read back: nil") }
