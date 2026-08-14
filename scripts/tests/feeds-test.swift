import Foundation
// Only the HTML parser is exercised here; no networking, so the test is deterministic.
let html = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let names = ServerFeeds.namesFromHTML(html)
print("parsed \(names.count) candidate names")
let want = ["Allmaps","Battlemod","Checker","Distance","Filterless","Timers","XICamera","Toon"]
let set = Set(names.map { AddonPolicy.normalize($0) })
for w in want {
    print(set.contains(AddonPolicy.normalize(w)) ? "  ok  \(w)" : "  MISSING \(w)")
}
let policy = AddonPolicy.allowlist(published: names, source: "test")
// The real check: does the fetched list still permit what is installed and approved, and still
// refuse something plainly not on it?
for probe in ["allmaps", "battlemod", "tparty", "definitely-not-an-addon-xyz"] {
    print("  allows \(probe): \(policy.allows(probe))")
}
