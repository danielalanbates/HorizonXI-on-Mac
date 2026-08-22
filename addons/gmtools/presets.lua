--[[
    GM Tools v1.0.4 - Preset Definitions
    Default presets for Restore Defaults. Custom presets are stored in SQLite.
]]--

require 'common';

local presets = {};

presets.defaults = T{
    {
        name = 'Full Dev Setup',
        desc = 'setupchar (all jobs 99 mastered, skills, key items) + all content unlocks + gil + inventory',
        commands = T{
            -- Custom server command: all 22 jobs to 99 mastered, skills capped,
            -- key items (LIMIT_BREAKER, JOB_BREAKER), subjob unlocked (~25s batched)
            '!setupchar',
            -- Content unlocks (not covered by setupchar)
            '!addallspells',
            '!addalltrusts',
            '!addallweaponskills',
            '!addallmaps',
            '!addallmounts',
            '!addallattachments',
            '!addallmonstrosity',
            '!addallatma',
            -- Gil and inventory
            '!setgil 10000000',
            '!setbag 80',
        },
    },

    -- LootScope Testing Presets

    {
        name = 'Chest & Coffer Kit',
        desc = 'Keys for chest/coffer testing (Garlaige, Oztroja, Crawlers, Eldieme). Warps to Garlaige Citadel.',
        commands = T{
            -- Universal keys (12 each)
            '!additem 1115 12',  -- Skeleton Key (best, +20% success)
            '!additem 1023 12',  -- Living Key (+15% success)
            '!additem 1022 12',  -- Thief\'s Tools (+10% success)
            -- Garlaige Citadel (zone 200) keys
            '!additem 1041',     -- Garlaige Chest Key
            '!additem 1047',     -- Garlaige Coffer Key
            -- Castle Oztroja (zone 151) keys
            '!additem 1035',     -- Oztroja Chest Key
            '!additem 1044',     -- Oztroja Coffer Key
            -- Crawler\'s Nest (zone 197) keys
            '!additem 1040',     -- Nest Chest Key
            '!additem 1045',     -- Nest Coffer Key
            -- Eldieme Necropolis (zone 195) keys
            '!additem 1039',     -- Eldieme Chest Key
            '!additem 1046',     -- Eldieme Coffer Key
            -- Warp to Garlaige Citadel
            '!zone 200',
        },
    },
    {
        name = 'BCNM Orb Kit',
        desc = 'All BCNM orbs, KSNM orbs, and seals. Warps to Horlais Peak.',
        commands = T{
            -- Standard BCNM orbs (one of each level cap)
            '!additem 1551',     -- Cloudy Orb (Lv20 cap)
            '!additem 1552',     -- Sky Orb (Lv30 cap)
            '!additem 1131',     -- Star Orb (Lv40 cap)
            '!additem 1177',     -- Comet Orb (Lv50 cap)
            '!additem 1130',     -- Moon Orb (Lv60 cap)
            -- KSNM orbs (no level cap)
            '!additem 1175',     -- Clotho Orb
            '!additem 1178',     -- Lachesis Orb
            '!additem 1180',     -- Atropos Orb
            '!additem 1553',     -- Themis Orb
            -- Seals and crests
            '!additem 1126 99',  -- Beastmen\'s Seal
            '!additem 1127 99',  -- Kindred\'s Seal
            '!additem 2955 99',  -- Kindred\'s Crest
            '!additem 2956 99',  -- High Kindred\'s Crest
            '!additem 2957 99',  -- Sacred Kindred\'s Crest
            -- Warp to Horlais Peak
            '!zone 139',
        },
    },
};

return presets;
