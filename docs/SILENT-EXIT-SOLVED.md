# The silent exit, solved — Sandbox's `use_interface_bypass`

**Date:** 2026-08-16
**Symptom:** the client logs in and then quits, about two seconds later, with no window, no error,
no crash dump and zero d3d8 calls:

```
[..] Successfully logged in as <account>!
[..] Connected to server!
[..] Closing...
```

This is the failure recorded in [FINDINGS.md](FINDINGS.md) §2 as unexplained after weeks of work.
It is **not** graphics, not wine, not the game data, not COM, not the registry, and not the
loader. It is one line in one config file.

## Cause

Ashita's **Sandbox** POL plugin virtualises the PlayOnline registry for the game. Its
`use_interface_bypass` hook patches FFXI's `patch.ver` interface-id check — the check that reads
`HKLM\SOFTWARE\PlayOnlineUS\Interface` (`Wow6432Node` in the 32-bit view) to decide whether the
installed game data is the build PlayOnline expects.

A private-server client never has valid `Interface` values. With the bypass **off**, that check
fails, and FFXI does not report it. It reads `patch.ver`, takes an unadvertised failure path,
calls `UnregisterClassA("FFXiClass")` for a window class it never registered, and exits. That is
exactly the trace in FINDINGS §"The exact last sequence before death" — which was correct all
along, and pointed at `patch.ver`; what was missing was that Sandbox is what makes that check
pass.

`config/sandbox/sandbox.ini` in this install had:

```ini
use_interface_bypass = 0
```

Ashita ships it as `1` and its own documentation says `Default: 1`.

## Evidence

Measured on the live HorizonXI install, boot profile otherwise unchanged, one variable at a time:

| `[ashita.polplugins]` | `use_interface_bypass` | result |
| --- | --- | --- |
| `sandbox=0 pivot=0` | (not loaded) | launches, renders |
| `sandbox=0 pivot=1` | (not loaded) | launches, renders |
| `sandbox=1 pivot=0` | `0` | **exits ~2 s after login** |
| `sandbox=1 pivot=1` | `0` | **exits ~2 s after login** |
| `sandbox=1 pivot=1` | `1` | launches, reaches character select |

The control that isolated it: a **byte-identical, untouched HorizonXI 2.0.3 client**
(`/Volumes/Games/FFXI/HorizonXI-fresh`) symlinked into the *same wine prefix* and launched with
its own stock boot profile ran perfectly and reached the title screen. Same wine, same MoltenVK,
same registry, same Mac. The only difference was its stock `sandbox.ini`, with the bypass on.

Ruled out along the way, each by direct test: the wrapper move to a new volume, the game data
(rsync `-c` against the previous copy: every difference is a HorizonXI update, nothing else),
the boot loader binary (2023 87 KB vs 2.0.x 1.05 MB — the older one only reaches the login menu,
but neither reaches the world), the client version (updated 1.9.0 → 2.0.3, no change), the wine
registry (diffed against the known-good baseline — identical but for path renames), the launch
environment, and the renderer.

## Fix

`use_interface_bypass = 1`. The app now:

* **checks** it in Preflight whenever the selected boot profile loads Sandbox
  (`Sandbox.isEnabled`), and shows a blocking check explaining the exact symptom;
* **repairs** it as part of Repair; and
* **repairs it automatically at launch**, because no user should ever meet this failure —
  it looks like a broken install and is a one-byte config difference.

See `app/Sources/HorizonXILauncher/Sandbox.swift`.

## Two other things the wrapper move broke

Both found while isolating the above, both now fixed in code:

1. **All 94 dylib symlinks in `SharedSupport/wine/lib` still pointed at the previous copy of the
   wrapper.** `cp -R`/`rsync` preserve symlink *text*, so a moved wrapper keeps loading the old
   one's libraries for as long as that disk is mounted — and breaks the day it is not. Worse,
   `libMoltenVK.dylib` silently resolved to the old wrapper's MoltenVK, which is a renderer
   change, not a missing file. `RendererSetup.relinkStrayDylibs` re-points anything that escapes
   the wrapper, and runs on every launch.

2. **`Contents/Frameworks/moltenvkcx/` was lost in the move.** DXVK needs that MoltenVK
   (1.2.10 / Vulkan 1.2.290); the stock one in the wrapper is 1.4.1, which rejects the pipelines
   DXVK builds — 45 × `VK_ERROR_FEATURE_NOT_PRESENT: Metal does not support disabling primitive
   restart` per launch, and nothing drawn. `linkMoltenVK` used to fail silently when the folder
   was absent; it now falls back to the stock one deliberately rather than leaving a stale link.
   The folder was recovered from the archived 2026-08-11 wrapper on the x10 drive.

## Gotcha worth its own line: DXVK's first frame takes about two minutes

With `dxvk.enableStateCache = True` and no cache yet on disk, the first launch after a config
change spends **~120 s** compiling pipelines before it presents anything. The window exists and
is completely black for that whole time. Every "DXVK renders nothing" observation in this
session was a screenshot taken at 50–70 s.

Do not judge it by a screenshot. Judge it by `DXVK_FPS_LOG`
(`C:\HorizonXI\logs\dxvkfps.csv`): a header-only file means no frames, rows mean it is drawing.
Verified working: **28–29 fps at 1920×1080, every FFXI setting at maximum, x87 sidecar not even
attached.**

The cache is only written on a *clean* exit. Killing the client (`kill -9`, or a harness that
pkills between runs) throws it away and buys the two-minute wait again next launch.
