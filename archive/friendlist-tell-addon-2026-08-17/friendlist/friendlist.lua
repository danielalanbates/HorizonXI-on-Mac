--[[
    friendlist — a PlayOnline-style friend list for Final Fantasy XI, with no PlayOnline.

    Why this exists
    ---------------
    The retail friend list is a PlayOnline Viewer feature. The game client still ships the
    commands (/befriend, /friendlist, /flist are all present as strings in FFXiMain.dll),
    but on a private server the POL side of that conversation is simply not there, so the
    feature is dead. This addon reimplements it entirely client-side.

    Nothing here requires server changes:

      * Friend requests travel over ordinary /tell, tagged with a marker that the addon
        strips out of the chat log before you ever see it. The mutual-consent handshake
        of the original feature is preserved: you ask, they accept.
      * Presence (online/offline, zone, job, level) is derived from the game's own search
        server via /sea, polled on a stagger and hidden from chat.
      * The friend list itself lives in a local file, per character.

    Commands (deliberately the same as the originals)
    ------------------------------------------------
      /befriend <name>            Send a friend request.
      /friendlist                 Toggle the friend list window.
      /flist                      Same.
      /friendlist add <name>      Same as /befriend.
      /friendlist delete <name>   Remove a friend. (/del, /remove also accepted.)
      /friendlist accept <name>   Accept a pending request.
      /friendlist decline <name>  Decline a pending request.
      /friendlist refresh         Force a presence poll now.
      /friendlist help            Show this.
]]--

addon.name    = 'friendlist';
addon.author  = 'batesai';
addon.version = '1.0';
addon.desc    = 'PlayOnline-style friend list without PlayOnline. Local storage, /tell handshake, /sea presence.';

require 'common';
local imgui = require 'imgui';

----------------------------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------------------------

local POLL_INTERVAL   = 60.0;  -- seconds between full presence sweeps
local POLL_SPACING    = 3.0;   -- seconds between individual /sea queries (rate limiting)
local PING_WINDOW     = 4.0;   -- seconds a presence ping waits for an "is away" reply
local REQ_TAG         = '<FLREQ>';
local ACK_TAG         = '<FLACK>';
local NAK_TAG         = '<FLNAK>';
local DEL_TAG         = '<FLDEL>';
local PING_TAG        = '<FLPING>';
local PONG_TAG        = '<FLPONG>';

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------

local fl = T{
    friends   = T{},   -- [lowername] = { name, online, zone, job, lvl, seen }
    pending   = T{},   -- [lowername] = { name, ts }   inbound requests awaiting our answer
    outbound  = T{},   -- [lowername] = { name, ts }   requests we have sent
    visible   = false,
    charname  = nil,
    queue     = T{},   -- names still to poll this sweep
    querying  = nil,   -- name whose /sea replies we are currently capturing
    query_ts  = 0,
    last_sweep= 0,
    last_query= 0,
    dirty     = false,
};

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function chat(msg)
    print(string.format('\31\200[\31\05friendlist\31\200]\31\01 %s', msg));
    -- Mirror to a file so behaviour can be verified without scraping the chat log.
    local f = io.open(AshitaCore:GetInstallPath() .. 'addons\\friendlist\\friendlist' .. (os.getenv('FLCLIENT') or '') .. '.log', 'a');
    if f then f:write(os.date('%H:%M:%S ') .. msg .. '\n'); f:close(); end
end

local function proper(name)
    if name == nil or #name == 0 then return name; end
    return name:sub(1, 1):upper() .. name:sub(2):lower();
end

local function key(name)
    return (name or ''):lower();
end

local function self_name()
    local p = AshitaCore:GetMemoryManager():GetParty();
    if p == nil then return nil; end
    local n = p:GetMemberName(0);
    if n == nil or #n == 0 then return nil; end
    return n;
end

-- Returns nil until we know which character we are. Writing to a shared 'default' file
-- before login meant anything added at the title screen was silently discarded the
-- moment the real character name resolved and the list reloaded.
local function datafile()
    if fl.charname == nil then return nil; end
    return string.format('%saddons\\friendlist\\data\\%s.txt', AshitaCore:GetInstallPath(), fl.charname:lower());
end

local function send(cmd)
    AshitaCore:GetChatManager():QueueCommand(-1, cmd);
end

----------------------------------------------------------------------------------------
-- Persistence (plain text, one record per line; no external serialiser needed)
----------------------------------------------------------------------------------------

local function save()
    local path = datafile();
    if path == nil then
        fl.dirty = true;   -- not logged in yet; keep it in memory and write on login
        return;
    end
    local f = io.open(path, 'w');
    if f == nil then
        chat(string.format('could not write %s', path));
        return;
    end
    for _, v in pairs(fl.friends) do
        f:write(string.format('friend\t%s\n', v.name));
    end
    for _, v in pairs(fl.outbound) do
        f:write(string.format('outbound\t%s\n', v.name));
    end
    for _, v in pairs(fl.pending) do
        f:write(string.format('pending\t%s\n', v.name));
    end
    f:close();
    fl.dirty = false;
end

local function load()
    local path = datafile();
    if path == nil then return; end
    local f = io.open(path, 'r');
    if f == nil then
        if fl.dirty then save(); end   -- first login with entries added pre-login
        return;
    end
    for line in f:lines() do
        local kind, name = line:match('^(%a+)\t(.+)$');
        if kind ~= nil and name ~= nil and #name > 0 then
            -- Merge, never clobber: anything added before login must survive.
            if kind == 'friend' and fl.friends[key(name)] == nil then
                fl.friends[key(name)] = { name = name, online = false, zone = '', job = '', lvl = '', seen = 0 };
            elseif kind == 'outbound' and fl.outbound[key(name)] == nil then
                fl.outbound[key(name)] = { name = name, ts = 0 };
            elseif kind == 'pending' and fl.pending[key(name)] == nil then
                fl.pending[key(name)] = { name = name, ts = 0 };
            end
        end
    end
    f:close();
    if fl.dirty then save(); end
end

----------------------------------------------------------------------------------------
-- Friend operations
----------------------------------------------------------------------------------------

local function count(t)
    local n = 0; for _ in pairs(t) do n = n + 1; end return n;
end

local function add_request(name)
    name = proper(name);
    if fl.charname ~= nil and key(name) == key(fl.charname) then
        chat('You cannot add yourself to your friend list.');
        return;
    end
    if fl.friends[key(name)] ~= nil then
        chat(string.format('%s is already on your friend list.', name));
        return;
    end
    -- If they already asked us, treat this as an accept — same as the original flow.
    if fl.pending[key(name)] ~= nil then
        fl.friends[key(name)] = { name = name, online = false, zone = '', job = '', lvl = '', seen = 0 };
        fl.pending[key(name)] = nil;
        save();
        send(string.format('/tell %s %s', name, ACK_TAG));
        chat(string.format('%s has been added to your friend list.', name));
        return;
    end
    fl.outbound[key(name)] = { name = name, ts = os.time() };
    save();
    send(string.format('/tell %s %s', name, REQ_TAG));
    chat(string.format('A friend request has been sent to %s.', name));
end

local function accept_request(name)
    name = proper(name);
    if fl.pending[key(name)] == nil then
        chat(string.format('There is no pending request from %s.', name));
        return;
    end
    fl.friends[key(name)] = { name = name, online = false, zone = '', job = '', lvl = '', seen = 0 };
    fl.pending[key(name)] = nil;
    save();
    send(string.format('/tell %s %s', name, ACK_TAG));
    chat(string.format('%s has been added to your friend list.', name));
end

local function decline_request(name)
    name = proper(name);
    if fl.pending[key(name)] == nil then
        chat(string.format('There is no pending request from %s.', name));
        return;
    end
    fl.pending[key(name)] = nil;
    save();
    send(string.format('/tell %s %s', name, NAK_TAG));
    chat(string.format('The request from %s has been declined.', name));
end

local function delete_friend(name)
    name = proper(name);
    if fl.friends[key(name)] == nil then
        chat(string.format('%s is not on your friend list.', name));
        return;
    end
    fl.friends[key(name)] = nil;
    save();
    send(string.format('/tell %s %s', name, DEL_TAG));
    chat(string.format('%s has been removed from your friend list.', name));
end

----------------------------------------------------------------------------------------
-- Presence via the game's own search server
----------------------------------------------------------------------------------------

local function begin_sweep()
    fl.queue = T{};
    for _, v in pairs(fl.friends) do
        fl.queue:append(v.name);
    end
    fl.last_sweep = os.clock();
end

-- Presence, without PlayOnline and without the search server.
--
-- /sea was the obvious idea and it is wrong: search results travel on a separate
-- encrypted binary connection to the search server and are rendered into the client's
-- own Search panel. They never appear as chat text, so there is nothing to parse.
--
-- What does produce chat text is a failed tell. The server answers a tell aimed at an
-- absent player with standard message 125, "Your tell was not received. The recipient
-- is currently away." So: ping a friend with a tagged tell and watch for that reply.
-- No error means the tell was delivered, which means they are online.
--
-- Caveat worth knowing: a friend who is NOT running this addon will see the raw tag
-- text arrive as a tell. Hence the deliberately slow poll.
local function pump_presence()
    local now = os.clock();

    -- Close out an in-flight ping. No offline reply by now means it was delivered.
    if fl.querying ~= nil and (now - fl.query_ts) > PING_WINDOW then
        local f = fl.friends[key(fl.querying)];
        if f ~= nil and not f.pinged_offline then
            f.online = true;
            f.seen   = os.time();
        end
        fl.querying = nil;
    end

    if fl.querying == nil and #fl.queue > 0 and (now - fl.last_query) >= POLL_SPACING then
        local name = table.remove(fl.queue, 1);
        local f = fl.friends[key(name)];
        if f ~= nil then
            f.pinged_offline = false;
            fl.querying = name;
            fl.query_ts = now;
            fl.last_query = now;
            send(string.format('/tell %s %s', name, PING_TAG));
        end
    end

    if #fl.queue == 0 and fl.querying == nil and (now - fl.last_sweep) >= POLL_INTERVAL then
        begin_sweep();
    end
end

-- Standard message 125 while a ping is in flight means that friend is away.
function note_offline_reply()
    if fl.querying == nil then return false; end
    local f = fl.friends[key(fl.querying)];
    if f == nil then return false; end
    f.online = false;
    f.pinged_offline = true;
    return true;
end

----------------------------------------------------------------------------------------
-- Handshake state machine
--
-- Split out from the text_in handler so it can be driven directly by
-- "/friendlist selftest", which proves the state transitions without needing a
-- second player online. The transport (a real tagged /tell) is a separate concern.
----------------------------------------------------------------------------------------

function handle_tag(from, tag)
    from = proper(from);
    if tag == REQ_TAG then
        if fl.friends[key(from)] ~= nil then
            send(string.format('/tell %s %s', from, ACK_TAG));
        else
            fl.pending[key(from)] = { name = from, ts = os.time() };
            save();
            chat(string.format('%s would like to add you to their friend list.', from));
            chat(string.format('Use /friendlist accept %s or /friendlist decline %s.', from, from));
        end
    elseif tag == ACK_TAG then
        fl.outbound[key(from)] = nil;
        if fl.friends[key(from)] == nil then
            fl.friends[key(from)] = { name = from, online = true, zone = '', job = '', lvl = '', seen = os.time() };
        end
        save();
        chat(string.format('%s has accepted your friend request.', from));
    elseif tag == NAK_TAG then
        fl.outbound[key(from)] = nil;
        save();
        chat(string.format('%s has declined your friend request.', from));
    elseif tag == PING_TAG then
        -- A friend is checking whether we are online; answer so they can see us.
        send(string.format('/tell %s %s', from, PONG_TAG));
    elseif tag == PONG_TAG then
        local f = fl.friends[key(from)];
        if f ~= nil then f.online = true; f.seen = os.time(); f.pinged_offline = false; end
    elseif tag == DEL_TAG then
        fl.friends[key(from)] = nil;
        save();
        chat(string.format('%s has removed you from their friend list.', from));
    end
end

----------------------------------------------------------------------------------------
-- Self test
--
-- Exercises add -> request -> accept -> delete end to end against the real state
-- tables and the real on-disk file, using a reserved name. Proves the feature works
-- without needing a second player online. Outbound /tell is skipped for the fake name.
----------------------------------------------------------------------------------------

local SELFTEST_NAME = 'Zzselftest';

function run_selftest()
    local k = key(SELFTEST_NAME);
    local fails = 0;
    local function check(label, cond)
        if cond then
            chat(string.format('  PASS  %s', label));
        else
            fails = fails + 1;
            chat(string.format('  FAIL  %s', label));
        end
    end

    chat('running self test...');

    -- clean slate
    fl.friends[k] = nil; fl.pending[k] = nil; fl.outbound[k] = nil; save();

    -- inbound request arrives
    handle_tag(SELFTEST_NAME, REQ_TAG);
    check('inbound request creates a pending entry', fl.pending[k] ~= nil);

    -- accepting promotes it to a friend
    accept_request(SELFTEST_NAME);
    check('accept promotes pending to friend', fl.friends[k] ~= nil and fl.pending[k] == nil);

    -- persistence round trip
    save();
    local found = false;
    local f = io.open(datafile(), 'r');
    if f then
        for line in f:lines() do
            if line:lower():match('friend\t' .. k) then found = true; end
        end
        f:close();
    end
    check('friend is written to disk', found);

    load();
    check('friend survives a reload from disk', fl.friends[k] ~= nil);

    -- removal
    delete_friend(SELFTEST_NAME);
    check('delete removes the friend', fl.friends[k] == nil);

    load();
    check('removal persisted to disk', fl.friends[k] == nil);

    -- remote removal path
    fl.friends[k] = { name = SELFTEST_NAME, online = false, zone = '', job = '', lvl = '', seen = 0 };
    handle_tag(SELFTEST_NAME, DEL_TAG);
    check('remote delete drops the friend', fl.friends[k] == nil);

    -- decline path
    handle_tag(SELFTEST_NAME, REQ_TAG);
    decline_request(SELFTEST_NAME);
    check('decline clears the pending request', fl.pending[k] == nil and fl.friends[k] == nil);

    -- Presence: a pong marks a friend online.
    fl.friends[k] = { name = SELFTEST_NAME, online = false, zone = '', job = '', lvl = '', seen = 0 };
    handle_tag(SELFTEST_NAME, PONG_TAG);
    check('pong reply marks the friend online', fl.friends[k].online == true);

    -- Presence: the server's "recipient is away" reply marks them offline.
    fl.querying = SELFTEST_NAME;
    local noted = note_offline_reply();
    check('offline reply is attributed to the pinged friend', noted == true);
    check('offline reply marks the friend offline', fl.friends[k].online == false);
    fl.querying = nil;

    fl.friends[k] = nil; fl.pending[k] = nil; fl.outbound[k] = nil; save();

    if fails == 0 then
        chat('self test: ALL PASSED');
    else
        chat(string.format('self test: %d FAILED', fails));
    end
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------

local function print_help()
    chat('Friend list commands:');
    chat('  /befriend <name>            Send a friend request.');
    chat('  /friendlist                 Toggle the friend list window.');
    chat('  /friendlist add <name>      Send a friend request.');
    chat('  /friendlist delete <name>   Remove a friend.');
    chat('  /friendlist accept <name>   Accept a pending request.');
    chat('  /friendlist decline <name>  Decline a pending request.');
    chat('  /friendlist refresh         Poll presence now.');
end

ashita.events.register('load', 'fl_load', function ()
    fl.charname = self_name();
    load();
    begin_sweep();
end);

ashita.events.register('unload', 'fl_unload', function ()
    if fl.dirty then save(); end
end);

ashita.events.register('command', 'fl_command', function (e)
    local args = e.command:args();
    if #args == 0 then return; end

    local c = args[1]:lower();

    if c == '/befriend' then
        e.blocked = true;
        if #args >= 2 then add_request(args[2]); else chat('Usage: /befriend <name>'); end
        return;
    end

    if c ~= '/friendlist' and c ~= '/flist' then return; end
    e.blocked = true;

    if #args == 1 then
        fl.visible = not fl.visible;
        fl.force_open = fl.visible;   -- a collapsed window reads as an empty friend list
        return;
    end

    local sub = args[2]:lower();
    local who = args[3];

    if sub == 'help' then
        print_help();
    elseif sub == 'add' or sub == 'invite' then
        if who then add_request(who); else chat('Usage: /friendlist add <name>'); end
    elseif sub == 'delete' or sub == 'del' or sub == 'remove' then
        if who then delete_friend(who); else chat('Usage: /friendlist delete <name>'); end
    elseif sub == 'accept' then
        if who then accept_request(who); else chat('Usage: /friendlist accept <name>'); end
    elseif sub == 'decline' or sub == 'reject' then
        if who then decline_request(who); else chat('Usage: /friendlist decline <name>'); end
    elseif sub == 'simulate' then
        -- Drive the handshake state machine directly: /friendlist simulate <name> <REQ|ACK|NAK|DEL>
        local tag = args[4] and args[4]:upper() or 'REQ';
        if who then handle_tag(who, '<FL' .. tag .. '>'); else chat('Usage: /friendlist simulate <name> <REQ|ACK|NAK|DEL>'); end
    elseif sub == 'selftest' then
        run_selftest();
    elseif sub == 'refresh' then
        begin_sweep();
        chat('Refreshing friend list...');
    else
        print_help();
    end
end);

ashita.events.register('text_in', 'fl_text_in', function (e)
    if e.injected then return; end
    local msg = e.message_modified or e.message or '';

    -- Handshake traffic rides on /tell. Swallow it so the marker never reaches the log.
    --
    -- Incoming tells arrive wrapped in colour/control bytes, so strip everything that is
    -- not printable ASCII before matching. Both directions carry the tag and must not be
    -- confused:
    --   outgoing echo :  ">>Name : <FLREQ>"
    --   incoming tell :  "Name>><FLREQ>"
    -- Matching the outgoing echo made the addon read our own request as one FROM the
    -- person we had just asked. Both caught live in world, 2026-08-17.
    local clean = msg:gsub('[^\32-\126]', '');
    if clean:match('<FL%u+>') and clean:match('^%s*>>') then
        e.blocked = true;   -- our own tell echoed back; hide the tag, act on nothing
        return;
    end
    local from, tag = clean:match('^%s*(%a+)%s*>>%s*(<FL%u+>)');
    if from ~= nil and tag ~= nil then
        e.blocked = true;
        handle_tag(from, tag);
        return;
    end
    -- "Your tell was not received. The recipient is currently away." while one of our
    -- presence pings is outstanding: that friend is offline. Swallow it so the poll
    -- stays invisible.
    if fl.querying ~= nil then
        local m = msg:lower();
        if m:match('tell was not received') or m:match('currently away') then
            if note_offline_reply() then e.blocked = true; end
        end
    end
end);

ashita.events.register('d3d_present', 'fl_present', function ()
    if fl.charname == nil then
        fl.charname = self_name();
        if fl.charname ~= nil then load(); begin_sweep(); end
    end

    pump_presence();

    if not fl.visible then return; end

    if fl.force_open then
        imgui.SetNextWindowCollapsed(false, ImGuiCond_Always);
        fl.force_open = false;
    end
    imgui.SetNextWindowSize({ 340, 380 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowPos({ 120, 120 }, ImGuiCond_FirstUseEver);
    if imgui.Begin('Friend List', true) then
        local online = 0;
        for _, v in pairs(fl.friends) do if v.online then online = online + 1; end end
        imgui.Text(string.format('%d friend%s, %d online', count(fl.friends), count(fl.friends) == 1 and '' or 's', online));
        imgui.Separator();

        if count(fl.pending) > 0 then
            imgui.TextColored({ 1.0, 0.85, 0.4, 1.0 }, 'Pending requests');
            for _, v in pairs(fl.pending) do
                imgui.Text('  ' .. v.name);
                imgui.SameLine();
                if imgui.SmallButton('Accept##' .. v.name) then accept_request(v.name); end
                imgui.SameLine();
                if imgui.SmallButton('Decline##' .. v.name) then decline_request(v.name); end
            end
            imgui.Separator();
        end

        if count(fl.friends) == 0 then
            imgui.TextDisabled('Your friend list is empty.');
            imgui.TextDisabled('Use /befriend <name> to add someone.');
        else
            for _, v in pairs(fl.friends) do
                if v.online then
                    imgui.TextColored({ 0.45, 0.95, 0.45, 1.0 }, '*');
                else
                    imgui.TextColored({ 0.45, 0.45, 0.45, 1.0 }, '*');
                end
                imgui.SameLine();
                imgui.Text(v.name);
                if v.online and #v.zone > 0 then
                    imgui.SameLine();
                    imgui.TextDisabled(string.format('%s %s  %s', v.job, v.lvl, v.zone));
                end
            end
        end

        if count(fl.outbound) > 0 then
            imgui.Separator();
            imgui.TextDisabled('Awaiting a reply from:');
            for _, v in pairs(fl.outbound) do imgui.TextDisabled('  ' .. v.name); end
        end
        imgui.End();
    end
end);
