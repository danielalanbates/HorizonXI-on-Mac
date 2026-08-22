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
* 2. ADDON WINDOWS CANNOT BE CLICKED.  Ashita receives no mouse button messages at all in
*    this wrapper (measured: `mouse events=0` while io.MousePos tracked perfectly).  The
*    2026-08-21 attempt to synthesise the whole message stream fixed clicking and made the
*    camera spin on every Cmd-Tab, because a synthetic WM_MOUSEMOVE hands FFXI's mouse-look
*    a delta the size of the screen.
*
*    So this one injects BUTTONS ONLY -- never WM_MOUSEMOVE, which is the message that
*    caused the spin -- and only while ImGui says the pointer is over one of its windows,
*    so a click meant for the game is never duplicated.  Off by default:
*
*        /winecursor clicks on
*
*    If the camera still misbehaves, `/winecursor clicks off` and say so; that result is
*    worth writing down either way.  See docs/MOUSE.md.
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
typedef void* HWND;
int   GetCursorPos(POINT* p);
int   ScreenToClient(HWND h, POINT* p);
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

local VK_LBUTTON, VK_RBUTTON = 0x01, 0x02
local WM_LBUTTONDOWN, WM_LBUTTONUP = 0x201, 0x202
local WM_RBUTTONDOWN, WM_RBUTTONUP = 0x204, 0x205
local MK_LBUTTON, MK_RBUTTON = 0x0001, 0x0002

local st = {
    clicks = false,
    arrow = nil,
    hwnd = nil,
    down = { [VK_LBUTTON] = false, [VK_RBUTTON] = false },
    injected = 0,
    reported = false,
};

local function window()
    if (st.hwnd == nil) then st.hwnd = ffi.C.FindWindowA('FFXiClass', nil); end
    return st.hwnd;
end

--- Cursor position in the game window's client coordinates, packed the way a mouse message
--- wants it, or nil when the pointer is not over the window.
local function client_lparam()
    local h = window();
    if (h == nil) then return nil; end
    local p = ffi.new('POINT');
    if (ffi.C.GetCursorPos(p) == 0) then return nil; end
    if (ffi.C.ScreenToClient(h, p) == 0) then return nil; end
    if (p.x < 0 or p.y < 0) then return nil; end
    -- LOWORD = x, HIWORD = y
    return (p.y * 65536) + (p.x % 65536);
end

local function press(vk, down_msg, up_msg, flag)
    local held = bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0;
    if (held == st.down[vk]) then return; end
    st.down[vk] = held;

    local h = window();
    local lp = client_lparam();
    if (h == nil or lp == nil) then return; end
    ffi.C.PostMessageA(h, held and down_msg or up_msg, held and flag or 0, lp);
    st.injected = st.injected + 1;
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

    -- 2. the clicks, only where ImGui wants them, and only the buttons
    if (not st.clicks) then return; end
    if (ffi.C.GetForegroundWindow() ~= window()) then
        -- Not focused: forget any held state rather than posting a release into a window
        -- that never saw the press.
        st.down[VK_LBUTTON] = false;
        st.down[VK_RBUTTON] = false;
        return;
    end
    local io = imgui.GetIO();
    if (not io.WantCaptureMouse) then
        st.down[VK_LBUTTON] = false;
        st.down[VK_RBUTTON] = false;
        return;
    end
    press(VK_LBUTTON, WM_LBUTTONDOWN, WM_LBUTTONUP, MK_LBUTTON);
    press(VK_RBUTTON, WM_RBUTTONDOWN, WM_RBUTTONUP, MK_RBUTTON);
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
                'buttons only, never mouse moves. If the camera spins on Cmd-Tab, turn it off and say so.')));
        end
        return;
    end

    print(chat.header(addon.name):append(chat.message(('cursor on, clicks %s, %d messages injected')
        :format(st.clicks and 'on' or 'off', st.injected))));
    print(chat.header(addon.name):append(chat.message('/winecursor clicks on|off')));
end);

ashita.events.register('load', 'winecursor_load', function ()
    print(chat.header(addon.name):append(chat.message(
        'cursor restored. /winecursor clicks on  to try clicking addon windows.')));
end);

ashita.events.register('unload', 'winecursor_unload', function ()
    -- Leave the count where the game expects it, or the next addon to look sees our +1.
    local guard = 0;
    while (ffi.C.ShowCursor(0) >= 0 and guard < 16) do guard = guard + 1; end
end);
