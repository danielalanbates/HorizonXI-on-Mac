-- Vanaguide :: core/story.lua
-- Quest and mission progress, read from the server rather than remembered by the addon.
--
-- FFXI sends the whole quest/mission log in packet 0x056.  Each 0x056 carries a *type*
-- word at 0x24 saying which log page it is, and either 32 bytes of flags at 0x04 (one bit
-- per quest, "current" and "completed" being separate pages) or, for the two special
-- types, the current mission number for each storyline.  That is the only way a client-side
-- addon can know what you have finished — there is no memory API for it — so a guide step
-- that says "this quest is done" is answering with the server's own bookkeeping.
--
-- Page ids and layout follow the same reading of the packet as AndreWesleyPS/ffxi-journal
-- (MIT), which is the clearest public description of 0x056; the implementation here is our
-- own.  See docs/PACKETS.md.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local S = {
    quest = { current = {}, completed = {} },
    mission = { current = {}, completed = {} },
    seen = false,
}

-- log page id -> what it is
local PAGES = {
    [0x0050] = { 'quest', 'current',   'sandoria' },
    [0x0058] = { 'quest', 'current',   'bastok'   },
    [0x0060] = { 'quest', 'current',   'windurst' },
    [0x0068] = { 'quest', 'current',   'jeuno'    },
    [0x0070] = { 'quest', 'current',   'other'    },
    [0x0078] = { 'quest', 'current',   'outlands' },
    [0x0088] = { 'quest', 'current',   'wotg'     },
    [0x00E0] = { 'quest', 'current',   'abyssea'  },
    [0x00F0] = { 'quest', 'current',   'adoulin'  },
    [0x0100] = { 'quest', 'current',   'coalition'},
    [0x0090] = { 'quest', 'completed', 'sandoria' },
    [0x0098] = { 'quest', 'completed', 'bastok'   },
    [0x00A0] = { 'quest', 'completed', 'windurst' },
    [0x00A8] = { 'quest', 'completed', 'jeuno'    },
    [0x00B0] = { 'quest', 'completed', 'other'    },
    [0x00B8] = { 'quest', 'completed', 'outlands' },
    [0x00C8] = { 'quest', 'completed', 'wotg'     },
    [0x00E8] = { 'quest', 'completed', 'abyssea'  },
    [0x00F8] = { 'quest', 'completed', 'adoulin'  },
    [0x0108] = { 'quest', 'completed', 'coalition'},
    [0x0030] = { 'mission', 'completed', 'campaign'   },
    [0x0038] = { 'mission', 'completed', 'campaign_2' },
}

local NATION_AREA = { [0] = 'sandoria', [1] = 'bastok', [2] = 'windurst' }

local function u32(data, off)
    if data == nil or #data < off + 4 then return nil end
    local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
    return b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000
end

local function i32(data, off)
    local v = u32(data, off)
    if v == nil then return nil end
    if v >= 0x80000000 then return v - 0x100000000 end
    return v
end

--- 32 bytes of flags -> set of ids that are set.  Bit n of byte b is quest id b*8+n.
local function flags(data, off, count)
    local set = {}
    for b = 0, count - 1 do
        local byte = data:byte(off + b + 1)
        if byte == nil then break end
        for bit = 0, 7 do
            if math.floor(byte / 2 ^ bit) % 2 == 1 then set[b * 8 + bit] = true end
        end
    end
    return set
end

--- Feed one incoming packet.  Anything that is not 0x056 is ignored cheaply.
function S.on_packet(id, data, size)
    if id ~= 0x056 or data == nil or (size or #data) < 40 then return end
    local page = u32(data, 0x24)
    if page == nil then return end

    local p = PAGES[page]
    if p ~= nil then
        S[p[1]][p[2]][p[3]] = flags(data, 0x04, 32)
        S.seen = true
        return
    end

    -- 0xFFFF: the current mission number of every storyline, in one packet.
    if page == 0xFFFF then
        local nation = i32(data, 0x04)
        S.nation = nation
        local cur = S.mission.current
        cur.nation  = i32(data, 0x08)
        cur.zilart  = i32(data, 0x0C)
        cur.cop     = i32(data, 0x10)
        local acp_mkd = data:byte(0x18 + 1)
        if acp_mkd ~= nil then
            cur.acp = acp_mkd % 16
            cur.mkd = math.floor(acp_mkd / 16)
        end
        local asa = data:byte(0x19 + 1)
        if asa ~= nil then cur.asa = asa % 16 end
        cur.adoulin = i32(data, 0x1C)
        cur.rov     = i32(data, 0x20)
        local area = NATION_AREA[nation]
        if area ~= nil then cur[area] = cur.nation end
        S.seen = true
        return
    end

    -- 0xFFFE: the "treasures of Aht Urhgan" counter, negative when nothing is active.
    if page == 0xFFFE then
        local v = i32(data, 0x04)
        if v ~= nil then S.mission.current.toau = v >= 0 and v or nil end
        return
    end
end

--- Has this quest been completed?  `area` is a log page name ('jeuno', 'sandoria', ...).
function S.quest_done(area, id)
    local set = S.quest.completed[area]
    return set ~= nil and set[id] == true
end

--- Is this quest accepted and not yet turned in?
function S.quest_active(area, id)
    local set = S.quest.current[area]
    return set ~= nil and set[id] == true
end

--- Is this mission finished?  Storylines are linear, so "the current mission is past it"
--- is the completion test; the nation storylines also set the completed flag page.
function S.mission_done(area, id)
    local cur = S.mission.current[area]
    if cur ~= nil and cur > id then return true end
    local set = S.mission.completed[area]
    return set ~= nil and set[id] == true
end

function S.mission_current(area)
    return S.mission.current[area]
end

--- Forget everything.  Called on zone-out to a new character / logout, because the flags
--- belong to whoever is logged in, and a stale set would silently mark steps done.
function S.reset()
    S.quest = { current = {}, completed = {} }
    S.mission = { current = {}, completed = {} }
    S.nation = nil
    S.seen = false
end

return S
