# x87 acceleration: the contract, and the day we got it wrong

**One-line version: set `ROSETTA_X87_PATH` to the sidecar binary and launch wine normally. Do not
wrap the command with the sidecar, and do not set `ROSETTA_DISABLE_AOT` yourself.**

This document exists because getting that backwards cost a full day and made the game unplayable
twice over — once at 3 fps, once at 8 — while every measurement said things were fine.

## Why x87 matters at all

FFXI's client is 32-bit and does its floating-point maths through x87. Rosetta 2 emulates x87 at
roughly 1% of native speed, and that — not the renderer, not Metal, not DXVK — is what pins the
game in the single digits in-world. `docs/X87-WALL.md` has the profiling that established it.
The sidecar ([athei/x87sidecar](https://github.com/athei/x87sidecar)) replaces Rosetta's x87
handlers with a native ARM64 JIT. Measured worth: **11.3 → 28.5 fps in-world at max settings.**

## The contract

Two pieces, both already on this machine:

| piece | where | what it does |
| --- | --- | --- |
| `x87sidecar-coop` | bundled in `FFXI-on-Mac.app/Contents/Resources` | the JIT; serves whoever handshakes with it |
| patched CX wine | `/Volumes/Games/FFXI/wine-coop` | re-execs i386 processes through the sidecar and performs the handshake |

The wine side is [athei/wine `3804c30b`](https://github.com/athei/wine/commit/3804c30b), *"ntdll:
HACK: Recognize ROSETTA_X87_PATH and attach x87sidecar cooperatively"*:

> For i386 targets, re-exec through the x87sidecar named in `ROSETTA_X87_PATH` … wine hands it our
> task + main-thread control ports from a handshake at the top of `__wine_main`.

So the mechanism is **per wine process, driven by an environment variable**:

    preloader_exec  →  re-exec as `x87sidecar --cooperative <loader> <args>`
    __wine_main     →  x87_cooperative_handshake() hands over task + thread ports

Every i386 wine process that starts with `ROSETTA_X87_PATH` set does this for itself. That is the
whole design, and it is the only reason the *game* can be accelerated at all — see below.

## What we did wrong

The launcher wrapped the command instead:

    x87sidecar-coop --cooperative wine Ashita-cli.exe horizonxi.ini    # WRONG

That looks equivalent and is not, because of how Ashita boots FFXI:

    Ashita-cli.exe   ← the injector. Injects Ashita.dll, then EXITS within seconds.
      └─ horizon-loader.exe   ← the actual game. Renders. Burns the x87. Runs for hours.

Wrapping accelerates the process the sidecar launched — the injector — and nothing else. Worse,
the sidecar lives exactly as long as its direct child, so seconds after launch it exits too, and
the client that Ashita just spawned has nothing left to handshake with even in principle.

Measured, same launch either way (`X87_LOGS=1`, counting `x87 coop: handed over task+thread ports`):

| invocation | handshakes | sidecar after 25 s | in-world |
| --- | --- | --- | --- |
| `x87sidecar-coop --cooperative wine Ashita-cli.exe …` | **1** (injector) | exited | ~8 fps |
| `ROSETTA_X87_PATH=… wine Ashita-cli.exe …` | **2** (injector + client) | alive | accelerated |

And the second mistake compounded the first: with the wrapper we also set `ROSETTA_DISABLE_AOT=1`
by hand. That flag is what makes Rosetta call the hook the sidecar patches — it disables the AOT
cache, which is a *huge* cost when no JIT is actually attached. So the client paid the full AOT
penalty and got none of the JIT: **2.98 fps**, worse than doing nothing at all (58 on the same
scene). The sidecar sets that flag itself when it attaches (`g_disable_aot=1`); setting it by hand
only creates the failure mode where the cost lands without the benefit.

## Two red herrings that kept it hidden

1. **Menu frame rate is meaningless.** The rules-of-conduct screen draws 382 primitives and runs at
   58 fps whatever x87 does; in-world draws ~1,150 and is entirely x87-bound. A whole verification
   pass "confirmed" 58 fps while the game was at 8. **Always measure in-world.**
2. **attach-by-pid looks like the alternative and is not.** On macOS 26.5.2 it kills the client
   about five seconds after launch (`UninstallAshita (228)`, before DXVK writes its first line).
   It is not a fallback; it is a crash.

## How to verify it is actually working

    X87_LOGS=1 … wine C:\<world>\Ashita-cli.exe <profile>.ini 2>&1 | grep "handed over task"

**Two or more** lines means the client is covered. One means only the injector is. Also useful:

* `[rosettax87] cooperative service registered: x87sidecar.<pid>` — the sidecar came up.
* `[rosettax87] cooperative attach: task=… thread=… reply=…` — a process was accepted.
* `X87_LOG_THROUGHPUT=1` — the sidecar prints requests/s; a live game shows steady traffic.
* CPU: an unaccelerated client pins ~100% of one core and stays there.

For frame rate, use the launcher's own switch so the measurement matches what Play does:

    FFXI_ON_MAC_FPSLOG=1 open -a /Applications/FFXI-on-Mac.app --args --world HorizonXI --play

which writes `fps.csv` next to the client. Read only the rows with >800 draws — those are in-world.

**Known measurement gap:** on the `ROSETTA_X87_PATH` pathway, `DXVK_FPS_LOG` did not produce a file
in the one run it was tried, though the same variable works on the plain pathway. Not diagnosed;
if a measurement run comes back with no CSV, this is why, and the CPU check above still works.

## Rules

1. **Set `ROSETTA_X87_PATH`, never wrap the command.** `PerfSettings.environment` does this.
2. **Never set `ROSETTA_DISABLE_AOT` by hand.** The sidecar owns that flag.
3. **Never use attach-by-pid on macOS ≥ 26.5.2.** It kills the client.
4. **Rebuild the sidecar after a macOS update.** It patches Rosetta internals; upstream says so.
5. **Judge it in-world, on the shipped Play path.** Menus and hand-built shell runs have both
   produced confident, wrong answers here — a shell run using a different wine than Play is how a
   19x regression reached the player.

## Per-world exceptions

`Server.x87` turns this off for a world whose client cannot take it. Today that is **Gaia XI**,
whose client exits at boot with the sidecar attached (`docs/SERVERS-WORKLOG.md`, 2026-08-21). The
launcher logs which world it skipped and why.

## Upstream

* [athei/x87sidecar](https://github.com/athei/x87sidecar) — the JIT. Head as of 2026-08-21 is
  `238a2147` (2026-08-12), which is exactly what this project vendors: **there is no newer upstream
  fix waiting to be picked up**, and no open issue describing this.
* [athei/wine-build](https://github.com/athei/wine-build) — the prebuilt CX wine.
  `cx-26.3.0-1` (2026-08-19) is current and is what `/Volumes/Games/FFXI/wine-coop` holds.
* [athei/wine `cx-26-patched`](https://github.com/athei/wine/tree/cx-26-patched) — the wine patches,
  including `3804c30b` above.

Nothing needs to be sent upstream for this: the bug was ours, in how the launcher invoked a working
mechanism. Worth reporting only if we hit a case where `ROSETTA_X87_PATH` is set and a spawned i386
process still does not handshake.
