import Foundation
struct Install { var gameDir: URL }
enum Credentials {
    static func applyIniOverrides(_ o: [String: String], to i: Install, profile: String) {}
}

var g = GraphicsSettings()
g.width = 3840; g.height = 2160
g.uiFollowsResolution = true
print("matched  -> 0037/0038 =", g.iniOverrides["0037"]!, g.iniOverrides["0038"]!)

g.uiFollowsResolution = false
g.uiWidth = 1280; g.uiHeight = 720
let o = g.iniOverrides
print("separate -> world 0001/0002 =", o["0001"]!, o["0002"]!,
      "| interface 0037/0038 =", o["0037"]!, o["0038"]!)
print("world resolution unchanged by interface setting:", o["0001"] == "3840" && o["0002"] == "2160")

// round-trip through a real boot profile
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gfxrt")
try? FileManager.default.createDirectory(
    at: dir.appendingPathComponent("config/boot"), withIntermediateDirectories: true)
let ini = dir.appendingPathComponent("config/boot/t.ini")
var body = "[ffxi.registry]\n"
for (k, v) in o.sorted(by: { $0.key < $1.key }) { body += "\(k) = \(v)\n" }
try? body.write(to: ini, atomically: true, encoding: .utf8)
if let back = GraphicsSettings.read(from: Install(gameDir: dir), profile: "t.ini") {
    print("read back -> ui \(back.uiWidth)x\(back.uiHeight), follows=\(back.uiFollowsResolution)")
    print("round-trips:", back.uiWidth == 1280 && back.uiHeight == 720
                          && back.uiFollowsResolution == false
                          && back.width == 3840)
} else { print("read back FAILED") }

// an old settings blob, missing the two new keys, must not reset everything
let old = #"{"width":2560,"height":1440,"uiFollowsResolution":false,"textureResolution":4096,"mipMapping":2,"textureCompression":2,"bumpMapping":true,"environmentAnimation":true,"soundChannels":20}"#
if let d = try? JSONDecoder().decode(GraphicsSettings.self, from: Data(old.utf8)) {
    print("old blob decodes -> \(d.width)x\(d.height), ui \(d.uiWidth)x\(d.uiHeight)",
          "| preserved:", d.width == 2560 && d.textureResolution == 4096)
} else { print("old blob FAILED to decode -- would silently reset the user's settings") }
