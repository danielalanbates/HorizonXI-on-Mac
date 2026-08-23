-- Vanaguide :: data/travel.lua
-- The seed travel graph: how you get from one zone to the next.
--
-- Two kinds of data live here.
--
--   walk[]      zone lines — two zones you can walk between.  Hand-authored for the base
--               world from common game knowledge, and DELIBERATELY incomplete: the client
--               keeps its zone-line geometry in the DATs, no server project publishes a
--               table of them, and guessing one is worse than not having it.  Whatever is
--               missing here the addon LEARNS: every time you zone, Routing/ZoneGraph
--               records the pair you just crossed and saves it (see docs/ROUTING.md).
--
--   transit[]   everything that is not a zone line — airships, ferries, the Kazham
--               shuttle, teleports.  These carry a `via` string, which is what the guide
--               window tells you to do, and a cost in seconds that reflects the real wait.
--
-- Costs are seconds of travel, honest order-of-magnitude, not measured.  Walking a zone is
-- treated as 90s; the router only ever compares them against each other.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local T = {}

T.WALK_COST = 90

-- Pairs are undirected unless a third value says otherwise.
T.walk = {
    -- San d'Oria
    { 230, 231 }, { 230, 232 }, { 231, 233 }, { 230, 101 }, { 231, 100 }, { 232, 100 },
    { 100, 102 }, { 100, 190 }, { 100, 140 }, { 140, 141 }, { 141, 142 },
    { 101, 104 }, { 102, 193 }, { 102, 103 }, { 104, 105 }, { 104, 149 },

    -- Bastok
    { 234, 235 }, { 235, 236 }, { 234, 237 }, { 234, 172 },
    { 234, 107 }, { 235, 106 }, { 236, 107 },
    { 106, 109 }, { 107, 108 }, { 107, 191 }, { 106, 143 },
    { 108, 103 }, { 109, 110 }, { 109, 147 }, { 110, 197 }, { 110, 200 },

    -- Windurst
    { 238, 239 }, { 238, 241 }, { 238, 240 }, { 239, 242 },
    { 238, 115 }, { 239, 115 }, { 240, 116 }, { 241, 116 },
    { 115, 117 }, { 116, 119 }, { 115, 194 }, { 117, 118 }, { 117, 151 },
    { 119, 120 }, { 119, 145 }, { 118, 123 },

    -- Jeuno and the middle lands
    { 243, 244 }, { 244, 245 }, { 245, 246 },
    { 105, 245 }, { 110, 245 }, { 120, 245 }, { 126, 246 },
    { 126, 157 }, { 157, 158 }, { 157, 184 },
    { 120, 121 }, { 121, 122 }, { 105, 195 }, { 111, 112 }, { 111, 105 },
    { 112, 161 }, { 161, 162 }, { 162, 165 },

    -- Southern continent
    { 123, 124 }, { 124, 250 }, { 124, 159 }, { 250, 252 },
    { 125, 247 }, { 125, 114 }, { 114, 174 }, { 125, 208 },
    { 103, 248 }, { 118, 249 },
}

-- Non-walking links.  `from`/`to` are zone ids, `via` is the instruction shown to the
-- player, `cost` is seconds including a typical wait, `oneway` marks a link that only
-- works in the stated direction.
T.transit = {
    -- Ferries
    { from = 248, to = 249, via = 'Ferry from Selbina to Mhaura', cost = 600 },
    { from = 249, to = 248, via = 'Ferry from Mhaura to Selbina', cost = 600 },

    -- Airships (all four need an Airship Pass; the router says so when it uses one)
    { from = 246, to = 232, via = 'Airship to San d\'Oria (Port Jeuno counter)', cost = 420, pass = true },
    { from = 232, to = 246, via = 'Airship to Jeuno (Port San d\'Oria counter)', cost = 420, pass = true },
    { from = 246, to = 236, via = 'Airship to Bastok (Port Jeuno counter)', cost = 420, pass = true },
    { from = 236, to = 246, via = 'Airship to Jeuno (Port Bastok counter)', cost = 420, pass = true },
    { from = 246, to = 240, via = 'Airship to Windurst (Port Jeuno counter)', cost = 420, pass = true },
    { from = 240, to = 246, via = 'Airship to Jeuno (Port Windurst counter)', cost = 420, pass = true },
    { from = 246, to = 250, via = 'Airship to Kazham (Port Jeuno counter)', cost = 480, pass = true },
    { from = 250, to = 246, via = 'Airship to Jeuno (Kazham counter)', cost = 480, pass = true },
}

-- Teleport destinations, offered when the player (or a passing mage) can cast them.
-- Not wired into the graph by default; the router adds them only when
-- settings.routing.use_teleports is on and the spell is known.
T.teleport = {
    { spell = 'Teleport-Holla', to = 102, cost = 30 },
    { spell = 'Teleport-Dem',   to = 108, cost = 30 },
    { spell = 'Teleport-Mea',   to = 119, cost = 30 },
    { spell = 'Teleport-Yhoat', to = 124, cost = 30 },
    { spell = 'Teleport-Altep', to = 125, cost = 30 },
    { spell = 'Teleport-Vahzl', to = 112, cost = 30 },
}

return T
