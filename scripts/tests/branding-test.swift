import Foundation
struct Install { var gameDir: URL }
struct Server { var name: String }

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let install = Install(gameDir: dir)
let ini = dir.appendingPathComponent("config/pivot/pivot.ini")

func show(_ label: String) {
    let t = (try? String(contentsOf: ini, encoding: .utf8)) ?? "<unreadable>"
    print("=== \(label) ===\n\(t)")
}
show("start")
print("apply(stock:true) ->", Branding.apply(stockBranding: true, to: install))
show("stock branding on")
print("apply(stock:true) again ->", Branding.apply(stockBranding: true, to: install))
let t = (try? String(contentsOf: ini, encoding: .utf8)) ?? ""
print("idempotent (one stockbrand line):",
      t.components(separatedBy: "=stockbrand").count - 1 == 1)
print("apply(stock:false) ->", Branding.apply(stockBranding: false, to: install))
show("stock branding off")
print("HorizonXI wants stock?", Branding.wantsStockBranding(Server(name: "HorizonXI")))
print("Local server wants stock?", Branding.wantsStockBranding(Server(name: "Local server")))
print("Eden wants stock?", Branding.wantsStockBranding(Server(name: "Eden")))

// Run against a throwaway prefix, not a real one:
//
//   mkdir -p /tmp/fake/config/pivot /tmp/fake/polplugins/DATs/stockbrand/ROM/119
//   printf '[settings]\nroot_path=x\n[overlays]\n0=horizonmusic\n1=xiview\n' \
//       > /tmp/fake/config/pivot/pivot.ini
//   touch /tmp/fake/polplugins/DATs/stockbrand/ROM/119/50.dat
//   swiftc -o /tmp/bt scripts/tests/branding-test.swift \
//       app/Sources/HorizonXILauncher/Branding.swift && /tmp/bt /tmp/fake
//
// Checks that the overlay goes in first, that applying twice does not duplicate it, that turning
// it off restores the original list, that [settings] survives, and that HorizonXI keeps its own
// branding while every other world does not.
