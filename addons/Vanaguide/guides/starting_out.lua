-- Vanaguide :: guides/starting_out.lua
-- The first hour, for any nation.  Deliberately written without coordinates: every step
-- here is either checked off by hand or answered by the game, and a made-up POS would send
-- the arrow somewhere wrong.  Fill coordinates in from play with /vg mark — see
-- docs/GUIDE_FORMAT.md.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local G = require('core.guide')

G.register({
    name = 'Starting out',
    author = 'Vanaguide',
    levels = '1-10',
    desc = 'What to do between stepping off the boat and level 10, in any nation.',
    steps = [[
N Welcome. Tick a step off with Done, or let the game tick it for you.|N|Steps that the server can confirm complete themselves.|
t Talk to your nation's Gate Guard and take Signet before leaving town.|N|Signet is what makes low-level fighting outside worth doing.|
t Ask the Gate Guard for the Adventurer's Certificate and your first national mission.|
C Reach level 5 in your starting job.|LV|5|
t Buy a weapon you can actually skill up, and food if you can afford it.|
C Reach level 10.|LV|10|
N At 10 you can take the airship pass quests and start moving between cities.|
]],
})
