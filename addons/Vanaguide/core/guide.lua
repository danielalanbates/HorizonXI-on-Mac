-- Vanaguide :: core/guide.lua
-- The guide format and its parser.
--
-- A guide is a list of steps written one per line.  The line starts with a one-letter verb
-- and the text shown to the player, and everything after it is |TAG|value| pairs:
--
--     t Ask the gate guard about missions|Z|230|POS|-140,120,8|N|He is by the fountain.|
--     A Mission 1-1: Save the Children|M|sandoria,2|Z|230|
--     K Kill orcs until you have three tusks|IT|1122,3|Z|140|
--
-- Verbs:  A accept · T turn in · C complete an objective · K kill · B buy · t talk
--         R run to · U use an item · F travel · N note only · L reach a level
--
-- Tags:   Z    zone (id, or a name from data/zone_names.lua)
--         POS  x,z[,radius]  — where in the zone; radius defaults to 10 yalms
--         M    area,id  — done when that mission is finished
--         Q    area,id  — done when that quest is completed
--         QA   area,id  — done when that quest is *accepted* (for A steps)
--         KI   id       — done when you hold that key item
--         IT   id[,n]   — done when you hold n of that item (default 1)
--         LV   n        — done at level n
--         JOB  job,lvl  — done when that job reaches that level
--         RANK n        — done at that nation rank
--         SP   id       — done when you know that spell
--         N    note shown under the step
--         FIXED         — never skipped automatically, even if its condition already holds
--
-- A step with no completion tag is a manual step: it waits for a click, or for the player
-- to walk into its POS radius if it has one.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local zones = require('data.zone_names')

local G = { guides = {}, order = {} }

local VERBS = {
    A = 'accept', T = 'turnin', C = 'complete', K = 'kill', B = 'buy',
    t = 'talk', R = 'run', U = 'use', F = 'travel', N = 'note', L = 'level',
}

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function numbers(s)
    local out = {}
    for n in s:gmatch('-?%d+%.?%d*') do out[#out + 1] = tonumber(n) end
    return out
end

--- Parse one line into a step, or nil (blank lines and -- comments).
function G.parse_line(line, lineno)
    line = trim(line or '')
    if line == '' or line:sub(1, 2) == '--' then return nil end

    local head = line:match('^([^|]*)') or ''
    local verb = head:sub(1, 1)
    local kind = VERBS[verb]
    if kind == nil then
        return nil, ('line %d: unknown verb %q'):format(lineno or 0, verb)
    end

    local step = { kind = kind, text = trim(head:sub(2)), line = lineno }

    for tag, value in line:gmatch('|(%u+)|([^|]*)') do
        value = trim(value)
        if tag == 'Z' then
            step.zone = tonumber(value) or zones.find(value)
            if step.zone == nil then
                return nil, ('line %d: unknown zone %q'):format(lineno or 0, value)
            end
        elseif tag == 'POS' then
            local n = numbers(value)
            if #n < 2 then return nil, ('line %d: POS needs x,z'):format(lineno or 0) end
            step.pos = { x = n[1], z = n[2], r = n[3] or 10 }
        elseif tag == 'M' or tag == 'Q' or tag == 'QA' then
            local area, id = value:match('^([%w_]+)%s*,%s*(%d+)$')
            if area == nil then
                return nil, ('line %d: %s needs area,id'):format(lineno or 0, tag)
            end
            step[tag == 'M' and 'mission' or (tag == 'Q' and 'quest' or 'quest_accept')] =
                { area = area, id = tonumber(id) }
        elseif tag == 'KI' then
            step.key_item = tonumber(value)
        elseif tag == 'IT' then
            local n = numbers(value)
            step.item = { id = n[1], count = n[2] or 1 }
        elseif tag == 'LV' then
            step.level = tonumber(value)
        elseif tag == 'JOB' then
            local n = numbers(value)
            step.job = { id = n[1], level = n[2] or 1 }
        elseif tag == 'RANK' then
            step.rank = tonumber(value)
        elseif tag == 'SP' then
            step.spell = tonumber(value)
        elseif tag == 'N' then
            step.note = value
        elseif tag == 'FIXED' then
            step.fixed = true
        end
    end

    -- The "N" verb is a note with no completion of its own; make that explicit rather than
    -- leaving a step the player can never satisfy sitting at the top of the window.
    if step.kind == 'note' then step.manual = true end
    if step.zone == nil and step.pos ~= nil then
        return nil, ('line %d: POS without Z'):format(lineno or 0)
    end
    return step
end

--- Parse a whole guide body.  Returns steps, errors (errors is empty on a clean parse).
function G.parse(body)
    local steps, errs = {}, {}
    local n = 0
    for line in tostring(body or ''):gmatch('[^\r\n]*') do
        n = n + 1
        local step, err = G.parse_line(line, n)
        if err ~= nil then errs[#errs + 1] = err end
        if step ~= nil then
            step.index = #steps + 1
            steps[#steps + 1] = step
        end
    end
    return steps, errs
end

--- Register a guide.  `def.steps` may be the raw body or an already-parsed list.
function G.register(def)
    assert(type(def) == 'table' and def.name, 'a guide needs a name')
    local steps, errs = def.steps, {}
    if type(steps) ~= 'table' then steps, errs = G.parse(steps) end
    local guide = {
        name = def.name,
        author = def.author or 'unknown',
        nation = def.nation,
        levels = def.levels,
        desc = def.desc,
        steps = steps,
        errors = errs,
    }
    if G.guides[guide.name] == nil then G.order[#G.order + 1] = guide.name end
    G.guides[guide.name] = guide
    return guide
end

function G.get(name) return G.guides[name] end

function G.list()
    local out = {}
    for _, name in ipairs(G.order) do out[#out + 1] = G.guides[name] end
    return out
end

return G
