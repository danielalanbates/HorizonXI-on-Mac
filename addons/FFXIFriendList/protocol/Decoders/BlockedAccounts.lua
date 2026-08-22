-- Decoders/BlockedAccounts.lua
-- Decode BlockedAccountsResponse payload

local M = {}

function M.decode(payload)
    if not payload or type(payload) ~= "table" then
        return false, "Invalid payload: expected table"
    end
    
    local result = {
        blocked = {},
        count = payload.count or 0
    }
    
    if payload.blocked and type(payload.blocked) == "table" then
        for _, entry in ipairs(payload.blocked) do
            -- Server returns characterName, normalize to displayName for UI
            table.insert(result.blocked, {
                accountId = entry.accountId,
                displayName = entry.characterName or entry.displayName or "Unknown",
                blockedAt = entry.blockedAt
            })
        end
    end
    
    return true, result
end

return M

