--[[
* protocol/Json.lua
* Centralized JSON encode/decode wrapper
* Uses Ashita's json.lua from addons/libs
]]--

-- Ensure sugar is loaded first (provides T{} helper used by json.lua)
-- Ashita's json.lua requires T{} which comes from sugar library
require("sugar")

-- Use Ashita's json library from addons/libs/json.lua
local json = require("json")

local M = {}

function M.decode(str)
    if not str or str == "" then
        return false, "Empty JSON string"
    end
    
    local success, result = pcall(function()
        -- Ashita's json library uses json.decode(str)
        return json.decode(str)
    end)
    
    if not success then
        -- Ensure error is a string, not a table
        local errorMsg = result
        if type(errorMsg) == "table" then
            errorMsg = "JSON decode error"
        else
            errorMsg = tostring(errorMsg)
        end
        
        -- Log decode failure
        local app = _G.FFXIFriendListApp
        local logger = app and app.deps and app.deps.logger
        if logger and logger.warn then
            logger.warn("[Json] Decode failed: " .. errorMsg)
        end
        
        return false, errorMsg
    end
    
    return true, result
end

function M.encode(table)
    if table == nil then
        return "null"
    end
    
    local success, result = pcall(function()
        -- Ashita's json library uses json.encode(table)
        return json.encode(table)
    end)
    
    if not success then
        -- Ensure error is a string, not a table
        local errorMsg = result
        if type(errorMsg) == "table" then
            errorMsg = "JSON encode error"
        else
            errorMsg = tostring(errorMsg)
        end
        error("Json.encode failed: " .. errorMsg)
    end
    
    return result
end

return M

