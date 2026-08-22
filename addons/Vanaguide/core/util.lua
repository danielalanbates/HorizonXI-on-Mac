-- Vanaguide :: core/util.lua
-- Everything that touches the game directly, in one place, behind small functions that
-- return nil rather than throwing when the player is zoning or not logged in.  The offline
-- harness replaces only this module's inputs (tools/stubs.lua), so nothing below it needs
-- to know whether it is running inside the client.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local zones = require('data.zone_names')

local U = {}

--- FFXI's world axes: X is east/west, Z is north/south, Y is height.  Every distance in
--- this addon is horizontal, because guides care about where you stand, not how high.
function U.dist2(x1, z1, x2, z2)
    local dx, dz = x1 - x2, z1 - z2
    return dx * dx + dz * dz
end

function U.dist(x1, z1, x2, z2)
    return math.sqrt(U.dist2(x1, z1, x2, z2))
end

local function core()
    return _G.AshitaCore
end

--- The player's entity, or nil while zoning / at the character screen.
function U.entity()
    local ok, e = pcall(function() return _G.GetPlayerEntity() end)
    if not ok then return nil end
    return e
end

--- x, z, y in world coordinates, or nil.
function U.position()
    local e = U.entity()
    if e == nil or e.Movement == nil or e.Movement.LocalPosition == nil then return nil end
    local p = e.Movement.LocalPosition
    return p.X, p.Z, p.Y
end

--- Facing, in radians, measured the way FFXI measures it (0 = east, counter-clockwise).
function U.heading()
    local e = U.entity()
    if e == nil then return nil end
    if e.Movement and e.Movement.LocalPosition then return e.Movement.LocalPosition.Yaw end
    return e.Heading
end

--- Current zone id, or nil when it is not knowable yet.
function U.zone()
    local c = core()
    if c == nil then return nil end
    local ok, id = pcall(function()
        return c:GetMemoryManager():GetParty():GetMemberZone(0)
    end)
    if not ok or id == nil or id == 0 then return nil end
    return id
end

--- Zone name.  The client's own localised string wins; the generated table is the fallback
--- so that names still resolve in the harness and in logs written before login.
function U.zone_name(id)
    if id == nil then return '?' end
    local c = core()
    if c ~= nil then
        local ok, s = pcall(function()
            return c:GetResourceManager():GetString('zones.names', id)
        end)
        if ok and s ~= nil and s ~= '' then return s end
    end
    return zones.name[id] or ('zone ' .. tostring(id))
end

function U.zone_id(name)
    return zones.find(name)
end

local function player()
    local c = core()
    if c == nil then return nil end
    local ok, p = pcall(function() return c:GetMemoryManager():GetPlayer() end)
    if not ok then return nil end
    return p
end

function U.logged_in()
    local p = player()
    if p == nil then return false end
    local ok, s = pcall(function() return p:GetLoginStatus() end)
    return ok and s == 2
end

function U.main_job()
    local p = player()
    if p == nil then return nil, nil end
    return p:GetMainJob(), p:GetMainJobLevel()
end

function U.job_level(job_id)
    local p = player()
    if p == nil then return 0 end
    local ok, lv = pcall(function() return p:GetJobLevel(job_id) end)
    return ok and lv or 0
end

function U.level()
    local _, lv = U.main_job()
    return lv or 0
end

function U.rank()
    local p = player()
    if p == nil then return 0 end
    local ok, r = pcall(function() return p:GetRank() end)
    return ok and r or 0
end

function U.nation()
    local p = player()
    if p == nil then return nil end
    local ok, n = pcall(function() return p:GetNation() end)
    return ok and n or nil
end

function U.has_key_item(id)
    local p = player()
    if p == nil then return false end
    local ok, v = pcall(function() return p:HasKeyItem(id) end)
    return ok and v == true
end

function U.has_spell(id)
    local p = player()
    if p == nil then return false end
    local ok, v = pcall(function() return p:HasSpell(id) end)
    return ok and v == true
end

--- How many of an item are in the ordinary inventory containers.
--- Containers 0 (inventory), 1 (safe), 2 (storage), 3 (temporary) and the wardrobes are all
--- checked, because a guide step that says "you have the letter" does not care where it sits.
local CONTAINERS = { 0, 1, 2, 3, 4, 5, 6, 7, 8 }
function U.item_count(id)
    local c = core()
    if c == nil then return 0 end
    local ok, total = pcall(function()
        local inv = c:GetMemoryManager():GetInventory()
        local n = 0
        for _, container in ipairs(CONTAINERS) do
            local max = inv:GetContainerCountMax(container) or 0
            for i = 0, max do
                local item = inv:GetContainerItem(container, i)
                if item ~= nil and item.Id == id then n = n + (item.Count or 1) end
            end
        end
        return n
    end)
    return ok and total or 0
end

--- Chat output, prefixed so it is findable in a busy log.
function U.print(msg)
    local line = '[Vanaguide] ' .. tostring(msg)
    if _G.print ~= nil then _G.print(line) end
end

--- Clamp an angle to (-pi, pi].
function U.wrap_angle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a <= -math.pi do a = a + 2 * math.pi end
    return a
end

--- Bearing from the player to a point, relative to where the player is facing.
--- 0 means "straight ahead"; positive is to the player's left, matching FFXI's yaw.
function U.relative_bearing(px, pz, yaw, tx, tz)
    local target = math.atan2(-(tz - pz), tx - px)
    return U.wrap_angle(target - (yaw or 0))
end

return U
