-----------------------------------
-- func: perftime
-- desc: Pin the Vana'diel clock to a given hour, for HorizonXI-on-Mac performance
--       scenarios. The sun and moon drive FFXI's visibility read-backs, so a fixed hour
--       makes runs comparable. Bind-mounted by scripts/lsb-docker/docker-compose.yml.
-- usage: !perftime <hour 0-23>
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 1,
    parameters = 'i'
}

commandObj.onTrigger = function(player, hour)
    hour = hour or 12
    -- One Vana'diel day is 3456 earth seconds; an hour is 144. The offset is applied on top of
    -- whatever offset is already in force, so compute from the current Vana'diel time.
    local current = (VanadielHour() * 60 + VanadielMinute()) * 60
    local target  = hour * 3600
    local deltaVana = (target - current) % 86400
    local deltaEarth = math.floor(deltaVana / 25)
    SetTimeOffset(deltaEarth)
    player:printToPlayer(string.format('perftime: clock moved %d earth seconds', deltaEarth))
    xi.commands.time.onTrigger(player)
end

return commandObj
