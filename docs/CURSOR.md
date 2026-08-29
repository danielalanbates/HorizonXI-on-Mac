# Keeping the mouse cursor visible under Wine — as a dylib, not an addon

## The problem
FFXI calls `ShowCursor(FALSE)` every frame and draws its own cursor sprite. That sprite does not
render under Wine/DXVK, so the pointer is invisible inside the game window — on every server.

## The two ways to fix it
1. **The `winecursor` Ashita addon** (`addons/winecursor/winecursor.lua`) holds the Win32
   show-count at +1 so the Windows cursor stays visible. It works, but it is an **Ashita addon**,
   and HorizonXI (and most private servers) run an allowlist — an unlisted addon is bannable
   (`docs/ADDON-POLICY.md`). `winecursor` is on nobody's list, so it is commented out of the
   HorizonXI boot profile and the cursor stays invisible there.

2. **`winecursor.dylib`** (`cursor/winecursor.m`) — this. A DYLD-inserted shim, exactly like
   `audiofollow.dylib`, that fixes the cursor **below** the addon layer, so no server allowlist
   governs it.

## How the dylib works
Wine's Mac driver, `winemac.drv`, performs the hide with AppKit's **`+[NSCursor hide]`** — not
`CGDisplayHideCursor`. Evidence: `nm -u winemac.so` shows the `hide`/`unhide` NSCursor selectors
and **no** `CGDisplay{Show,Hide}Cursor`. So a C-function interpose cannot catch it; the dylib
instead **swizzles `+[NSCursor hide]`/`+[NSCursor unhide]` to no-ops** in its constructor. The
cursor's hide-count then never leaves 0 and the system arrow stays visible for the life of the
process. This is the native-layer equivalent of the addon holding the Win32 count at +1.

It is inserted by the launcher (`WineCursor.swift` → `Settings.swift`, appended to
`DYLD_INSERT_LIBRARIES` next to `audiofollow.dylib`), always on, guarded by the same
missing/wrong-arch check (`MachOSlice.hasX86`) so a bad file can never abort a launch.

## What is verified, and what is not
- **Verified natively:** the swizzle replaces `+[NSCursor hide]`'s implementation when the dylib
  is inserted — `scripts/tests/winecursor-test.m` (and an IMP-address diff) confirm the method
  pointer changes from AppKit's to the dylib's no-op. The dylib builds universal (arm64 + x86_64).
- **Not yet verified in-game:** that neutralising the hide makes the FFXI arrow visible with no
  second cursor. That needs a rebuilt `/Applications/FFXI-on-Mac.app` and one launch on the
  **local** LandSandBoat world (never test on a hosted server). The evidence chain — winemac uses
  `[NSCursor hide]` → the dylib neutralises it → the OS cursor is never hidden — makes this the
  expected result, but it is unconfirmed until that run.

## Scope
Only cursor **visibility**. Clicking/dragging in-game addon windows genuinely needs Ashita's
ImGui/WNDPROC path (the addon's parts 2 & 3) and cannot move below the addon layer.
