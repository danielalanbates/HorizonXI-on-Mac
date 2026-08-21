addon.name    = 'mousediag';
addon.author  = 'batesai';
addon.version = '0.1';
addon.desc    = 'Logs Win32 cursor / ImGui mouse state to diagnose unclickable ImGui windows.';

require 'common';
local imgui = require 'imgui';
local ffi   = require 'ffi';

ffi.cdef[[
typedef struct { long x; long y; } POINT;
typedef struct { long left; long top; long right; long bottom; } RECT;
typedef void* HWND;
int   GetCursorPos(POINT* p);
int   ScreenToClient(HWND h, POINT* p);
int   GetClientRect(HWND h, RECT* r);
int   GetWindowRect(HWND h, RECT* r);
HWND  WindowFromPoint(POINT p);
HWND  GetForegroundWindow(void);
HWND  GetActiveWindow(void);
HWND  GetCapture(void);
HWND  GetParent(HWND h);
int   GetClassNameA(HWND h, char* buf, int n);
int   GetWindowTextA(HWND h, char* buf, int n);
unsigned long GetWindowLongA(HWND h, int idx);
int   IsWindowVisible(HWND h);
HWND  FindWindowA(const char* cls, const char* title);
unsigned int GetDpiForSystem(void);
short GetAsyncKeyState(int vk);
int ShowCursor(int b);
void* LoadCursorA(void* hi, const char* name);
void* SetCursor(void* c);
long PostMessageA(HWND h, unsigned int msg, unsigned int wp, long lp);
int   ClientToScreen(HWND h, POINT* p);
]]

local logpath = AshitaCore:GetInstallPath() .. '\\addons\\mousediag\\mousediag' .. (os.getenv('FLCLIENT') or '') .. '.log';
local function log(s)
    local f = io.open(logpath, 'a');
    if f then f:write(os.date('%H:%M:%S ') .. s .. '\n'); f:close(); end
end

local function winfo(h)
    if h == nil then return 'nil'; end
    local cls = ffi.new('char[128]'); local ttl = ffi.new('char[128]');
    ffi.C.GetClassNameA(h, cls, 128); ffi.C.GetWindowTextA(h, ttl, 128);
    local wr = ffi.new('RECT'); local cr = ffi.new('RECT');
    ffi.C.GetWindowRect(h, wr); ffi.C.GetClientRect(h, cr);
    local par = ffi.C.GetParent(h);
    return string.format('%08X cls="%s" title="%s" win=(%d,%d,%d,%d) client=%dx%d style=%08X exstyle=%08X vis=%d parent=%s',
        tonumber(ffi.cast('uintptr_t', h)), ffi.string(cls), ffi.string(ttl),
        wr.left, wr.top, wr.right, wr.bottom, cr.right - cr.left, cr.bottom - cr.top,
        tonumber(ffi.C.GetWindowLongA(h, -16)), tonumber(ffi.C.GetWindowLongA(h, -20)),
        ffi.C.IsWindowVisible(h), par == nil and 'nil' or string.format('%08X', tonumber(ffi.cast('uintptr_t', par))));
end

-- Per-client command file so two clients can be driven independently.
-- FLCLIENT=2 in the environment -> addons/mousediag/cmd2.txt
local cmdpath = AshitaCore:GetInstallPath() .. '\\addons\\mousediag\\cmd' .. (os.getenv('FLCLIENT') or '') .. '.txt';
local function pump_commands()
    local f = io.open(cmdpath, 'r');
    if not f then return; end
    local body = f:read('*a'); f:close();
    if body == nil or body == '' then return; end
    local w = io.open(cmdpath, 'w'); if w then w:close(); end
    for line in body:gmatch('[^\r\n]+') do
        if line ~= '' then
            log('CMD: ' .. line);
            if line:sub(1,4) == 'LUA ' then
                local fn, lerr = loadstring(line:sub(5));
                if not fn then log('LUA compile error: ' .. tostring(lerr));
                else
                    local ok, res = pcall(fn);
                    log('LUA result: ' .. tostring(ok) .. ' ' .. tostring(res));
                end
            else
                AshitaCore:GetChatManager():QueueCommand(-1, line);
            end
        end
    end
end

local state = { lastx = -1, lasty = -1, lb = false, rb = false, clicks = 0, hovered = false, lastlog = 0, msgs = {}, msgcount = 0, lastmouse = 'none' };

ashita.events.register('load', 'load_cb', function ()
    log('=== mousediag loaded ===');
    local ok, dpi = pcall(function() return ffi.C.GetDpiForSystem(); end);
    log('GetDpiForSystem: ' .. tostring(ok and dpi or 'n/a'));
    local ffxi = ffi.C.FindWindowA('FFXiClass', nil);
    log('FindWindow FFXiClass: ' .. winfo(ffxi));
    local pol = ffi.C.FindWindowA('PlayOnlineViewer', nil);
    log('FindWindow PlayOnlineViewer: ' .. winfo(pol));
    log('foreground: ' .. winfo(ffi.C.GetForegroundWindow()));
    log('active: ' .. winfo(ffi.C.GetActiveWindow()));
end);


-- Win32's cursor show-count is held one step above visible; see the present callback.
local CURSOR_COUNT_TARGET = 1;

-- Message numbers and the button bits that ride in wParam.
local WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP = 0x0200, 0x0201, 0x0202;
local WM_RBUTTONDOWN, WM_RBUTTONUP = 0x0204, 0x0205;
local MK_LBUTTON, MK_RBUTTON = 0x0001, 0x0002;
local VK_LBUTTON, VK_RBUTTON = 0x01, 0x02;

--- Synthesise the mouse message stream Ashita never receives.
---
--- Under this Wine the client window gets **no** mouse messages at all: Ashita's ImGui sees
--- `MouseDown=nil` and `hovered=false` forever, which is why addon windows cannot be clicked or
--- even hovered. Position is fine, because Ashita polls GetCursorPos for that -- it is only the
--- message stream that is missing. So read the real pointer and the real button state, and post
--- the messages Windows would have posted.
---
--- Two guards, both learned the hard way:
---  * Only ever post while FFXI is the foreground window. GetAsyncKeyState is global: without
---    this, clicking in another app (WoW, a browser) posts those clicks into FFXI as well.
---  * lParam must be *client* coordinates of the FFXiClass window found here. An earlier version
---    of this used whatever window happened to be active, which is what made io.MousePos read as
---    ImGui's -FLT_MAX "no mouse" sentinel (docs/MOUSE.md, "known rough edge").
local function inject_mouse_messages()
    local hwnd = state.client_hwnd;
    if hwnd == nil then
        hwnd = ffi.C.FindWindowA('FFXiClass', nil);
        state.client_hwnd = hwnd;
    end
    if hwnd == nil then return; end
    if ffi.C.GetForegroundWindow() ~= hwnd then
        -- Release anything held, so a button never latches down while the player is elsewhere.
        if state.ldown then
            ffi.C.PostMessageA(hwnd, WM_LBUTTONUP, 0, state.lastlparam or 0);
            state.ldown = false;
        end
        if state.rdown then
            ffi.C.PostMessageA(hwnd, WM_RBUTTONUP, 0, state.lastlparam or 0);
            state.rdown = false;
        end
        return;
    end

    local p = ffi.new('POINT'); ffi.C.GetCursorPos(p);
    local c = ffi.new('POINT'); c.x = p.x; c.y = p.y;
    ffi.C.ScreenToClient(hwnd, c);
    local lparam = bit.bor(bit.lshift(bit.band(c.y, 0xFFFF), 16), bit.band(c.x, 0xFFFF));

    local l = bit.band(ffi.C.GetAsyncKeyState(VK_LBUTTON), 0x8000) ~= 0;
    local r = bit.band(ffi.C.GetAsyncKeyState(VK_RBUTTON), 0x8000) ~= 0;
    local wparam = 0;
    if l then wparam = bit.bor(wparam, MK_LBUTTON); end
    if r then wparam = bit.bor(wparam, MK_RBUTTON); end

    if lparam ~= state.lastlparam then
        ffi.C.PostMessageA(hwnd, WM_MOUSEMOVE, wparam, lparam);
        state.lastlparam = lparam;
    end
    if l ~= state.ldown then
        ffi.C.PostMessageA(hwnd, l and WM_LBUTTONDOWN or WM_LBUTTONUP, wparam, lparam);
        state.ldown = l;
    end
    if r ~= state.rdown then
        ffi.C.PostMessageA(hwnd, r and WM_RBUTTONDOWN or WM_RBUTTONUP, wparam, lparam);
        state.rdown = r;
    end
end

ashita.events.register('mouse', 'mouse_cb', function (e)
    state.msgcount = state.msgcount + 1;
    state.lastmouse = string.format('msg=%03X x=%d y=%d delta=%d blocked=%s', e.message, e.x, e.y, e.delta or 0, tostring(e.blocked));
    if e.message == 0x201 or e.message == 0x202 or e.message == 0x204 then
        log('MOUSE EVENT ' .. state.lastmouse);
    end
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    pump_commands();
    if state.arrow == nil then state.arrow = ffi.C.LoadCursorA(nil, ffi.cast('const char*', 32512)); end
    ffi.C.SetCursor(state.arrow);
    -- Hold Win32's cursor show-count at +1, not 0.
    --
    -- The count is a counter, not a flag: the cursor is drawn while it is >= 0. FFXI calls
    -- ShowCursor(FALSE) itself every frame, so parking the count at exactly 0 means the game's
    -- own call takes it to -1 and the cursor vanishes until this callback runs again -- once per
    -- frame, which is precisely the blink. One step of headroom absorbs the game's decrement and
    -- the cursor stays drawn; the clamp below stops it growing without bound.
    local n = ffi.C.ShowCursor(1);
    local guard = 0;
    while n > CURSOR_COUNT_TARGET and guard < 16 do n = ffi.C.ShowCursor(0); guard = guard + 1; end
    while n < CURSOR_COUNT_TARGET and guard < 32 do n = ffi.C.ShowCursor(1); guard = guard + 1; end
    if state.curlog == nil then state.curlog = true; log('ShowCursor count -> ' .. tostring(n)); end
    local io = imgui.GetIO();
    inject_mouse_messages();
    state.hovered = io.WantCaptureMouse;
    local now = os.clock();
    if now - state.lastlog > 2.0 then
        state.lastlog = now;
        local p = ffi.new('POINT'); ffi.C.GetCursorPos(p);
        local sp = { x = p.x, y = p.y };
        local under = ffi.C.WindowFromPoint(p);
        local act = ffi.C.GetActiveWindow();
        local cp = ffi.new('POINT'); cp.x = sp.x; cp.y = sp.y;
        if act ~= nil then ffi.C.ScreenToClient(act, cp); end
        log(string.format('TICK imgui=(%.0f,%.0f) disp=%.0fx%.0f want=%s down=%s hovered=%s | cursor screen=(%d,%d) client=(%d,%d) | msgs=%d last=%s',
            io.MousePos.x, io.MousePos.y, io.DisplaySize.x, io.DisplaySize.y, tostring(io.WantCaptureMouse), tostring(io.MouseDown[0]), tostring(state.hovered),
            sp.x, sp.y, cp.x, cp.y, state.msgcount, state.lastmouse));
        log('  under-cursor: ' .. winfo(under));
        log('  active: ' .. winfo(act));
        log('  foreground: ' .. winfo(ffi.C.GetForegroundWindow()));
        log('  capture: ' .. winfo(ffi.C.GetCapture()));
    end
end);


-- Temporary discovery: capture incoming chat so /sea output format can be learned.
ashita.events.register('text_in', 'textin_cb', function (e)
    local mode = bit.band(e.mode_modified, 0xFF);
    local msg = e.message_modified or e.message or '';
    msg = msg:gsub('[\x00-\x1f\x7f-\xff]', '.');
    log(string.format('TEXTIN mode=%d inj=%s | %s', mode, tostring(e.injected), msg));
end);


-- Does ANY synthetic keyboard input reach the client? Log every key Ashita sees.
ashita.events.register('key', 'key_cb', function (e)
    log(string.format('KEY key=%s down=%s blocked=%s', tostring(e.key), tostring(e.down), tostring(e.blocked)));
end);
ashita.events.register('key_data', 'keydata_cb', function (e)
    log(string.format('KEYDATA key=%s down=%s', tostring(e.key), tostring(e.down)));
end);


-- Does opening the NATIVE friend menu send anything to the game server?
ashita.events.register('packet_out', 'pkt_out_cb', function (e)
    log(string.format('PKTOUT id=0x%03X size=%d', e.id, e.size));
end);
ashita.events.register('packet_in', 'pkt_in_cb', function (e)
    if e.id == 0x041 or e.id == 0x059 or e.id == 0x072 or e.id == 0x081 then
        log(string.format('PKTIN  id=0x%03X size=%d', e.id, e.size));
    end
end);
