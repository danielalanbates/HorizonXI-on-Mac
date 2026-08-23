-- Vanaguide :: routing/router.lua
-- Turns "the step is over there" into "here is the next thing to do".
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local U      = require('core.util')
local graph  = require('routing.zonegraph')

local R = {}

--- What should the arrow point at, and what should the window say under it?
--- Returns a table:
---   mode  'here'    the step is in this zone — bearing/distance are set
---         'travel'  you are somewhere else — `via` says how to start moving
---         'unknown' the step has no place, or no route exists
function R.recommend(step, w)
    if step == nil then return { mode = 'unknown', text = 'No step.' } end
    if w.zone == nil then return { mode = 'unknown', text = 'Not in the world yet.' } end

    local zone = step.zone
    if zone == nil then
        return { mode = 'unknown', text = step.note or 'Do this wherever you are.' }
    end

    if zone == w.zone then
        if step.pos == nil or w.x == nil then
            return { mode = 'here', text = 'In ' .. U.zone_name(zone), distance = nil }
        end
        local d = U.dist(w.x, w.z, step.pos.x, step.pos.z)
        local bearing = U.relative_bearing(w.x, w.z, w.yaw or 0, step.pos.x, step.pos.z)
        return {
            mode = 'here', distance = d, bearing = bearing,
            text = ('%.0f yalms'):format(d),
            arrived = d <= (step.pos.r or 10),
        }
    end

    local legs, cost = graph.route(w.zone, zone)
    if legs == nil then
        return {
            mode = 'unknown',
            text = ('Go to %s — no route known from %s yet.')
                :format(U.zone_name(zone), U.zone_name(w.zone)),
        }
    end
    local first = legs[1]
    local text
    if first == nil then
        text = 'You are there.'
    elseif first.kind == 'transit' then
        text = first.via
    else
        text = ('Zone into %s'):format(U.zone_name(first.to))
    end
    return {
        mode = 'travel', legs = legs, eta = cost, text = text,
        destination = zone,
        hops = #legs,
    }
end

--- A one-line description of a whole route, for `/vg route`.
function R.describe(legs)
    if legs == nil then return 'no route' end
    if #legs == 0 then return 'you are already there' end
    local out = {}
    for _, leg in ipairs(legs) do
        if leg.kind == 'transit' then
            out[#out + 1] = leg.via
        else
            out[#out + 1] = U.zone_name(leg.to)
        end
    end
    return table.concat(out, ' -> ')
end

return R
