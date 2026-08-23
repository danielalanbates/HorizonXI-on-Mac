--[[
* Vanaguide -- a guided-walkthrough addon for FINAL FANTASY XI (Ashita v4).
*
* Shows the next thing to do, ticks it off when the server says you have done it, and
* points an arrow at where to go, routing across zones when "there" is a continent away.
*
* Commands:
*   /vanaguide, /vg            show or hide the guide window
*   /vg guides                 pick a guide
*   /vg next | back | skip     move through the current guide
*   /vg route                  explain the route to the current step
*   /vg mark <name>            record where you are standing into marks.txt (guide authoring)
*   /vg arrow flip             flip the arrow's rotation if it points the wrong way
*   /vg arrow nudge <degrees>  rotate the arrow by a fixed offset
*   /vg reset                  start the current guide again
*
* Copyright (c) 2026 Bates LLC.  All rights reserved.
* https://batesai.org  ·  help@batesai.org
--]]

addon.name    = 'Vanaguide';
addon.author  = 'Bates LLC';
addon.version = '0.1.0';
addon.desc    = 'Step-by-step quest and mission guides with a routing arrow.';
addon.link    = 'https://batesai.org';

require('common');

-- LuaJIT's mcode patcher faults inside Ashita 4.3's Addons.dll on this project's Wine
-- build; every addon here turns the JIT off for the same reason.  See
-- HorizonXI-on-Mac docs/ADDONS.md.
if (jit ~= nil and jit.off ~= nil) then jit.off(true, true); end

-- Ashita puts the addon's own folder on package.path, but say it explicitly: a path that
-- silently lacks it turns every require below into a confusing "module not found".
do
    local ok, root = pcall(function () return AshitaCore:GetInstallPath(); end);
    if (ok and root ~= nil and root ~= '') then
        root = root:gsub('[\\/]$', '');
        package.path = ('%s\\addons\\Vanaguide\\?.lua;%s'):format(root, package.path);
    end
end

local settings = require('settings');

local U      = require('core.util');
local story  = require('core.story');
local G      = require('core.guide');
local C      = require('core.conditions');
local P      = require('core.progress');
local graph  = require('routing.zonegraph');
local R      = require('routing.router');
local Arrow  = require('ui.arrow');
local Window = require('ui.window');

require('guides.init');

local default_settings = T{
    guide = '',
    progress = T{},          -- [guide name] = { index, checked, skipped }
    learned = T{},           -- zone lines this character has crossed
    arrow = T{ visible = true, calibration = 1, offset = 0 },
    window = T{ visible = true },
};

local vg = {
    settings = settings.load(default_settings),
    last_zone = nil,
    last_advance = 0,
    was_logged_in = false,
    d3d8 = nil,
};

local function save_progress()
    if (P.guide == nil) then return; end
    vg.settings.guide = P.guide.name;
    vg.settings.progress[P.guide.name] = P.save_state();
    vg.settings.learned = graph.save_learned();
    settings.save();
end

local function load_guide(name)
    local guide = G.get(name);
    if (guide == nil) then
        U.print('no guide named "' .. tostring(name) .. '"');
        return false;
    end
    P.set_guide(guide, vg.settings.progress[name]);
    save_progress();
    U.print(('loaded "%s" (%d steps, on step %d)'):format(guide.name, P.count(), P.index));
    return true;
end

local function apply_settings(s)
    if (s ~= nil) then vg.settings = s; end
    graph.load_learned(vg.settings.learned);
    Arrow.calibration = vg.settings.arrow.calibration or 1;
    Arrow.offset = vg.settings.arrow.offset or 0;
    Window.open[1] = vg.settings.window.visible ~= false;
    if (vg.settings.guide ~= nil and vg.settings.guide ~= '') then
        load_guide(vg.settings.guide);
    end
end

settings.register('settings', 'settings_update', apply_settings);

--- Guide authoring helper: write where the player is standing to a file the guide format
--- can be pasted from.  Coordinates in guides should come from somebody actually standing
--- there, which is the whole reason this exists.
local function mark(name)
    local x, z, y = U.position();
    local zone = U.zone();
    if (x == nil or zone == nil) then U.print('not in the world'); return; end
    local line = ('%s|Z|%d|POS|%.1f,%.1f,10|N|%s, y=%.1f|')
        :format(name or 'mark', zone, x, z, U.zone_name(zone), y or 0);
    local path = ('%s\\addons\\Vanaguide\\marks.txt'):format(AshitaCore:GetInstallPath():gsub('[\\/]$', ''));
    local f = io.open(path, 'a');
    if (f ~= nil) then f:write(line, '\n'); f:close(); end
    U.print(line);
end

ashita.events.register('load', 'vg_load', function ()
    apply_settings(nil);
    U.print(('v%s loaded. /vg for the window, /vg guides to pick one.'):format(addon.version));
end);

ashita.events.register('unload', 'vg_unload', function ()
    save_progress();
    settings.save();
end);

ashita.events.register('packet_in', 'vg_packet_in', function (e)
    story.on_packet(e.id, e.data, e.size);
end);

ashita.events.register('command', 'vg_command', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/vanaguide', '/vg')) then return; end
    e.blocked = true;

    local sub = (#args > 1) and args[2]:lower() or '';

    if (sub == '') then
        Window.toggle();
        vg.settings.window.visible = Window.open[1];
        settings.save();
        return;
    end

    if (sub == 'guides' or sub == 'list') then
        Window.picker[1] = true;
        for _, g in ipairs(G.list()) do
            U.print(('  %s  (%s)'):format(g.name, g.levels or 'any level'));
        end
        return;
    end

    if (sub == 'load' and #args > 2) then
        load_guide(table.concat({ unpack(args, 3) }, ' '));
        return;
    end

    if (sub == 'next' or sub == 'done') then P.check(); P.advance(); save_progress(); return; end
    if (sub == 'skip') then P.skip(); P.advance(); save_progress(); return; end
    if (sub == 'back') then P.back(); save_progress(); return; end
    if (sub == 'reset') then
        if (P.guide ~= nil) then
            vg.settings.progress[P.guide.name] = nil;
            P.set_guide(P.guide, nil);
            save_progress();
            U.print('progress reset');
        end
        return;
    end

    if (sub == 'route') then
        local step = P.step();
        if (step == nil or step.zone == nil) then U.print('the current step has no place'); return; end
        local legs = graph.route(U.zone(), step.zone);
        U.print(R.describe(legs));
        return;
    end

    if (sub == 'mark') then
        mark(#args > 2 and table.concat({ unpack(args, 3) }, ' ') or nil);
        return;
    end

    if (sub == 'arrow') then
        local what = (#args > 2) and args[3]:lower() or '';
        if (what == 'flip') then
            Arrow.calibration = -Arrow.calibration;
            vg.settings.arrow.calibration = Arrow.calibration;
        elseif (what == 'nudge' and #args > 3) then
            local deg = tonumber(args[4]) or 0;
            Arrow.offset = Arrow.offset + math.rad(deg);
            vg.settings.arrow.offset = Arrow.offset;
        elseif (what == 'on' or what == 'off') then
            vg.settings.arrow.visible = (what == 'on');
        end
        settings.save();
        U.print(('arrow: %s, calibration %d, offset %.0f degrees')
            :format(vg.settings.arrow.visible and 'on' or 'off',
                    Arrow.calibration, math.deg(Arrow.offset)));
        return;
    end

    U.print('commands: guides, load <name>, next, back, skip, reset, route, mark, arrow');
end);

ashita.events.register('d3d_present', 'vg_present', function ()
    if (not U.logged_in()) then
        -- Back at the character select.  The quest flags belong to whoever was logged in,
        -- and keeping them would silently mark the next character's steps done.
        if (vg.was_logged_in) then
            story.reset();
            vg.was_logged_in = false;
            vg.last_zone = nil;
        end
        return;
    end
    vg.was_logged_in = true;

    local w = C.world();
    w.yaw = U.heading();

    -- Learn the zone line we just crossed.  This is what fills in the travel graph.
    if (w.zone ~= nil and w.zone ~= vg.last_zone) then
        if (vg.last_zone ~= nil and graph.learn(vg.last_zone, w.zone)) then
            vg.settings.learned = graph.save_learned();
            settings.save();
        end
        vg.last_zone = w.zone;
    end

    -- Advancing walks the whole remaining guide in the worst case; once a second is plenty.
    local now = os.time();
    if (now ~= vg.last_advance) then
        vg.last_advance = now;
        if (P.advance(w) > 0) then save_progress(); end
    end

    Window.draw(w, function (name) load_guide(name); end);

    if (vg.settings.arrow.visible ~= false and P.guide ~= nil) then
        local step = P.step();
        if (step ~= nil) then
            local rec = R.recommend(step, w);
            local ok, vp = pcall(function ()
                if (vg.d3d8 == nil) then vg.d3d8 = require('d3d8'); end
                local res, v = vg.d3d8.get_device():GetViewport();
                if (res == 0) then return v; end
                return nil;
            end);
            if (ok and vp ~= nil) then Arrow.set_viewport(vp.Width, vp.Height); end

            if (rec.mode == 'here' and rec.bearing ~= nil) then
                Arrow.draw(rec.bearing, rec.distance,
                    ('%.0f yalms'):format(rec.distance or 0), step.text);
            elseif (rec.mode == 'travel') then
                Arrow.draw(0, nil, rec.text, U.zone_name(rec.destination));
            end
        end
    end
end);
