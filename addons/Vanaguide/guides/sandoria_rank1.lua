-- Vanaguide :: guides/sandoria_rank1.lua
-- San d'Oria, Rank 1.  SEED CONTENT: the step text and the zones are right, the mission
-- ids are the client's own numbering and have not yet been confirmed against a live
-- character (see docs/VERIFICATION.md).  If a step ticks itself at the wrong moment, that
-- is the id, and it is a one-line fix.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local G = require('core.guide')

G.register({
    name = "San d'Oria — Rank 1",
    author = 'Vanaguide',
    nation = 'sandoria',
    levels = '1-10',
    desc = "The first rank of San d'Oria's mission line.",
    steps = [[
t Take a mission from the Gate Guard in Southern San d'Oria.|Z|230|
C Mission 1-1: Smash the Orcish Scouts. Kill orcs in Ghelsba Outpost.|M|sandoria,1|Z|140|
T Report back to the Gate Guard and take your reward.|Z|230|
t Take Mission 1-2 from the Gate Guard.|Z|230|
C Mission 1-2: Bat Hunt. Collect the bat wings in Kings Ranperre's Tomb.|M|sandoria,2|Z|190|
T Report back to the Gate Guard.|Z|230|
t Take Mission 1-3 from the Gate Guard.|Z|230|
C Mission 1-3: The Rescue. Fort Ghelsba.|M|sandoria,3|Z|141|
T Report back, and you are Rank 2.|Z|230|RANK|2|
]],
})
