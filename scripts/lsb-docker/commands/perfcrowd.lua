-----------------------------------
-- func: perfcrowd
-- desc: Spawn the first N mobs of the current zone at the player, for HorizonXI-on-Mac
--       performance scenarios. Bind-mounted into the local test server by
--       scripts/lsb-docker/docker-compose.yml; not part of upstream LandSandBoat.
-- usage: !perfcrowd <count>
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 1,
    parameters = 'i'
}

commandObj.onTrigger = function(player, count)
    local zone = player:getZone()
    if not zone then
        return
    end
    count = count or 40
    local base = 0x1000000 + zone:getID() * 0x1000
    local x, y, z, rot = player:getXPos(), player:getYPos(), player:getZPos(), player:getRotPos()
    local spawned, tried = 0, 0
    local slot = 1
    while spawned < count and slot < 1024 do
        local mob = GetMobByID(base + slot)
        slot = slot + 1
        if mob then
            tried = tried + 1
            if not mob:isSpawned() then
                SpawnMob(base + slot - 1)
            end
            -- Fan the crowd out in a ring so they do not stack on one point.
            local a = (spawned / count) * 2 * math.pi
            mob:setPos(x + 6 * math.cos(a), y, z + 6 * math.sin(a), rot)
            spawned = spawned + 1
        end
    end
    player:printToPlayer(string.format('perfcrowd: %d spawned (%d ids checked)', spawned, tried))
end

return commandObj
