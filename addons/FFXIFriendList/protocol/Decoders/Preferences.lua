-- Decoders/Preferences.lua
-- Decode PreferencesResponse / PreferencesUpdateResponse payload

local M = {}

function M.decode(payload)
    if not payload or type(payload) ~= "table" then
        return false, "Invalid payload: expected table"
    end
    
    local result = {
        preferences = {},
        privacy = {}
    }
    
    if payload.preferences and type(payload.preferences) == "table" then
        result.preferences = payload.preferences
    end
    
    if payload.privacy and type(payload.privacy) == "table" then
        result.privacy = payload.privacy
    end
    
    return true, result
end

return M

