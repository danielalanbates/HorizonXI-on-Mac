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

## The fix (verified working)
In `mousediag.lua`, per frame:

1. `SetCursor(LoadCursorA(nil, IDC_ARROW))` then drive `ShowCursor(1)` until the
   internal show-count is >= 0. Log line `ShowCursor count -> 1` means visible.
   **This is what made the cursor appear.**
2. Synthesise the missing message stream from `GetCursorPos` + `GetAsyncKeyState` and
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
