-- Decoders/FriendsList.lua
-- Decode FriendsListResponse payload
-- Server returns friends array with all data inline (name, isOnline, job, zone, etc.)

local M = {}

function M.decode(payload)
    if not payload or type(payload) ~= "table" then
        return false, "Invalid payload: expected table"
    end
    
    local result = {
        friends = {},
        statuses = {},
        serverTime = 0
    }
    
    -- Extract friends array
    -- Server returns friends with all data inline:
    -- { friendAccountId, friendedAsName, name, isOnline, lastSeenAt, job, zone, nation, rank, ... }
    if payload.friends and type(payload.friends) == "table" then
        result.friends = payload.friends
        
        -- Also build statuses array from the same data for compatibility
        -- The friends.lua handler uses statuses for updating friend status
        for _, friend in ipairs(payload.friends) do
            if friend.name or friend.friendedAsName then
                table.insert(result.statuses, {
                    name = friend.name or friend.friendedAsName,
                    characterName = friend.name or friend.friendedAsName,
                    isOnline = friend.isOnline,
                    isAway = friend.isAway,
                    job = friend.job,
                    zone = friend.zone,
                    nation = friend.nation,
                    rank = friend.rank,
                    lastSeenAt = friend.lastSeenAt,
                    sharesOnlineStatus = friend.sharesOnlineStatus,
                    linkedCharacters = friend.linkedCharacters,
                    friendedAsName = friend.friendedAsName,
                    friendAccountId = friend.friendAccountId
                })
            end
        end
    end
    
    -- Also check for separate statuses array if server sends it
    if payload.statuses and type(payload.statuses) == "table" then
        for _, status in ipairs(payload.statuses) do
            table.insert(result.statuses, status)
        end
    end
    
    if payload.serverTime then
        result.serverTime = tonumber(payload.serverTime) or 0
    end
    
    return true, result
end

return M

