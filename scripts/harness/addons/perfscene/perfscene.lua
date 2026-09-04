--[[
perfscene: run a fixed, reproducible in-world scenario on the local test server.

Loaded by menu-run.py through Ashita's boot script. It waits for the character to be in the
world, then walks a list of steps at a fixed cadence: GM commands to keep the character alive
and load the scene (weather, mobs, teleports), plus fps settings. Every step and every zone
change is appended to a markers file in the capture directory so the recorder can slice the
frame log by scenario phase without anyone watching the screen.

Environment (set by the launcher for one run, read through os.getenv):
  PERFSCENE_MARKERS   file to append JSON-lines markers to (required, otherwise idle)
  PERFSCENE_SCENARIO  scenario name from the table below (default: city)
  PERFSCENE_START     seconds after zone-in before the first step (default 8)

Commands:
  /perfscene run <name>    start a scenario by hand
  /perfscene stop          stop the running scenario
  /perfscene list          list scenarios
--]]

addon.name    = 'perfscene';
addon.author  = 'HorizonXI-on-Mac';
addon.version = '1.0';
addon.desc    = 'Reproducible in-world performance scenarios for the local test server.';
addon.link    = 'https://github.com/danielalanbates/HorizonXI-on-Mac';

require('common');
local chat = require('chat');

-- Each step is { delay_seconds, command_or_function, label }. Commands starting with '!' are
-- LandSandBoat GM commands sent as chat; '/' commands go to Ashita. Zone ids: North Gustaberg
-- 106, Bastok Markets 235, Batallia Downs 105, Rolanberry Fields 110. Weather ids follow
-- xi.weather (6 rain, 7 squall, 12 snow, 13 blizzards, 15 thunderstorms).
local scenarios = {
    -- The settled-city baseline: stand in the busiest Bastok zone at uncapped FPS.
    city = {
        { 0,  '!godmode',                 'godmode' },
        { 2,  '/fps 0',                   'fps uncapped' },
        { 2,  '/drawdistance setworld 20','draw distance max' },
        { 2,  '/drawdistance setmob 20',  'entity draw max' },
        { 3,  '!zone 235',                'zone bastok markets' },
        { 25, 'settle',                   'city settled' },
        { 20, '!zone 234',                'zone bastok mines' },
        { 25, 'settle',                   'mines settled' },
        { 20, 'done',                     'done' },
    },
    -- Outdoors with weather and a crowd of spawned mobs around the player.
    field = {
        { 0,  '!godmode',                 'godmode' },
        { 2,  '/fps 0',                   'fps uncapped' },
        { 2,  '/drawdistance setworld 20','draw distance max' },
        { 2,  '/drawdistance setmob 20',  'entity draw max' },
        { 3,  '!zone 106',                'zone north gustaberg' },
        { 25, 'settle',                   'field settled' },
        { 3,  '!setweather 15',           'thunderstorms' },
        { 15, 'settle',                   'weather settled' },
        { 3,  'spawn 40',                 'spawn 40 mobs' },
        { 25, 'settle',                   'crowd settled' },
        { 3,  '!zone 235',                'zone bastok markets' },
        { 25, 'settle',                   'city after crowd' },
        { 15, 'done',                     'done' },
    },
};

local state = {
    running   = nil,     -- scenario table
    index     = 0,
    next_at   = 0,
    markers   = os.getenv('PERFSCENE_MARKERS'),
    auto      = os.getenv('PERFSCENE_SCENARIO'),
    start     = tonumber(os.getenv('PERFSCENE_START') or '8'),
    in_world  = false,
    world_at  = 0,
    zone      = -1,
    file      = nil,
};

local function mark(label, extra)
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    local line = string.format('{"epoch": %.3f, "label": "%s", "zone": %d%s}',
        os.time() + (os.clock() % 1), (label:gsub('"', "'")), zone, extra or '');
    if (state.markers ~= nil) then
        local f = io.open(state.markers, 'a');
        if (f ~= nil) then f:write(line, '\n'); f:close(); end
    end
    print(chat.header(addon.name):append(chat.message(label)));
end

local function send(cmd)
    -- Mode 1: as if typed in the chat box. GM commands are plain text that begins with '!'.
    AshitaCore:GetChatManager():QueueCommand(1, cmd);
end

-- Spawn N copies of the nearest spawnable mob ids of this zone at the player's position.
-- LandSandBoat assigns mob ids per zone as 0x1000000 | zone << 12 | slot; !mobhere moves a
-- spawn to the player. Slots that hold no mob are rejected by the server and skipped.
local function spawn_crowd(n)
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
    local base = 0x1000000 + zone * 0x1000;
    for slot = 0, n - 1 do
        send(string.format('!mobhere %d 1', base + slot));
    end
end

local function step()
    local sc = state.running;
    if (sc == nil) then return; end
    state.index = state.index + 1;
    local s = sc[state.index];
    if (s == nil) then
        state.running = nil;
        mark('scenario finished');
        return;
    end
    local cmd, label = s[2], s[3];
    if (cmd == 'settle') then
        mark(label);
    elseif (cmd == 'done') then
        mark(label);
        state.running = nil;
        return;
    elseif (cmd:sub(1, 6) == 'spawn ') then
        spawn_crowd(tonumber(cmd:sub(7)) or 20);
        mark(label);
    else
        send(cmd);
        mark(label, string.format(', "command": "%s"', (cmd:gsub('"', "'"))));
    end
    -- Each step's delay is the pause *before* it runs, so schedule the next one now.
    local nxt = sc[state.index + 1];
    if (nxt ~= nil) then state.next_at = os.clock() + nxt[1]; end
end

local function start(name)
    local sc = scenarios[name];
    if (sc == nil) then
        print(chat.header(addon.name):append(chat.error('unknown scenario: ' .. tostring(name))));
        return;
    end
    state.running = sc; state.index = 0;
    state.next_at = os.clock() + sc[1][1];
    mark('scenario start: ' .. name);
end

ashita.events.register('load', 'perfscene_load', function ()
    if (state.markers ~= nil) then
        mark('addon loaded');
    end
end);

ashita.events.register('command', 'perfscene_command', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/perfscene') then return; end
    e.blocked = true;
    if (#args >= 3 and args[2] == 'run') then start(args[3]);
    elseif (#args >= 2 and args[2] == 'stop') then state.running = nil; mark('scenario stopped');
    elseif (#args >= 2 and args[2] == 'list') then
        for k, _ in pairs(scenarios) do print(chat.header(addon.name):append(chat.message(k))); end
    end
end);

-- Zone-in detection: the first time the party zone is a real zone and the player is not
-- zoning, the character is in the world. Every later change of zone is a marker too.
ashita.events.register('d3d_present', 'perfscene_present', function ()
    local mem = AshitaCore:GetMemoryManager();
    local zone = mem:GetParty():GetMemberZone(0);
    local zoning = mem:GetPlayer():GetIsZoning() ~= 0;
    if (zone ~= state.zone and zone > 0 and not zoning) then
        local first = not state.in_world;
        state.zone = zone;
        state.in_world = true;
        mark(first and 'in world' or 'zoned', string.format(', "zone_id": %d', zone));
        if (first) then
            state.world_at = os.clock();
        end
    end
    if (state.in_world and state.auto ~= nil and state.running == nil and not state.auto_done) then
        if (os.clock() - state.world_at >= state.start) then
            state.auto_done = true;
            start(state.auto);
        end
    end
    if (state.running ~= nil and os.clock() >= state.next_at) then
        step();
    end
end);
