import Foundation

/// Start a process that outlives this app.
///
/// Why this exists
/// ---------------
/// Everything the launcher started used to die with it. Two separate reasons, and both had to
/// go:
///
/// 1. **Session membership.** `Foundation.Process` children inherit the launcher's process
///    group and session, so anything that signals the group -- a force-quit, a crash, the
///    Dock's "Force Quit" -- takes the game with it.
/// 2. **The x87 sidecar.** It is attached to the running client for the whole session and does
///    not exit on its own, so the launcher terminated it when the game ended. Quitting the
///    launcher therefore killed the sidecar, and without it the client drops back to Rosetta's
///    stock x87 speed -- the difference between 28 fps and 11 (docs/X87-WALL.md). Surviving the
///    quit is no good if the game is left crawling.
///
/// `posix_spawn` with `POSIX_SPAWN_SETSID` puts the child in a brand-new session: it has no
/// controlling terminal, is in no process group of ours, and is reparented to launchd when this
/// app exits. Foundation's `Process` cannot ask for that, which is why this drops to posix_spawn.
enum Detach {

    /// Spawn `exe` detached. Returns the child's pid, or nil if the spawn failed.
    ///
    /// `stdoutPath`, when given, receives both stdout and stderr, appended. The launcher tails
    /// that file rather than holding a pipe -- a pipe would tie the child's writes to this
    /// process being alive to drain them, which is the coupling being removed.
    @discardableResult
    static func spawn(_ exe: URL, args: [String], env: [String: String],
                      cwd: URL?, stdoutPath: String?) -> pid_t? {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // POSIX_SPAWN_SETSID is the whole point. POSIX_SPAWN_CLOEXEC_DEFAULT closes every
        // descriptor this app happens to have open rather than leaking them into the game.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if let path = stdoutPath {
            posix_spawn_file_actions_addopen(&actions, 1, path,
                                             O_WRONLY | O_CREAT | O_APPEND, 0o644)
            posix_spawn_file_actions_adddup2(&actions, 1, 2)
        } else {
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, 1, 2)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)

        // posix_spawn has no "working directory" argument, so go through a shell for that. It
        // is also how the game has always been started (see Runner.spawnViaShell), and the
        // launch is known to be sensitive to it.
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var command = ([exe.path] + args).map(q).joined(separator: " ")
        // /bin/sh is a platform (SIP-protected) binary, and dyld strips every DYLD_* variable
        // from such a process's environment before main() -- so anything handed to the shell in
        // `env` never reached wine, and audiofollow.dylib silently failed to load in every
        // launch (found 2026-08-26 by lsof on the live client). Set those in the *shell's*
        // command line instead: the shell exports them itself and the unsigned wine loader,
        // which dyld does not restrict, picks them up. The equivalent gotcha for arch(1) is in
        // docs/AUDIO.md; this is the same rule for any system binary in the exec chain.
        let dyld = env.filter { $0.key.hasPrefix("DYLD_") }
        let shellEnv = env.filter { !$0.key.hasPrefix("DYLD_") }
        let assigns = dyld.keys.sorted().map { "\($0)=\(q(dyld[$0]!))" }.joined(separator: " ")
        let prefixed = assigns.isEmpty ? "exec \(command)" : "\(assigns) exec \(command)"
        if let cwd { command = "cd \(q(cwd.path)) && \(prefixed)" } else { command = prefixed }

        let argv: [String] = ["/bin/sh", "-c", command]
        var cargv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cargv.append(nil)
        var cenv: [UnsafeMutablePointer<CChar>?] = shellEnv.map { strdup("\($0.key)=\($0.value)") }
        cenv.append(nil)
        defer {
            for p in cargv where p != nil { free(p) }
            for p in cenv where p != nil { free(p) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/sh", &actions, &attr, &cargv, &cenv)
        return rc == 0 ? pid : nil
    }

    /// Is this pid still alive? `kill(pid, 0)` asks without sending anything.
    ///
    /// A detached child is not ours any more, so `Process.isRunning` and `terminationHandler`
    /// are both unavailable -- this is what replaces them.
    static func isAlive(_ pid: pid_t) -> Bool {
        // A detached child is still *this process's* child until the launcher exits (a new
        // session does not reparent it), so when it dies it lingers as a zombie until someone
        // waits on it -- and `kill(pid, 0)` succeeds on a zombie. Found 2026-08-27: the previous
        // day's injector sat `<defunct>` for 12 hours, this returned true the whole time, the
        // "injector exited" callback never fired, and the Play button stayed at RUNNING until
        // the app was quit. Reap first; only a live process survives both checks.
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Arrange for `victim` to be killed once no process matching `whilePattern` is left.
    ///
    /// The sidecar has to die when the game does, and the launcher can no longer be the thing
    /// that notices -- it may not be running. So the job is handed to a detached shell, which
    /// costs one sleeping `sh` per session and survives the launcher exactly as the game does.
    static func killWhenGone(victim: pid_t, whilePattern: String) {
        let script = "while /usr/bin/pgrep -qf \(whilePattern.replacingOccurrences(of: "'", with: "")) ; "
                   + "do /bin/sleep 2; done; /bin/kill \(victim) 2>/dev/null"
        spawn(URL(fileURLWithPath: "/bin/sh"), args: ["-c", script],
              env: ["PATH": "/usr/bin:/bin"], cwd: nil, stdoutPath: nil)
    }
}
