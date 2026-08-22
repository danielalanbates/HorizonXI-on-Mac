-- Vanaguide :: core/conditions.lua
-- Is this step done?  One function, no side effects, so the offline harness can drive it
-- with a fake world and get exactly what the client would give.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local U     = require('core.util')
local story = require('core.story')

local C = {}

--- The player's world, gathered once per evaluation.  `w` may be supplied by the harness.
function C.world()
    local x, z, y = U.position()
    return {
        zone = U.zone(),
        x = x, z = z, y = y,
        level = U.level(),
        rank = U.rank(),
        nation = U.nation(),
        story = story,
        has_key_item = U.has_key_item,
        has_spell = U.has_spell,
        item_count = U.item_count,
        job_level = U.job_level,
    }
end

--- True when the step has a condition the game can answer for us.
function C.is_automatic(step)
    return step.mission ~= nil or step.quest ~= nil or step.quest_accept ~= nil
        or step.key_item ~= nil or step.item ~= nil or step.level ~= nil
        or step.job ~= nil or step.rank ~= nil or step.spell ~= nil
end

--- Distance to the step's marker, or nil when the step has no place or the player is not
--- in its zone.  Used by the arrow and by proximity completion.
function C.distance(step, w)
    if step.pos == nil or w.zone == nil or w.x == nil then return nil end
    if step.zone ~= nil and step.zone ~= w.zone then return nil end
    return U.dist(w.x, w.z, step.pos.x, step.pos.z)
end

--- Has this step been satisfied?
function C.done(step, w)
    w = w or C.world()

    if step.mission ~= nil then
        return w.story.mission_done(step.mission.area, step.mission.id)
    end
    if step.quest ~= nil then
        return w.story.quest_done(step.quest.area, step.quest.id)
    end
    if step.quest_accept ~= nil then
        return w.story.quest_active(step.quest_accept.area, step.quest_accept.id)
            or w.story.quest_done(step.quest_accept.area, step.quest_accept.id)
    end
    if step.key_item ~= nil then return w.has_key_item(step.key_item) == true end
    if step.item ~= nil then return w.item_count(step.item.id) >= (step.item.count or 1) end
    if step.level ~= nil then return (w.level or 0) >= step.level end
    if step.job ~= nil then return w.job_level(step.job.id) >= step.job.level end
    if step.rank ~= nil then return (w.rank or 0) >= step.rank end
    if step.spell ~= nil then return w.has_spell(step.spell) == true end

    -- No automatic condition.  A "run to" step completes by arriving; anything else waits
    -- for the player to tick it off, because guessing would march the guide past a step
    -- the player has not actually done.
    if step.kind == 'run' or step.kind == 'travel' then
        local d = C.distance(step, w)
        return d ~= nil and d <= (step.pos and step.pos.r or 10)
    end
    return false
end

return C
