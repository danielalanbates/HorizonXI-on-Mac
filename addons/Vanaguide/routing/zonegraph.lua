-- Vanaguide :: routing/zonegraph.lua
-- Dijkstra over the zone graph, and the part that makes the graph honest: it learns.
--
-- The seed graph in data/travel.lua only covers what could be written down confidently.
-- Every time the player crosses a zone line, `learn()` records the pair, so the graph fills
-- in from actual play instead of from someone's memory of the map.  Learned edges are saved
-- with the character's settings and merged in on load.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local travel = require('data.travel')

local Z = { adj = {}, learned = {} }

local function link(a, edge)
    Z.adj[a] = Z.adj[a] or {}
    table.insert(Z.adj[a], edge)
end

local function build()
    Z.adj = {}
    for _, pair in ipairs(travel.walk) do
        local a, b = pair[1], pair[2]
        link(a, { to = b, cost = travel.WALK_COST, kind = 'walk' })
        link(b, { to = a, cost = travel.WALK_COST, kind = 'walk' })
    end
    for _, t in ipairs(travel.transit) do
        link(t.from, { to = t.to, cost = t.cost, kind = 'transit', via = t.via, pass = t.pass })
        if not t.oneway then
            -- Transit entries are written one direction each; nothing is mirrored here on
            -- purpose, because "the airship back" is a different counter in a different city.
        end
    end
    for key in pairs(Z.learned) do
        local a, b = key:match('^(%d+):(%d+)$')
        if a ~= nil then
            a, b = tonumber(a), tonumber(b)
            link(a, { to = b, cost = travel.WALK_COST, kind = 'walk', learned = true })
        end
    end
end

--- Record a zone transition the player just made.  Returns true if it was new.
function Z.learn(from, to)
    if from == nil or to == nil or from == to then return false end
    local key, back = from .. ':' .. to, to .. ':' .. from
    if Z.learned[key] then return false end
    -- Already in the seed graph?  Then there is nothing to learn.
    for _, e in ipairs(Z.adj[from] or {}) do
        if e.to == to then return false end
    end
    Z.learned[key] = true
    Z.learned[back] = true
    build()
    return true
end

function Z.load_learned(saved)
    Z.learned = saved or {}
    build()
end

function Z.save_learned() return Z.learned end

--- Cheapest route from one zone to another.
--- Returns a list of legs { from, to, kind, via, cost } and the total cost, or nil.
function Z.route(from, to)
    if from == nil or to == nil then return nil end
    if from == to then return {}, 0 end

    local dist, prev, visited = { [from] = 0 }, {}, {}
    while true do
        -- Small graph (a few hundred nodes): a linear scan for the nearest unvisited node
        -- is faster in practice than maintaining a heap, and much easier to read.
        local u, best = nil, math.huge
        for node, d in pairs(dist) do
            if not visited[node] and d < best then u, best = node, d end
        end
        if u == nil then return nil end
        if u == to then break end
        visited[u] = true
        for _, e in ipairs(Z.adj[u] or {}) do
            local nd = best + e.cost
            if dist[e.to] == nil or nd < dist[e.to] then
                dist[e.to] = nd
                prev[e.to] = { from = u, edge = e }
            end
        end
    end

    local legs, node = {}, to
    while node ~= from do
        local p = prev[node]
        if p == nil then return nil end
        table.insert(legs, 1, {
            from = p.from, to = node, kind = p.edge.kind,
            via = p.edge.via, cost = p.edge.cost, pass = p.edge.pass,
        })
        node = p.from
    end
    return legs, dist[to]
end

build()
return Z
