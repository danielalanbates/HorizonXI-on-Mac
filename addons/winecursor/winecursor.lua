-- HXI_MAC_JIT_GUARD: added by the FFXI-on-Mac launcher. Ashita 4.3's LuaJIT trace patcher faults inside
-- Addons.dll under Wine/Rosetta (EXCEPTION_ACCESS_VIOLATION, lj_mcode_patch); interpreted Lua
-- does not. Delete these lines to opt this addon out.
if jit and jit.off then jit.off() end
--[[
* winecursor -- make the mouse work again under wine.
*
* Three separate problems, three separate switches.
*
* 1. THE CURSOR IS INVISIBLE.  FFXI calls ShowCursor(FALSE) every frame and draws its own
*    cursor sprite, which does not render under wine/DXVK.  Holding Win32's show-count at
*    +1 puts the real arrow back.  This is always on; it is the reason this addon exists,
*    and it is a compatibility shim, not a gameplay feature.
*
* 2. IMGUI ADDON WINDOWS CANNOT BE CLICKED.  Solved 2026-08-23, and not by posting messages
*    at all.  Ashita's ImGui build exposes ImGui's own input event API -- io:AddMousePosEvent
*    and io:AddMouseButtonEvent -- so the pointer can be handed straight to ImGui without
*    the game's message queue ever being touched.  That removes the camera spin at its
*    source: the 2026-08-21 attempt spun the camera because it posted WM_MOUSEMOVE to
*    FFXiClass, and this posts nothing anywhere.
*
*    Three measurements made it work, each of which had been a dead end on its own:
*
*      a. NOTHING feeds io.MousePos.  The 2026-08-17 note that it "tracked perfectly" no
*         longer holds on this build -- it sat frozen at whatever a probe last wrote.  So
*         position has to be fed too, not just buttons.
*      b. ImGui's DisplaySize is 640x480 while the wine client rect is 1564x848.  Client
*         coordinates must be SCALED into ImGui space or every hit test misses by a factor
*         of two and a half.
*      c. GetAsyncKeyState reports the mouse button only while FFXiClass is genuinely the
*         foreground window.  A stray wine popup (class #32769) holding focus reads as a
*         dead mouse, which is what "zero mouse messages" looked like from the inside.
*
*    On by default.  `/winecursor clicks off` disables it.
*
* 3. PANELS STILL CANNOT BE SHIFT-DRAGGED.  Reported 2026-08-24, and it is a different
*    stream, which is why (2) did not fix it.  The panels people actually want to move --
*    timers, tparty, tTimers, tCrossBar, thotbar, equipmon, anything built on
*    addons/libs/primitives.lua or libs/fonts.lua -- do not use ImGui for input at all.
*    They register `ashita.events.register('mouse', ...)`, which Ashita raises from the
*    game window's WNDPROC, and gate the drag on a shift state they take from the matching
*    'key' event.  Under wine that window receives no WM_MOUSE* whatsoever, so the callback
*    never runs and the panel is immovable no matter what ImGui believes.
*
*    So this synthesises that message stream: WM_MOUSEMOVE / WM_*BUTTONDOWN / WM_*BUTTONUP
*    posted to FFXiClass, plus a VK_SHIFT WM_KEYDOWN/WM_KEYUP pair when -- and only when --
*    the real key stream looks dead too.
*
*    The coordinates are the other half of it.  Ashita passes lparam through undecorated, so
*    e.x/e.y are exactly what is packed here, and the consumers hit-test against primitive
*    positions -- which live in the back buffer the game draws into, not in the wine client
*    rect.  On Windows those two are the same size and the question never comes up; under
*    wine/DXVK they are not, so client pixels are scaled into back-buffer space (the d3d8
*    viewport, falling back to ImGui's DisplaySize) before packing.
*
*    The 2026-08-21 camera spin is handled, and this is the part to understand before
*    changing anything here.  Ashita's window hook raises the addon event FIRST and only
*    then hands the message to the game's own WNDPROC, unless something marks it blocked.
*    So every synthetic message is blocked on arrival: addons see it, FFXI never does, and
*    the mouse-look delta that spun the camera is never computed.  Blocking is what makes
*    this safe, and `/winecursor block none` is the one setting that can bring the spin
*    back -- it exists for diagnosis, not for use.
*
*    `/winecursor wndproc off` disables the whole synthetic stream.
*
* Copyright (c) 2026 Bates LLC.  All rights reserved.  https://batesai.org
--]]

addon.name    = 'winecursor';
addon.author  = 'Bates LLC';
addon.version = '1.1';
addon.desc    = 'Restores the mouse cursor under wine, and makes addon windows clickable and draggable.';

require 'common';

if (jit ~= nil and jit.off ~= nil) then jit.off(true, true); end

local chat  = require 'chat';
local imgui = require 'imgui';
local ffi   = require 'ffi';
local d3d8  = require 'd3d8';

ffi.cdef[[
typedef struct { long x; long y; } POINT;
typedef struct { long left; long top; long right; long bottom; } RECT;
typedef void* HWND;
int   GetCursorPos(POINT* p);
int   ScreenToClient(HWND h, POINT* p);
int   GetClientRect(HWND h, RECT* r);
HWND  FindWindowA(const char* cls, const char* title);
HWND  GetForegroundWindow(void);
short GetAsyncKeyState(int vk);
int   ShowCursor(int b);
void* LoadCursorA(void* hi, const char* name);
void* SetCursor(void* c);
long  PostMessageA(HWND h, unsigned int msg, unsigned int wp, long lp);
]]

-- The show-count is a counter, not a flag: the cursor draws while it is >= 0.  FFXI's own
-- per-frame ShowCursor(FALSE) takes it to -1 if it is parked at 0, which is exactly the
-- blink that was reported before.  One step of headroom absorbs that decrement.
local CURSOR_TARGET = 1

local VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_SHIFT = 0x01, 0x02, 0x04, 0x10

-- ImGui's "pointer is nowhere" sentinel.
local OUTSIDE = -3.4028235e38

-- ImGui key ids for the modifier.  Feeding both the physical key and the mod bit is what
-- sets io.KeyShift, which the ImGui-side addons (fancychat, FFXIFriendList) gate on.
local ImGuiKey_LeftShift = 528;
local ImGuiMod_Shift     = bit.lshift(1, 13);

local WM_MOUSEMOVE   = 0x0200;
local WM_KEYDOWN     = 0x0100;
local WM_KEYUP       = 0x0101;

local MK_LBUTTON, MK_RBUTTON, MK_MBUTTON, MK_SHIFT, MK_CONTROL = 0x0001, 0x0002, 0x0010, 0x0004, 0x0008;

-- Scan code 0x2A is left shift; the lparam layout is the ordinary one Win32 documents,
-- because the consumers read it: timers.lua decides shift-is-down from bit 31 (the
-- transition-state bit, set only on key-up).
local SHIFT_LPARAM_DOWN = bit.tobit(0x002A0001);
local SHIFT_LPARAM_UP   = bit.tobit(0xC02A0001);

local BUTTONS = {
    { vk = VK_LBUTTON, index = 0, mk = MK_LBUTTON, down = 0x0201, up = 0x0202 },
    { vk = VK_RBUTTON, index = 1, mk = MK_RBUTTON, down = 0x0204, up = 0x0205 },
    { vk = VK_MBUTTON, index = 2, mk = MK_MBUTTON, down = 0x0207, up = 0x0208 },
};

local st = {
    -- Switches.
    clicks  = true,     -- (2) feed ImGui's own event queue
    wndproc = true,     -- (3) synthesise the WNDPROC message stream
    block   = 'event',  -- how the game is kept from seeing (3): event | input | both | none
    space   = 'game',   -- coordinate space posted with (3): game | imgui | client

    -- State.
    arrow    = nil,
    hwnd     = nil,
    down     = { [VK_LBUTTON] = false, [VK_RBUTTON] = false, [VK_MBUTTON] = false },
    shift    = false,
    last_x   = nil,
    last_y   = nil,
    blocking = false,   -- whether SetBlockInput is currently held on
    frames   = 0,       -- present count, for the command-file poll

    -- Counters, so `/winecursor` can answer "is anything actually happening".
    injected  = 0,      -- ImGui events fed
    posted    = 0,      -- WM_ messages posted
    seen      = 0,      -- 'mouse' events Ashita raised back to us
    keys_seen = 0,      -- real (non-shift) 'key' events -- proof the key stream is alive
};

local function window()
    if (st.hwnd == nil) then st.hwnd = ffi.C.FindWindowA('FFXiClass', nil); end
    return st.hwnd;
end

--[[
* Shell -> game command channel.  There is no other way into a running client: Ashita has no
* IPC, and the keyboard path is the one this addon exists to work around.  Retired with
* mousediag, restored here, because without it every change to this file needs someone sitting
* at the keyboard to type `/addon reload winecursor`.
*
* Each line of addons/winecursor/cmd.txt is queued as a game command and the file is emptied.
* A line beginning `LUA ` is compiled and run instead, and its result appended to cmd.out --
* which is how anything can be measured from outside the client.
--]]
local CMD_POLL_FRAMES = 30;
local cmd = nil;

local function cmd_paths()
    if (cmd == nil) then
        local base = AshitaCore:GetInstallPath() .. '\\addons\\winecursor\\';
        cmd = { inp = base .. 'cmd.txt', out = base .. 'cmd.out' };
    end
    return cmd;
end

local function cmd_write(line)
    local f = io.open(cmd_paths().out, 'a');
    if (f == nil) then return; end
    f:write(tostring(line) .. '\n');
    f:close();
end

local function pump_commands()
    local paths = cmd_paths();
    local f = io.open(paths.inp, 'r');
    if (f == nil) then return; end
    local body = f:read('*a');
    f:close();
    if (body == nil or body == '') then return; end

    -- Emptied before anything runs, so a command that errors cannot loop forever.
    local w = io.open(paths.inp, 'w');
    if (w ~= nil) then w:close(); end

    for line in body:gmatch('[^\r\n]+') do
        if (line ~= '') then
            if (line:sub(1, 4) == 'LUA ') then
                local chunk, err = loadstring(line:sub(5));
                if (chunk == nil) then
                    cmd_write('compile error: ' .. tostring(err));
                else
                    local ok, res = pcall(chunk);
                    cmd_write(('%s %s'):format(ok and 'ok' or 'error', tostring(res)));
                end
            else
                AshitaCore:GetChatManager():QueueCommand(-1, line);
                cmd_write('queued: ' .. line);
            end
        end
    end
end

--- Cursor position in client pixels plus the client size, or nil when it is off the window.
local function cursor_client()
    local h = window();
    if (h == nil) then return nil; end
    local p = ffi.new('POINT');
    if (ffi.C.GetCursorPos(p) == 0) then return nil; end
    if (ffi.C.ScreenToClient(h, p) == 0) then return nil; end

    local r = ffi.new('RECT');
    if (ffi.C.GetClientRect(h, r) == 0 or r.right == 0 or r.bottom == 0) then return nil; end
    if (p.x < 0 or p.y < 0 or p.x > r.right or p.y > r.bottom) then return nil; end

    return p.x, p.y, r.right, r.bottom;
end

--- Cursor position in ImGui's coordinate space, or nil when it is not over the window.
--- The scale step is the one that is easy to miss: ImGui is laid out in DisplaySize units
--- (640x480 at the title screen) while ScreenToClient answers in wine client pixels.
--- Primitives are drawn into the same backbuffer ImGui measures, so the synthetic WNDPROC
--- stream is scaled the same way -- on Windows the two spaces are identical and nobody ever
--- had to think about it.
local function imgui_position(io)
    local x, y, w, h = cursor_client();
    if (x == nil) then return nil; end
    return x * (io.DisplaySize.x / w), y * (io.DisplaySize.y / h);
end

--- The back buffer the game is actually drawing into, which is the space primitives are
--- positioned in and therefore the space the WNDPROC consumers hit-test in.  Ashita passes
--- lparam through undecorated -- e.x/e.y are a raw LOWORD/HIWORD decode of what is posted --
--- so this is the space to pack, and on Windows it happens to equal the client rect, which
--- is why nobody upstream ever had to convert.
local function backbuffer()
    local ok, w, h = pcall(function ()
        local res, vp = d3d8.get_device():GetViewport();
        if (res ~= 0) then return nil, nil; end
        return vp.Width, vp.Height;
    end);
    if (ok and w ~= nil and w > 0 and h > 0) then return w, h; end
    return nil, nil;
end

--- Win32 lparam packing for a mouse message: y in the high word, x in the low word.
local function make_lparam(x, y)
    local lx = bit.band(math.floor(x + 0.5), 0xFFFF);
    local ly = bit.band(math.floor(y + 0.5), 0xFFFF);
    return bit.bor(bit.lshift(ly, 16), lx);
end

--- The wparam every mouse message carries: which buttons and modifiers are held right now.
local function make_wparam()
    local w = 0;
    for _, b in ipairs(BUTTONS) do
        if (st.down[b.vk]) then w = bit.bor(w, b.mk); end
    end
    if (st.shift) then w = bit.bor(w, MK_SHIFT); end
    if (bit.band(ffi.C.GetAsyncKeyState(0x11), 0x8000) ~= 0) then w = bit.bor(w, MK_CONTROL); end
    return w;
end

local function post(msg, wparam, lparam)
    local h = window();
    if (h == nil) then return; end
    ffi.C.PostMessageA(h, msg, wparam, lparam);
    st.posted = st.posted + 1;
end

--- Hold or release Ashita's core-level mouse block, which is one of the two ways the
--- synthetic stream is kept away from the game.
local function set_block_input(on)
    if (st.blocking == on) then return; end
    local ok = pcall(function ()
        AshitaCore:GetInputManager():GetMouse():SetBlockInput(on);
    end);
    if (ok) then st.blocking = on; end
end

ashita.events.register('d3d_present', 'winecursor_present', function ()
    -- 1. the cursor
    if (st.arrow == nil) then
        st.arrow = ffi.C.LoadCursorA(nil, ffi.cast('const char*', 32512));  -- IDC_ARROW
    end
    ffi.C.SetCursor(st.arrow);
    local n, guard = ffi.C.ShowCursor(1), 0;
    while (n > CURSOR_TARGET and guard < 16) do n = ffi.C.ShowCursor(0); guard = guard + 1; end
    while (n < CURSOR_TARGET and guard < 32) do n = ffi.C.ShowCursor(1); guard = guard + 1; end

    st.frames = st.frames + 1;
    if (st.frames % CMD_POLL_FRAMES == 0) then pcall(pump_commands); end

    if (not st.clicks and not st.wndproc) then
        set_block_input(false);
        return;
    end

    local io      = imgui.GetIO();
    local focused = (ffi.C.GetForegroundWindow() == window());

    -- GetAsyncKeyState only answers while FFXiClass really is foreground; treat anything
    -- else as released so nothing can stick down across a Cmd-Tab.
    local shift = focused and (bit.band(ffi.C.GetAsyncKeyState(VK_SHIFT), 0x8000) ~= 0);

    local cx, cy, cw, ch = cursor_client();
    local over = focused and (cx ~= nil);

    local ix, iy = nil, nil;
    if (over) then
        ix = cx * (io.DisplaySize.x / cw);
        iy = cy * (io.DisplaySize.y / ch);
    end

    -- Latch this frame's input once.  The previous frame is kept alongside it because both
    -- streams below fire on the CHANGE, while the wparam of a message has to describe the
    -- state the message itself creates -- a left-down carries MK_LBUTTON.
    local was_shift = st.shift;
    local was_down  = { };
    for _, button in ipairs(BUTTONS) do
        was_down[button.vk] = st.down[button.vk];
        st.down[button.vk]  = focused and (bit.band(ffi.C.GetAsyncKeyState(button.vk), 0x8000) ~= 0);
    end
    st.shift = shift;

    -- 2. the pointer, handed to ImGui through its own event queue
    if (st.clicks) then
        pcall(function () io:AddMousePosEvent(ix or OUTSIDE, iy or OUTSIDE); end);

        if (shift ~= was_shift) then
            pcall(function ()
                io:AddKeyEvent(ImGuiKey_LeftShift, shift);
                io:AddKeyEvent(ImGuiMod_Shift, shift);
            end);
        end

        for _, button in ipairs(BUTTONS) do
            local held = st.down[button.vk];
            if (held ~= was_down[button.vk]) then
                pcall(function () io:AddMouseButtonEvent(button.index, held); end);
                st.injected = st.injected + 1;
            end
        end
    end

    -- 3. the WNDPROC stream, for every addon that is not an ImGui window
    if (st.wndproc) then
        set_block_input(st.block == 'input' or st.block == 'both');

        -- The shift state the panels gate their drag on.  Only synthesised while the real
        -- key stream looks dead: if Ashita is already raising 'key' events for ordinary
        -- typing, posting our own would be a second, contradictory source of truth.
        if (shift ~= was_shift and st.keys_seen == 0) then
            post(shift and WM_KEYDOWN or WM_KEYUP, VK_SHIFT,
                 shift and SHIFT_LPARAM_DOWN or SHIFT_LPARAM_UP);
        end

        local px, py = ix, iy;
        if (over) then
            if (st.space == 'client') then
                px, py = cx, cy;
            elseif (st.space == 'game') then
                local bw, bh = backbuffer();
                if (bw ~= nil) then px, py = cx * (bw / cw), cy * (bh / ch); end
            end
        end

        if (over) then
            -- Move first, so a hit test on the button message sees the current position.
            if (px ~= st.last_x or py ~= st.last_y) then
                st.last_x, st.last_y = px, py;
                post(WM_MOUSEMOVE, make_wparam(), make_lparam(px, py));
            end
        else
            st.last_x, st.last_y = nil, nil;
        end

        for _, button in ipairs(BUTTONS) do
            local held = st.down[button.vk];
            if (held ~= was_down[button.vk]) then
                -- A press is only delivered where the pointer actually is; a release is
                -- always delivered, even off-window, or a drag sticks to the panel.
                if (over or not held) then
                    local x = st.last_x or px or 0;
                    local y = st.last_y or py or 0;
                    post(held and button.down or button.up, make_wparam(), make_lparam(x, y));
                end
            end
        end
    else
        set_block_input(false);
    end
end);

--[[
* Everything the synthetic stream posts comes straight back here, because Ashita raises the
* addon event from the same WNDPROC the message was posted to.  Marking it blocked is what
* stops it continuing on into FFXI's own window procedure -- which is the whole reason the
* 2026-08-21 attempt spun the camera and this one does not.
--]]
ashita.events.register('mouse', 'winecursor_mouse', function (e)
    st.seen = st.seen + 1;
    if (st.wndproc and (st.block == 'event' or st.block == 'both')) then
        e.blocked = true;
    end
end);

--[[
* Watching the real key stream.  A single ordinary key event proves WNDPROC keyboard input
* is alive, and the synthetic VK_SHIFT pair switches itself off for good.
--]]
ashita.events.register('key', 'winecursor_key', function (e)
    if (e.wparam ~= VK_SHIFT) then st.keys_seen = st.keys_seen + 1; end
end);

ashita.events.register('command', 'winecursor_command', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/winecursor', '/wc')) then return; end
    e.blocked = true;

    local sub = (#args > 1) and args[2]:lower() or 'status';
    local val = (#args > 2) and args[3]:lower() or nil;

    local function say(msg) print(chat.header(addon.name):append(chat.message(msg))); end

    if (sub == 'clicks' and val ~= nil) then
        st.clicks = val == 'on';
        say('ImGui input is now ' .. (st.clicks and 'on' or 'off'));
        return;
    end

    if (sub == 'wndproc' and val ~= nil) then
        st.wndproc = val == 'on';
        if (not st.wndproc) then set_block_input(false); end
        say('synthetic WNDPROC stream is now ' .. (st.wndproc and 'on' or 'off'));
        return;
    end

    if (sub == 'block' and val ~= nil) then
        if (val:any('none', 'event', 'input', 'both')) then
            st.block = val;
            say('blocking mode is now ' .. val ..
                (val == 'none' and ' -- the camera can spin in this mode' or ''));
        else
            say('block takes: none | event | input | both');
        end
        return;
    end

    if (sub == 'space' and val ~= nil) then
        if (val:any('game', 'imgui', 'client')) then
            st.space = val;
            say('posting coordinates in ' .. val .. ' space');
        else
            say('space takes: game | imgui | client');
        end
        return;
    end

    -- Status.  Report what the game thinks, not just what we did: the numbers below are
    -- what tell a working stream from a silent one.
    local cx, cy, cw, ch = cursor_client();
    local io_ok, dw, dh, want = pcall(function ()
        local io = imgui.GetIO();
        return io.DisplaySize.x, io.DisplaySize.y, io.WantCaptureMouse;
    end);
    say(('clicks %s, wndproc %s, block %s, space %s')
        :format(st.clicks and 'on' or 'off', st.wndproc and 'on' or 'off', st.block, st.space));
    say(('imgui events %d, WM posted %d, mouse events seen %d, real key events %d')
        :format(st.injected, st.posted, st.seen, st.keys_seen));
    local bw, bh = backbuffer();
    say(('cursor client %s, client rect %s, back buffer %s, ImGui display %s, WantCaptureMouse %s')
        :format(cx and ('%d,%d'):format(cx, cy) or 'off-window',
                cw and ('%dx%d'):format(cw, ch) or '?',
                bw and ('%dx%d'):format(bw, bh) or 'unavailable',
                io_ok and ('%dx%d'):format(dw, dh) or '?',
                tostring(io_ok and want)));
    say('/winecursor clicks|wndproc on|off  |  block none|event|input|both  |  space game|imgui|client');
end);

ashita.events.register('load', 'winecursor_load', function ()
    print(chat.header(addon.name):append(chat.message(
        'cursor restored; ImGui windows clickable and panels shift-draggable. /winecursor for status.')));
end);

ashita.events.register('unload', 'winecursor_unload', function ()
    set_block_input(false);
    -- Leave the count where the game expects it, or the next addon to look sees our +1.
    local guard = 0;
    while (ffi.C.ShowCursor(0) >= 0 and guard < 16) do guard = guard + 1; end
end);
