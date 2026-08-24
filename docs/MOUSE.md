# Mouse input on Wine — cursor invisible, addon windows unclickable

Measured 2026-08-17 with the `mousediag` addon (`addons/mousediag/mousediag.lua`).

## Symptoms
- Mouse cursor invisible inside the game window.
- Ashita/ImGui addon windows (Links, HXUI, …) can't be hovered or clicked.

## Root cause
Ashita received **zero** mouse messages. `mouse events=0`, `MouseDown0=nil`,
`hovered=false` — confirmed with the pointer driven across the focused client area by
CGEvent *and* a real HID left-click posted at the window centre. Meanwhile
`io.MousePos` tracked perfectly, because Ashita polls `GetCursorPos` for position.
Position worked; the button/hover *message* stream was dead.

Separately, FFXI calls `ShowCursor(FALSE)` and draws its own cursor sprite, which does
not render under Wine/DXVK — hence no visible cursor.

## NOT the cause
**RetinaMode.** Client rect and ImGui DisplaySize are both exactly 1920x1080,
`io.MousePos` matches the Win32 client cursor position exactly, and Wine screen coords
are exactly 2x macOS points with a clean conversion. An earlier `RetinaMode=n` "fix"
was a pure regression and has been reverted. Do not revisit it.

## Also ruled out by test
- `mouse.unhook=0` in `config/boot/horizonxi.ini` — no change.
- `io.MouseDown[0] = x` from Lua — Ashita's ImGui binding is read-only
  (`MouseDown assignable: false`).
- **`HardwareMouse.dll` — actively harmful.** With `/load HardwareMouse` in
  `scripts/default.txt` the client dies during startup, before addons load. Keep it
  commented out.

## 2026-08-21: injection is OFF again, and why

Restoring the synthetic message stream (step 2 below) made the game unplayable in a way the
original removal note never described: **Cmd-Tab back into the game and the camera spins**, and
clicking does not stop it. FFXI reads mouse-look as a delta from a captured position; a synthetic
WM_MOUSEMOVE posted on the frame focus returns hands it a delta the size of the screen, which it
keeps applying. Releasing the buttons on focus loss does not help — the spin is a *move*, not a
held button.

So injection is behind `FFXI_MOUSE_INJECT=1` and off by default. The cursor fix (step 1) is
unrelated, stays on, and is what stopped the blinking.

**Clicking addon windows is therefore still unsolved**, and the two obvious paths are both known
bad: this injection spins the camera, and `HardwareMouse.dll` kills the client at startup. What
has *not* been tried is fixing the message stream at its source — Ashita 4.3's own mouse hook
(`mouse.unhook` in the boot profile was tested and did nothing, but the hook itself was never
read) or a DirectInput-side interposer. That is where the next attempt should go, rather than at
another round of posting WM_ messages into a game that is doing its own mouse-look maths.

## The fix (verified working)
In `mousediag.lua`, per frame:

1. `SetCursor(LoadCursorA(nil, IDC_ARROW))` then drive `ShowCursor(1)` until the
   internal show-count is >= 0. Log line `ShowCursor count -> 1` means visible.
   **This is what made the cursor appear.**
2. (**Off by default — see the 2026-08-21 note above.**) Synthesise the missing message stream from `GetCursorPos` + `GetAsyncKeyState` and
   `PostMessageA` it to the `FFXiClass` window (WM_MOUSEMOVE 0x200,
   WM_LBUTTONDOWN/UP 0x201/0x202, WM_RBUTTONDOWN/UP 0x204/0x205). After this,
   `mousediag` reports `msgs=136` and climbing where it was pinned at 0.

Known rough edge: once messages flow, `io.MousePos` can read as -FLT_MAX (ImGui's
"no mouse" sentinel) and `client` coords stop differing from `screen` coords, which
suggests the `ScreenToClient` target window handle is wrong in that path. Clicking
should be re-verified against a real in-world addon window before calling it done.

## Shell -> game command channel
`mousediag` polls `addons/mousediag/cmd.txt` every frame and queues each line via
`AshitaCore:GetChatManager():QueueCommand(-1, line)`. Closes any addon window with no
mouse at all:

    printf '/addon unload links\n' > "$PREFIX/drive_c/HorizonXI/addons/mousediag/cmd.txt"

Verified by before/after screenshot on the Links box.

## Unclosable Wine windows
Cause: Wine's `winedbg --auto` crash dialog. Editing AeDebug in `system.reg` does NOT
stick — Wine rewrites `system.reg` on shutdown from its in-memory copy. Fix is
process-level:

- `scripts/quit-wine.sh` force-closes every Wine window/process
  (`wineserver -k` then a `pkill -9` sweep). Verified to 0 remaining.
- Launch alongside a reaper loop that `pkill`s `winedbg --auto` every 2s, so a crash
  can never leave a stuck window:

      while pgrep -qf "Ashita-cli.exe|horizon-loader.exe"; do
        pkill -f "winedbg --auto"; sleep 2
      done

## Gotchas
- Boot to first ImGui frame is ~60-80s (DXVK first frame). Don't judge by screenshot
  before then.
- Launching via `nohup` inside a tool call that later times out kills the game.
- The client needs a real keypress at the PlayOnline "Accept" screen, so fully scripted
  runs never reach the world and in-world addons aren't loaded there.

## Security
The HorizonXI password is plaintext in `config/boot/horizonxi.ini` and appears in `ps`
output. Worth changing how it's passed.

## 2026-08-22: the cursor went missing again, and why

Daniel pressed Update and Restart and came back with no cursor at all. Nothing regressed in
the code — **the launcher's own Apply removed the fix.**

The chain: the cursor fix lives in `mousediag`; Apply rewrites everything between
`# --HORIZON_ADDONS_START/STOP--` in `scripts/default.txt` from the addon screen's checkboxes;
that screen filters by the server's published allowlist; `mousediag` is on no server's list
because it is ours. So Apply wrote a managed block without it, and the ShowCursor loop stopped
running.

Two changes, so it cannot happen again:

* **`addons/winecursor/`** — the cursor fix on its own, with none of `mousediag`'s
  diagnostics, injection or `cmd.txt` channel. That separation matters for the allowlist
  argument: this addon only makes the pointer visible.
* **`AddonPolicy.infrastructure`** now contains `winecursor`, next to `winefix`, so an
  allowlist can never filter it out, and the load line goes **outside** the managed markers in
  `default.txt` so an Apply cannot rewrite it away.

## SOLVED 2026-08-23: clicking works, and no message is posted anywhere

The previous section's experiment was run, and it did nothing — as its own last paragraph
predicted. The fix is a different mechanism entirely, and it is now on by default.

**Ashita's ImGui build exposes ImGui's own input event API.** `imgui.GetIO()` answers with a
userdata carrying `AddMousePosEvent`, `AddMouseButtonEvent`, `AddMouseWheelEvent` and
`AddFocusEvent` (probed in game, all present, all callable). Feeding the pointer through those
hands it straight to ImGui and **posts nothing to the game at all** — so the camera-spin
failure mode of 2026-08-21 is not merely avoided, it is unreachable: FFXI's message queue is
never touched.

Three measurements were needed, and each had been a dead end on its own:

1. **Nothing feeds `io.MousePos` any more.** The 2026-08-17 note that it "tracked perfectly"
   does not hold on this build — it sat frozen at whatever a probe had last written to it. So
   position has to be fed too. Buttons alone can never work, because ImGui has no idea where
   the pointer is and `WantCaptureMouse` is meaningless.
2. **ImGui lays out in a 640x480 space while the wine client rect is 1564x848.** Client
   coordinates must be scaled by `DisplaySize / clientRect` or every hit test misses by a
   factor of two and a half. This is also why addon windows here look enormous.
3. **`GetAsyncKeyState` reports the mouse button only while `FFXiClass` is genuinely the
   foreground window.** A stray wine popup — class `#32769` — was holding focus, and from the
   inside that is indistinguishable from "wine never sees the mouse". Activating the game
   window through the macOS app, not just clicking in it, made the button read `-32768`
   immediately. A good part of the original "zero mouse messages" finding was this.

### What `winecursor` does now, per frame

```
io:AddMousePosEvent(clientX * DisplaySize.x / clientRect.right,
                    clientY * DisplaySize.y / clientRect.bottom)   -- or -FLT_MAX when outside
io:AddMouseButtonEvent(0|1|2, GetAsyncKeyState(VK_L|R|MBUTTON) & 0x8000 ~= 0)
```

Buttons are forced released whenever `FFXiClass` is not foreground, so nothing can stick down
across a Cmd-Tab. `PostMessageA` is gone from the click path.

### Verified

Against the local LandSandBoat world, with the Vanagear panel as the target: hovering reported
`IsAnyItemHovered() == true` over a button, clicking one ran its handler (a set was created on
disk), and clicking a row in a list selected it. Screenshots in the Vanagear repo's
`docs/img/`.

`/winecursor clicks off` turns it off; `/winecursor` reports the injected count and what ImGui
currently thinks.

### Still open

- Mouse **wheel** is not fed. `AddMouseWheelEvent` exists; nothing calls it yet.
- Whether the game *also* acts on a click that ImGui consumed. Nothing suppresses the real
  click, so a click through an addon window probably still reaches the world underneath.
  `io.WantCaptureMouse` is the signal that would drive a suppression, if one turns out to be
  wanted.
- The old `WM_`-posting code is deleted, not disabled. If it is ever wanted back, it is in the
  git history and in the section above.
