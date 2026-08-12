--[[
* fpslog -- renderer-agnostic frame rate logger for HorizonXI-on-Mac benchmarking.
*
* Counts d3d_present callbacks, so it measures the frame rate the *game* actually achieves
* no matter which translation stack is underneath (DXVK/MoltenVK, DXMT, wined3d, dgVoodoo).
* Writes one CSV row per second to <install>\logs\fpslog.csv.
*
* Config (optional): <install>\logs\fpslog.conf, "key=value" per line
*     tag=<label>        label written into every row so runs can be told apart
*     settle=<seconds>   rows before this are marked settle=1 and excluded from summaries
*
* Commands:
*     /fpslog tag <name>     relabel the current run
*     /fpslog mark <text>    write a marker row
*     /fpslog sample <secs>  print an average to the chat log
--]]

addon.name    = 'fpslog';
addon.author  = 'HorizonXI-on-Mac';
addon.version = '1.0';
addon.desc    = 'Logs frame rate and scene stats to CSV for benchmarking.';

require 'common';

local st = {
    frames  = 0,
    tick    = 0,
    t0      = 0,
    row     = 0,
    tag     = 'run',
    settle  = 0,
    path    = nil,
    sample  = nil,
};

local function install_path()
    local ok, p = pcall(function() return AshitaCore:GetInstallPath(); end);
    if (not ok or p == nil or p == '') then
        return 'C:\\HorizonXI';
    end
    if (p:sub(-1) == '\\' or p:sub(-1) == '/') then
        p = p:sub(1, #p - 1);
    end
    return p;
end

local function read_conf()
    local f = io.open(install_path() .. '\\logs\\fpslog.conf', 'r');
    if (f == nil) then return; end
    for line in f:lines() do
        local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$');
        if (k == 'tag' and v ~= nil) then st.tag = v; end
        if (k == 'settle' and v ~= nil) then st.settle = tonumber(v) or 0; end
    end
    f:close();
end

local function write_row(cols)
    local f = io.open(st.path, 'a');
    if (f == nil) then return; end
    f:write(table.concat(cols, ',') .. '\n');
    f:close();
end

-- Number of entities the client currently has flagged for rendering. Correlates with how
-- much geometry the frame is submitting, which is the thing that actually limits us.
local function rendered_entities()
    local ok, n = pcall(function()
        local ents = AshitaCore:GetMemoryManager():GetEntity();
        local c = 0;
        for i = 0, 2303 do
            local flags = ents:GetRenderFlags0(i);
            if (flags ~= nil and bit.band(flags, 0x200) == 0x200) then
                c = c + 1;
            end
        end
        return c;
    end);
    return ok and n or -1;
end

local function scene()
    local zone, x, y, z = -1, 0, 0, 0;
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        zone = party:GetMemberZone(0) or -1;
        local idx = party:GetMemberTargetIndex(0) or 0;
        if (idx > 0) then
            local ents = AshitaCore:GetMemoryManager():GetEntity();
            x = ents:GetLocalX(idx) or 0;
            y = ents:GetLocalY(idx) or 0;
            z = ents:GetLocalZ(idx) or 0;
        end
    end);
    return zone, x, y, z;
end

ashita.events.register('load', 'fpslog_load', function ()
    read_conf();
    st.path = install_path() .. '\\logs\\fpslog.csv';
    st.t0   = os.clock();
    st.tick = os.time();
    write_row({ '#start', tostring(os.time()), st.tag, tostring(st.settle) });
    write_row({ 'epoch', 'elapsed', 'fps', 'zone', 'x', 'y', 'z', 'ents', 'settle', 'tag' });
end);

ashita.events.register('unload', 'fpslog_unload', function ()
    write_row({ '#stop', tostring(os.time()), st.tag });
end);

ashita.events.register('command', 'fpslog_command', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/fpslog') then return; end
    e.blocked = true;

    if (#args >= 3 and args[2] == 'tag') then
        st.tag = args[3];
        print('[fpslog] tag = ' .. st.tag);
        return;
    end
    if (#args >= 3 and args[2] == 'mark') then
        write_row({ '#mark', tostring(os.time()), table.concat(args, ' ', 3) });
        return;
    end
    if (#args >= 3 and args[2] == 'sample') then
        st.sample = { n = 0, fin = os.clock() + (tonumber(args[3]) or 30), len = tonumber(args[3]) or 30 };
        print('[fpslog] sampling ' .. tostring(st.sample.len) .. 's');
        return;
    end
    print('[fpslog] /fpslog (tag <name> | mark <text> | sample <secs>)');
end);

ashita.events.register('d3d_present', 'fpslog_present', function ()
    st.frames = st.frames + 1;

    if (st.sample ~= nil) then
        if (os.clock() > st.sample.fin) then
            print(('[fpslog] %d frames in %ds = %.2f fps'):fmt(st.sample.n, st.sample.len, st.sample.n / st.sample.len));
            st.sample = nil;
        else
            st.sample.n = st.sample.n + 1;
        end
    end

    local now = os.time();
    if (now < st.tick + 1) then return; end

    local fps     = st.frames / (now - st.tick);
    local elapsed = os.clock() - st.t0;
    st.frames = 0;
    st.tick   = now;
    st.row    = st.row + 1;

    local zone, x, y, z = scene();
    write_row({
        tostring(now),
        ('%.1f'):fmt(elapsed),
        ('%.2f'):fmt(fps),
        tostring(zone),
        ('%.1f'):fmt(x), ('%.1f'):fmt(y), ('%.1f'):fmt(z),
        tostring(rendered_entities()),
        (elapsed < st.settle) and '1' or '0',
        st.tag,
    });
end);
