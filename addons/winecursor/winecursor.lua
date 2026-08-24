-- HXI_MAC_JIT_GUARD: added by the FFXI-on-Mac launcher. Ashita 4.3's LuaJIT trace patcher faults inside
-- Addons.dll under Wine/Rosetta (EXCEPTION_ACCESS_VIOLATION, lj_mcode_patch); interpreted Lua
-- does not. Delete these lines to opt this addon out.
if jit and jit.off then jit.off() end
--[[
* winecursor -- make the mouse work again under wine.
*
* Two separate problems, two separate switches.
*
* 1. THE CURSOR IS INVISIBLE.  FFXI calls ShowCursor(FALSE) every frame and draws its own
*    cursor sprite, which does not render under wine/DXVK.  Holding Win32's show-count at
*    +1 puts the real arrow back.  This is always on; it is the reason this addon exists,
*    and it is a compatibility shim, not a gameplay feature.
*
* 2. ADDON WINDOWS CANNOT BE CLICKED.  Solved 2026-08-23, and not by posting messages at
*    all.  Ashita's ImGui build exposes ImGui's own input event API -- io:AddMousePosEvent
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
*    On by default.  `/winecursor clicks off` disables it.  See docs/MOUSE.md.
*
* Copyright (c) 2026 Bates LLC.  All rights reserved.  https://batesai.org
--]]

addon.name    = 'winecursor';
addon.author  = 'Bates LLC';
addon.version = '1.0';
addon.desc    = 'Restores the mouse cursor under wine, and can make addon windows clickable.';

require 'common';

if (jit ~= nil and jit.off ~= nil) then jit.off(true, true); end

local chat  = require 'chat';
local imgui = require 'imgui';
local ffi   = require 'ffi';

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

local VK_LBUTTON, VK_RBUTTON, VK_MBUTTON = 0x01, 0x02, 0x04

-- ImGui's "pointer is nowhere" sentinel.
local OUTSIDE = -3.4028235e38

local st = {
    clicks = true,
    arrow = nil,
    hwnd = nil,
    down = { [VK_LBUTTON] = false, [VK_RBUTTON] = false, [VK_MBUTTON] = false },
    injected = 0,
    reported = false,
};

local BUTTONS = {
    { vk = VK_LBUTTON, index = 0 },
    { vk = VK_RBUTTON, index = 1 },
    { vk = VK_MBUTTON, index = 2 },
};

local function window()
    if (st.hwnd == nil) then st.hwnd = ffi.C.FindWindowA('FFXiClass', nil); end
    return st.hwnd;
end

--- Cursor position in ImGui's coordinate space, or nil when it is not over the window.
--- The scale step is the one that is easy to miss: ImGui is laid out in DisplaySize units
--- (640x480 here) while ScreenToClient answers in wine client pixels (1564x848).
local function imgui_position(io)
    local h = window();
    if (h == nil) then return nil; end
    local p = ffi.new('POINT');
    if (ffi.C.GetCursorPos(p) == 0) then return nil; end
    if (ffi.C.ScreenToClient(h, p) == 0) then return nil; end

    local r = ffi.new('RECT');
    if (ffi.C.GetClientRect(h, r) == 0 or r.right == 0 or r.bottom == 0) then return nil; end
    if (p.x < 0 or p.y < 0 or p.x > r.right or p.y > r.bottom) then return nil; end

    return p.x * (io.DisplaySize.x / r.right), p.y * (io.DisplaySize.y / r.bottom);
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

    -- 2. the pointer, handed to ImGui through its own event queue
    if (not st.clicks) then return; end
    local io = imgui.GetIO();
    local focused = (ffi.C.GetForegroundWindow() == window());

    local x, y = nil, nil;
    if (focused) then x, y = imgui_position(io); end
    pcall(function () io:AddMousePosEvent(x or OUTSIDE, y or OUTSIDE); end);

    for _, button in ipairs(BUTTONS) do
        -- GetAsyncKeyState only answers while FFXiClass really is foreground; treat
        -- anything else as released so a button cannot stick down across a Cmd-Tab.
        local held = focused and (bit.band(ffi.C.GetAsyncKeyState(button.vk), 0x8000) ~= 0);
        if (held ~= st.down[button.vk]) then
            st.down[button.vk] = held;
            pcall(function () io:AddMouseButtonEvent(button.index, held); end);
            st.injected = st.injected + 1;
        end
    end
end);

ashita.events.register('command', 'winecursor_command', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/winecursor', '/wc')) then return; end
    e.blocked = true;

    local sub = (#args > 1) and args[2]:lower() or 'status';

    if (sub == 'clicks' and #args > 2) then
        st.clicks = args[3]:lower() == 'on';
        print(chat.header(addon.name):append(chat.message('click injection is now '))
            :append(chat.success(st.clicks and 'on' or 'off')));
        if (st.clicks) then
            print(chat.header(addon.name):append(chat.message(
                'fed straight to ImGui; nothing is posted to the game, so the camera is not touched.')));
        end
        return;
    end

    -- Report what ImGui thinks, not just what we did: the open question is whether ImGui
    -- ever reports the pointer as over one of its windows when it receives no messages.
    local io_ok, want, hovered = pcall(function ()
        local io = imgui.GetIO();
        return io.WantCaptureMouse, imgui.IsAnyItemHovered ~= nil and imgui.IsAnyItemHovered() or false;
    end);
    local p = ffi.new('POINT'); ffi.C.GetCursorPos(p);
    print(chat.header(addon.name):append(chat.message(
        ('cursor on, clicks %s, %d injected, WantCaptureMouse=%s, anyItemHovered=%s, cursor=%d,%d')
        :format(st.clicks and 'on' or 'off', st.injected,
                tostring(io_ok and want), tostring(io_ok and hovered), p.x, p.y))));
    print(chat.header(addon.name):append(chat.message('/winecursor clicks on|off')));
end);

ashita.events.register('load', 'winecursor_load', function ()
    print(chat.header(addon.name):append(chat.message(
        'cursor restored, addon windows clickable. /winecursor clicks off to disable.')));
end);

ashita.events.register('unload', 'winecursor_unload', function ()
    -- Leave the count where the game expects it, or the next addon to look sees our +1.
    local guard = 0;
    while (ffi.C.ShowCursor(0) >= 0 and guard < 16) do guard = guard + 1; end
end);
