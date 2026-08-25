# Mouse input on Wine — cursor, clicks, and draggable panels

Three separate problems that look like one. All three are handled by the `winecursor`
addon (`addons/winecursor/winecursor.lua`), each behind its own switch.

| # | Symptom | Cause | Fixed |
|---|---------|-------|-------|
| 1 | Cursor invisible in the game window | FFXI calls `ShowCursor(FALSE)` and draws its own sprite, which does not render under Wine/DXVK | 2026-08-17 |
| 2 | ImGui addon windows can't be hovered or clicked | Nothing feeds ImGui's `io` — Ashita takes mouse input from the game window's WNDPROC, and under Wine that window receives no `WM_MOUSE*` at all | 2026-08-23 |
| 3 | Panels can't be shift-dragged (`timers`, `tparty`, `tTimers`, `tCrossBar`, `thotbar`, `equipmon`, anything on `libs/primitives.lua` or `libs/fonts.lua`) | Same dead WNDPROC stream — but these addons don't read ImGui, so fixing (2) did nothing for them | 2026-08-24 |

## The thing that took longest to see: there are two input streams, not one

Ashita feeds addons through **two independent paths**, and an addon uses one or the other:

- **ImGui's `io`** — `imgui.GetIO()`, `io.MousePos`, `io.MouseDown`, `io.KeyShift`. Every
  addon that draws an ImGui window hit-tests through this.
- **`ashita.events.register('mouse'|'key', ...)`** — raised from the game window's WNDPROC,
  carrying the raw `WM_` message id, `wparam`/`lparam` and client coordinates. Every addon
  that draws with **primitives or GDI fonts** hit-tests through this, because there is no
  ImGui window to hover. `addons/libs/primitives.lua:195` and `addons/libs/fonts.lua:369`
  register it on behalf of everything built on them.

Both start from the same dead source under Wine — the window gets no mouse messages — so
both have to be fed, and feeding one does nothing for the other. That is exactly why
"clicking works now" (2026-08-23) and "I still can't shift-click to move panels"
(2026-08-24) were both true at the same time.

The shift-drag contract is worth spelling out, from `addons/timers/timers.lua:238`:

- `512` (`WM_MOUSEMOVE`) while dragging → move the panel by the delta
- `513` (`WM_LBUTTONDOWN`) → start dragging, **but only if `gShiftDown`**
- `514` (`WM_LBUTTONUP`) → stop dragging and save
- `522` (`WM_MOUSEWHEEL`) → panel opacity
- `gShiftDown` comes from the **`key`** event: `wparam == 0x10` and lparam bit 31 clear

So a synthetic stream has to carry the shift state too, or every press is ignored and the
panel never moves — which is the bug as reported.

## How it is fed now

`winecursor` runs on `d3d_present` and, per frame:

1. **Cursor.** `SetCursor(LoadCursorA(nil, IDC_ARROW))`, then drive `ShowCursor` until the
   internal show-count sits at +1. The count is a counter, not a flag; one step of headroom
   absorbs FFXI's own per-frame `ShowCursor(FALSE)`, which is what the blinking was.
2. **ImGui.** `io:AddMousePosEvent` / `io:AddMouseButtonEvent` / `io:AddKeyEvent` — ImGui's
   own event queue. Nothing is posted to any window, so the game's mouse-look maths is
   never touched.
3. **WNDPROC.** `PostMessageA` to `FFXiClass`: `WM_MOUSEMOVE`, `WM_*BUTTONDOWN/UP`, and a
   `VK_SHIFT` `WM_KEYDOWN`/`WM_KEYUP` pair — but only while the real key stream looks dead
   (one genuine non-shift `key` event and the synthetic shift switches itself off for good).

### Why this does not spin the camera

The 2026-08-21 attempt posted `WM_MOUSEMOVE` to `FFXiClass` and made the game unplayable:
Cmd-Tab back in and the camera spun, because FFXI reads mouse-look as a delta from a
captured position and a synthetic move on focus return hands it a screen-sized delta.

Ashita's window hook raises the addon event **first** and only then passes the message on to
the game's own window procedure — unless it is marked blocked. So every synthetic message is
blocked on arrival by `winecursor`'s own `mouse` handler: addons see it, FFXI never does, and
the delta is never computed. `/winecursor block none` is the one setting that can bring the
spin back; it exists for diagnosis.

Two blocking mechanisms are implemented because they are evaluated at different layers:

- `block event` (default) — set `e.blocked = true` on each event, the mechanism the addons
  themselves use (`timers.lua:281` blocks its own drags the same way).
- `block input` — hold `AshitaCore:GetInputManager():GetMouse():SetBlockInput(true)`, the
  core-level flag behind `mouse.blockinput` in the boot `.ini`.
- `block both` — belt and braces.

### Commands

    /winecursor                         status: switches, counters, both coordinate spaces
    /winecursor clicks   on|off         the ImGui stream
    /winecursor wndproc  on|off         the synthetic WNDPROC stream
    /winecursor block    none|event|input|both
    /winecursor space    game|imgui|client   coordinate space the WNDPROC stream posts in

### What the consumers actually require

Inventoried across the whole addon tree, not just the ones loaded:

- **Message ids.** `libs/primitives.lua:92-104` and `libs/fonts.lua:75-87` map exactly 11 ids
  and silently drop the rest: `0x200` move, `0x201/0x202` left, `0x204/0x205` right,
  `0x207/0x208` middle, `0x20A` wheel, `0x20B/0x20C` xbutton, `0x20E` hwheel. The concrete
  consumers use a subset — `timers` 512/513/514/522, `equipmon` also 516/517 (right button),
  `crosshair` 512 alone.
- **Order.** A move must land *before* a button-down: `timers.lua:288-290` and
  `thotbar/display.lua:219-221` latch the drag origin from the down message, and
  `crosshair.lua:93-95` caches position from moves only.
- **The button-up is not optional.** `thotbar/callbacks.lua:102-119`,
  `tCrossBar/callbacks.lua:136-155` and `tTimers/timergroup.lua:96-99` latch a
  `mouseDown`/`MouseBlocked` flag on a blocked 513 that only a 514 clears, and
  `tTimers/timergroup.lua:60-63` ends its drag — and calls `settings.save()` — only on a 514,
  so a panel moved without one silently reverts on reload. `winecursor` therefore always
  delivers the up, even off-window and even on focus loss.
- **Two different sources of shift.** `timers` and `equipmon` take it from the `key` event's
  lparam bit 31 (`timers.lua:226-233`). `tTimers` instead polls `GetKeyState` through FFI at
  the moment the 513 arrives (`tTimers/timergroup.lua:26-33`, shift and ctrl) — and a
  `PostMessage`d `WM_KEYDOWN` does **not** update `GetKeyState`, so that one depends on Wine's
  own key-state tracking the physical key. `thotbar` polls `GetKeyState` for ctrl only
  (`thotbar/display.lua:6-10`) and `tCrossBar` does not poll it at all.
- **Event fields are `wparam`/`lparam`/`delta`/`blocked`** — confirmed from the shipped
  binary (`strings plugins/Addons.dll`: `eventargs_inputmanager_handlemouse_t` … `delta`,
  `eventargs_inputmanager_handlekeyboard_t` … `wparam`, `lparam`). There is no `e.key` or
  `e.down` on the `key` event; the retired `mousediag` logged those and printed `nil` for
  every real keypress, which is worth knowing before trusting any old measurement from it.

### Coordinates

Ashita passes lparam through undecorated — `mousecallback_f` is
`BOOL(uint32_t, WPARAM, LPARAM, bool)` (`plugins/sdk/Ashita.h:435`) and nothing in the SDK
rescales — so `e.x/e.y` are exactly a `LOWORD/HIWORD` decode of whatever is posted. That
makes the packed space the whole ballgame, and three spaces are in play:

- **Wine client pixels** — what `ScreenToClient` answers in (e.g. 1564x848).
- **The d3d8 back buffer** — what primitives are positioned in, so what `timers`, `equipmon`
  and `balloon` hit-test against.
- **ImGui `DisplaySize`** — what `crosshair` draws in, and 640x480 at the title screen.

The last two are the same surface, so one packing serves both. `winecursor` scales client
pixels into back-buffer space, reading it from `d3d8.get_device():GetViewport()` — the same
call `crosshair.lua:71` uses — and falling back to `io.DisplaySize` when the device does not
answer. On Windows the client rect and the back buffer are the same size, which is why
nothing upstream ever converts. `/winecursor space imgui` forces the DisplaySize path and
`space client` posts raw client pixels, if a panel ever turns out to hit-test elsewhere.

### Not synthesised

`WM_MOUSEWHEEL`. There is no polling API for wheel movement the way `GetAsyncKeyState`
polls buttons, so the wheel-driven bits (panel opacity on `timers`) stay dead until real
messages arrive. If it is ever added, note the trap: Win32 puts **screen** coordinates in
the wheel message's lparam, unlike every other mouse message, while `equipmon` and `timers`
hit-test the wheel with the same `e.x/e.y` they use for clicks — so it has to be packed with
client-derived coordinates like the rest, not with true screen ones.

## Verification

`addons/winecursor/harness.lua` runs the addon against a stubbed Ashita/Win32 under plain
`luajit` — no game client, no wine:

    luajit addons/winecursor/harness.lua addons/winecursor/winecursor.lua

It asserts the posted message stream frame by frame: move scaling and rounding, no repeat
move when the pointer is still, the synthetic `VK_SHIFT` down/up, `MK_LBUTTON|MK_SHIFT` in
the wparam of a press, the drag, the release, a Cmd-Tab mid-drag still delivering the
button-up, `e.blocked` being set, the synthetic shift switching itself off when a real key
arrives, and every command path. All pass as of 2026-08-24.

That is a logic harness, not a substitute for the game: what it cannot prove is Ashita's
own dispatch behaviour — whether an event one addon marks blocked still reaches the addons
registered after it. If shift-drag still does nothing after a reload, that is the thing to
suspect, and `/winecursor block input` is the switch that tests it.

## NOT the cause (ruled out by test — do not revisit)

- **RetinaMode.** Client rect and ImGui DisplaySize agree, and Wine screen coords are
  exactly 2x macOS points with a clean conversion. An earlier `RetinaMode=n` "fix" was a
  pure regression and was reverted.
- **`mouse.unhook=0`** in the boot profile — no change.
- **`io.MouseDown[0] = x` from Lua** — Ashita's ImGui binding is read-only for that field
  (`MouseDown assignable: false`). The `io:Add*Event` queue is the way in.
- **`HardwareMouse.dll`** — actively harmful. With `/load HardwareMouse` in
  `scripts/default.txt` the client dies during startup, before addons load. Keep it
  commented out. (`winefix.dll` is a different plugin and is fine.)

## Shell -> game command channel

Restored in `winecursor` 1.1, having been retired with `mousediag`. There is no other way
into a running client — Ashita has no IPC, and the keyboard path is the one this addon exists
to work around. Every 30th frame it drains `addons/winecursor/cmd.txt`, queues each line as a
game command, and empties the file:

    P="/Volumes/x10/Video Games/Mac/FFXI/siku.app/Contents/SharedSupport/prefix10/drive_c/HorizonXI"
    printf '/winecursor\n' > "$P/addons/winecursor/cmd.txt"

A line beginning `LUA ` is compiled and run instead, with its result appended to `cmd.out` —
which is how state gets measured from outside:

    printf 'LUA return tostring(imgui.GetIO().DisplaySize.x)\n' > "$P/addons/winecursor/cmd.txt"
    cat "$P/addons/winecursor/cmd.out"

The one thing it cannot do is load itself: a change to `winecursor.lua` still needs
`/addon reload winecursor`, and until 1.1 is loaded once there is no channel to ask through.

## Unclosable Wine windows

Cause: Wine's `winedbg --auto` crash dialog. Editing AeDebug in `system.reg` does NOT
stick — Wine rewrites `system.reg` on shutdown from its in-memory copy. Fix is
process-level:

- `scripts/quit-wine.sh` force-closes every Wine window/process (`wineserver -k` then a
  `pkill -9` sweep). Verified to 0 remaining.
- Launch alongside a reaper loop that `pkill`s `winedbg --auto` every 2s, so a crash can
  never leave a stuck window:

      while pgrep -qf "Ashita-cli.exe|horizon-loader.exe"; do
        pkill -f "winedbg --auto"; sleep 2
      done

## Gotchas

- Boot to first ImGui frame is ~60-80s (DXVK first frame). Don't judge by screenshot before
  then.
- Launching via `nohup` inside a tool call that later times out kills the game.
- The client needs a real keypress at the PlayOnline "Accept" screen, so fully scripted runs
  never reach the world and in-world addons aren't loaded there.
- `winecursor` is **not installed by the launcher** — it exists only in the game directory it
  was written into, and in this repo. A fresh install does not get it.

## Security

The HorizonXI password is plaintext in the boot `.ini` and appears in `ps` output. Worth
changing how it's passed.
