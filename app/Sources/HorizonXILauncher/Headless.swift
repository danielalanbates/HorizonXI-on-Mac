import Foundation

/// `--check` — run every world's preflight and print the result, then exit. No window, no
/// wineserver, nothing launched.
///
/// This exists because the failure it is built to catch is invisible from the outside: a world
/// pointed at a folder that holds another world's client launches, connects, and plays *that*
/// world's data (see Install.clientAmbiguity). Checking it by eye means opening the launcher and
/// switching worlds one at a time; checking it here is one command, and it can run while somebody
/// is playing, because it touches nothing.
///
///     FFXI-on-Mac.app/Contents/MacOS/FFXI-on-Mac --check [--world <name>]
///
/// Exit status is 1 if any checked world has a blocking problem, so it is usable from a script.
enum Headless {
    /// True when this process was started to do one job and print about it, rather than to show
    /// a window: `--check` (which exits here) or `--play` (which needs a window, but whose log
    /// belongs on stderr as well -- see Runner.tee).
    static var isHeadlessRun: Bool {
        let a = CommandLine.arguments
        return a.contains("--check") || a.contains("--play")
    }

    @MainActor static func runIfAsked() {
        let args = CommandLine.arguments
        guard args.contains("--check") else { return }
        var only: String? = nil
        if let w = args.firstIndex(of: "--world"), w + 1 < args.count { only = args[w + 1] }

        guard let base = Install.remembered() ?? Install.discover().first else {
            FileHandle.standardError.write(Data("no wrapper/install found\n".utf8))
            exit(2)
        }
        print("install: \(base.wrapper.path) [\(base.prefixName)]\n")

        let store = ServerStore()
        var worst = 0
        for server in store.servers where only == nil || server.name == only! {
            let i = base.forServer(server)
            let checks = Preflight.run(i, profile: server.bootProfile)
            let bad = checks.filter { $0.state == .bad }
            let flag = bad.isEmpty ? "ok  " : "BAD "
            let where_ = server.dataPath.isEmpty ? "(wrapper default)" : i.gameDir.path
            print("\(flag)\(server.name)")
            print("     client   \(where_)")
            print("     ashita   \(i.hasGame ? i.ashitaGeneration.rawValue : "none")  profile \(i.bootProfileName(server.bootProfile))")
            print("     data     \(i.squareEnix.path)")
            for c in bad { print("     ! \(c.title): \(c.detail)") }
            print("")
            if !bad.isEmpty { worst = 1 }
        }
        exit(Int32(worst))
    }
}
