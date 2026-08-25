-- Offline harness: runs winecursor.lua against a stubbed Ashita/Win32 so the message
-- stream it would post can be asserted without a game client.

local ok_bit = bit

------------------------------------------------------------------ simulated Win32 world
local SIM = {
    cursor   = { x = 100, y = 100 },   -- screen coords
    origin   = { x = 0, y = 0 },       -- client origin in screen coords
    client   = { w = 1564, h = 848 },
    fg       = 'game',                 -- 'game' | 'other'
    keys     = { },                    -- vk -> bool
    showcount = 0,
    viewport = { w = 1920, h = 1080 },   -- nil to simulate the device not answering
}

local POSTED = { }

local function reset_posted() POSTED = { } end

local ffi_stub = {
    cdef = function () end,
    cast = function (_, v) return v end,
    new  = function (t)
        if (t == 'POINT') then return { x = 0, y = 0 }; end
        if (t == 'RECT') then return { left = 0, top = 0, right = 0, bottom = 0 }; end
        error('unexpected ffi.new: ' .. tostring(t));
    end,
    C = {
        GetCursorPos = function (p) p.x = SIM.cursor.x; p.y = SIM.cursor.y; return 1; end,
        ScreenToClient = function (h, p)
            if (h ~= 'HWND_GAME') then return 0; end
            p.x = p.x - SIM.origin.x; p.y = p.y - SIM.origin.y; return 1;
        end,
        GetClientRect = function (h, r)
            if (h ~= 'HWND_GAME') then return 0; end
            r.right = SIM.client.w; r.bottom = SIM.client.h; return 1;
        end,
        FindWindowA = function (cls) return cls == 'FFXiClass' and 'HWND_GAME' or nil; end,
        GetForegroundWindow = function () return SIM.fg == 'game' and 'HWND_GAME' or 'HWND_OTHER'; end,
        GetAsyncKeyState = function (vk) return SIM.keys[vk] and 0x8000 or 0; end,
        ShowCursor = function (b)
            SIM.showcount = SIM.showcount + (b ~= 0 and 1 or -1);
            return SIM.showcount;
        end,
        LoadCursorA = function () return 'ARROW'; end,
        SetCursor = function (c) return c; end,
        PostMessageA = function (h, msg, wp, lp)
            table.insert(POSTED, { hwnd = h, msg = msg, wparam = wp, lparam = lp });
            return 1;
        end,
    },
};

------------------------------------------------------------------ stubbed Ashita surface
local EVENTS = { };
local BLOCKED = { value = nil };
local OUTPUT = { };

local io_stub = {
    DisplaySize = { x = 640, y = 480 },
    WantCaptureMouse = false,
    events = { },
};
function io_stub:AddMousePosEvent(x, y) table.insert(self.events, { 'pos', x, y }); end
function io_stub:AddMouseButtonEvent(b, d) table.insert(self.events, { 'button', b, d }); end
function io_stub:AddKeyEvent(k, d) table.insert(self.events, { 'key', k, d }); end

local imgui_stub = { GetIO = function () return io_stub; end };

local d3d8_stub = {
    get_device = function ()
        return {
            GetViewport = function ()
                if (SIM.viewport == nil) then return 1, nil; end
                return 0, { Width = SIM.viewport.w, Height = SIM.viewport.h };
            end,
        };
    end,
};

local chat_stub = {
    header  = function (s) return setmetatable({ s = '[' .. s .. '] ' }, {
        __index = { append = function (self, v) self.s = self.s .. tostring(v); return self; end },
        __tostring = function (self) return self.s; end,
    }); end,
    message = function (s) return s; end,
    success = function (s) return s; end,
};

local ashita_stub = {
    events = {
        register = function (name, alias, fn)
            EVENTS[name] = EVENTS[name] or { };
            table.insert(EVENTS[name], { alias = alias, fn = fn });
        end,
    },
};

local QUEUED = { };

local AshitaCore_stub = {
    GetInstallPath = function () return os.getenv('HARNESS_INSTALL') or '.'; end,
    GetChatManager = function ()
        return { QueueCommand = function (_, mode, line) table.insert(QUEUED, line); end };
    end,
    GetInputManager = function ()
        return {
            GetMouse = function ()
                return { SetBlockInput = function (_, v) BLOCKED.value = v; end };
            end,
        };
    end,
};

-- string extensions the addon relies on (Ashita's common.lua provides these)
local smeta = getmetatable('')
function smeta.__index.args(s)
    local t = { };
    for w in s:gmatch('%S+') do table.insert(t, w); end
    return t;
end
function smeta.__index.any(s, ...)
    for _, v in ipairs({ ... }) do if (s == v) then return true; end end
    return false;
end

------------------------------------------------------------------ load the addon
local env = setmetatable({
    addon      = { },
    ashita     = ashita_stub,
    AshitaCore = AshitaCore_stub,
    require    = function (n)
        if (n == 'chat') then return chat_stub; end
        if (n == 'imgui') then return imgui_stub; end
        if (n == 'ffi') then return ffi_stub; end
        if (n == 'd3d8') then return d3d8_stub; end
        if (n == 'common') then return true; end
        error('unexpected require: ' .. n);
    end,
    print      = function (s) table.insert(OUTPUT, tostring(s)); end,
    jit        = nil,   -- skip the JIT guard branches
    bit        = ok_bit,
}, { __index = _G });

local chunk = assert(loadfile((...) or 'winecursor.lua'));
setfenv(chunk, env);
chunk();

local function fire(name, e)
    for _, h in ipairs(EVENTS[name] or { }) do h.fn(e); end
    return e;
end

local present = function () fire('d3d_present'); end

------------------------------------------------------------------ assertions
local failures = 0;
local function check(label, cond, detail)
    if (cond) then
        print(('  ok   %s'):format(label));
    else
        failures = failures + 1;
        print(('  FAIL %s%s'):format(label, detail and ('  -- ' .. detail) or ''));
    end
end

local function last(msg)
    for i = #POSTED, 1, -1 do if (POSTED[i].msg == msg) then return POSTED[i]; end end
    return nil;
end
local function count(msg)
    local n = 0;
    for _, p in ipairs(POSTED) do if (p.msg == msg) then n = n + 1; end end
    return n;
end

print('scenario 1: pointer over the window, nothing held');
reset_posted();
SIM.cursor = { x = 782, y = 424 };   -- dead centre of a 1564x848 client
present();
local mm = last(0x200);
check('WM_MOUSEMOVE posted', mm ~= nil);
if (mm) then
    local x, y = bit.band(mm.lparam, 0xFFFF), bit.band(bit.rshift(mm.lparam, 16), 0xFFFF);
    check('scaled into back-buffer space (960,540)', x == 960 and y == 540, ('got %d,%d'):format(x, y));
    check('wparam has no buttons', mm.wparam == 0, ('got %d'):format(mm.wparam));
end
-- ImGui is fed in its own space in the same frame, and the two must not be confused.
local ipos = io_stub.events[#io_stub.events - 0];
for i = #io_stub.events, 1, -1 do
    if (io_stub.events[i][1] == 'pos') then ipos = io_stub.events[i]; break; end
end
check('ImGui still fed in DisplaySize space (320,240)',
      math.floor(ipos[2] + 0.5) == 320 and math.floor(ipos[3] + 0.5) == 240,
      ('got %s,%s'):format(tostring(ipos[2]), tostring(ipos[3])));

print('scenario 2: no repeat move when the pointer is still');
reset_posted();
present();
check('nothing re-posted', #POSTED == 0, ('posted %d'):format(#POSTED));

print('scenario 3: shift down, key stream dead -> synthesised VK_SHIFT');
reset_posted();
SIM.keys[0x10] = true;
present();
local kd = last(0x100);
check('WM_KEYDOWN posted', kd ~= nil);
if (kd) then
    check('wparam is VK_SHIFT', kd.wparam == 0x10);
    check('lparam transition bit clear (key is DOWN)', bit.band(kd.lparam, 0x80000000) == 0);
end

print('scenario 4: shift+left press on the panel');
reset_posted();
SIM.keys[0x01] = true;
present();
local ld = last(0x201);
check('WM_LBUTTONDOWN posted', ld ~= nil);
if (ld) then
    check('wparam carries MK_LBUTTON|MK_SHIFT', ld.wparam == 0x0005, ('got %d'):format(ld.wparam));
end

print('scenario 5: drag');
reset_posted();
SIM.cursor = { x = 882, y = 524 };
present();
local dm = last(0x200);
check('move posted while held', dm ~= nil);
if (dm) then
    check('wparam still carries the held button', bit.band(dm.wparam, 0x0001) ~= 0);
    local x, y = bit.band(dm.lparam, 0xFFFF), bit.band(bit.rshift(dm.lparam, 16), 0xFFFF);
    check('new position scaled+rounded (1083,667)', x == 1083 and y == 667, ('got %d,%d'):format(x, y));
end

print('scenario 6: release');
reset_posted();
SIM.keys[0x01] = false;
present();
check('WM_LBUTTONUP posted', last(0x202) ~= nil);
check('and no stray second down', count(0x201) == 0);

print('scenario 7: cmd-tab away mid-drag releases the button');
reset_posted();
SIM.keys[0x01] = true; present();          -- press again
reset_posted();
SIM.fg = 'other'; present();               -- focus lost while held
check('release delivered off-window', last(0x202) ~= nil);
check('no move posted while unfocused', count(0x200) == 0);
SIM.fg = 'game';

print('scenario 8: every synthetic message comes back blocked');
local e = fire('mouse', { message = 0x200, x = 1, y = 1, blocked = false });
check('e.blocked set', e.blocked == true);

print('scenario 9: a real key event switches the synthetic shift off');
reset_posted();
SIM.keys[0x10] = false; present();          -- shift up, still synthesised
fire('key', { wparam = 0x41, lparam = 0 }); -- a real 'A' arrives -> stream is alive
reset_posted();
SIM.keys[0x10] = true; present();
check('no VK_SHIFT posted once the real stream is proven', last(0x100) == nil);
SIM.keys[0x10] = false; present();

print('scenario 9b: no viewport -> falls back to ImGui DisplaySize');
SIM.viewport = nil;
reset_posted();
SIM.cursor = { x = 782, y = 424 };
present();
local fb = last(0x200);
check('move still posted', fb ~= nil);
if (fb) then
    local x, y = bit.band(fb.lparam, 0xFFFF), bit.band(bit.rshift(fb.lparam, 16), 0xFFFF);
    check('fell back to 640x480 space (320,240)', x == 320 and y == 240, ('got %d,%d'):format(x, y));
end
SIM.viewport = { w = 1920, h = 1080 };

print('scenario 10: commands');
OUTPUT = { };
fire('command', { command = '/winecursor', blocked = false });
check('status prints without error', #OUTPUT >= 3, ('printed %d lines'):format(#OUTPUT));
for _, l in ipairs(OUTPUT) do print('       ' .. l); end

OUTPUT = { };
fire('command', { command = '/winecursor block input', blocked = false });
present();
check('block input engages SetBlockInput', BLOCKED.value == true, tostring(BLOCKED.value));

OUTPUT = { };
fire('command', { command = '/winecursor wndproc off', blocked = false });
present();
check('wndproc off releases the block', BLOCKED.value == false, tostring(BLOCKED.value));
reset_posted();
present();
check('wndproc off posts nothing', #POSTED == 0, ('posted %d'):format(#POSTED));

fire('command', { command = '/winecursor wndproc on', blocked = false });
fire('command', { command = '/winecursor block event', blocked = false });

print('scenario 10b: shell -> game command channel');
do
    local base = (os.getenv('HARNESS_INSTALL') or '.') .. '\\addons\\winecursor\\';
    local f = io.open(base .. 'cmd.txt', 'w');
    f:write('/addon reload winecursor\nLUA return 6*7\n');
    f:close();
    for _ = 1, 30 do present(); end            -- the poll runs every 30th frame
    check('command queued', QUEUED[1] == '/addon reload winecursor', tostring(QUEUED[1]));
    local o = io.open(base .. 'cmd.out', 'r');
    local body = o and o:read('*a') or '';
    if (o) then o:close(); end
    check('LUA result written to cmd.out', body:find('ok 42') ~= nil, body:gsub('\n', ' | '));
    local again = io.open(base .. 'cmd.txt', 'r');
    local left = again and again:read('*a') or 'MISSING';
    if (again) then again:close(); end
    check('cmd.txt emptied', left == '', ('left %q'):format(left));
end

print('scenario 11: unload restores the cursor count and the block');
SIM.showcount = 1;
fire('unload', { });
check('SetBlockInput released', BLOCKED.value == false);
check('show count left below zero', SIM.showcount < 0, ('count %d'):format(SIM.showcount));

print('');
if (failures == 0) then
    print('ALL CHECKS PASSED');
else
    print(('%d CHECK(S) FAILED'):format(failures));
    os.exit(1);
end
