-- Vanaguide :: guides/subjob.lua
-- Unlocking support jobs.  The completion test is the key item the quest awards, which is
-- the same on every server that runs the retail quest.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local G = require('core.guide')

G.register({
    name = 'Support jobs',
    author = 'Vanaguide',
    levels = '18+',
    desc = 'Unlock the ability to set a subjob.',
    steps = [[
C Reach level 18 on any job.|LV|18|
N The quest is taken in your own nation and finishes in the Horutoto Ruins.|
t Start the subjob quest with the quest giver in your home city.|
C Bring back the three Ancient Beastcoins the quest asks for.|
T Finish the quest. Your first subjob is unlocked.|
N Buy or farm a job you actually want to subjob before setting one.|
]],
})
