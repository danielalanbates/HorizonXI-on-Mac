-- ApiKeyPersistence.lua

local Json = require("protocol.Json")
local PathUtils = require("platform.assets.PathUtils")

local M = {}

function M.loadFromFile(characterName)
    local path = PathUtils.getConfigPath("ffxifriendlist.json")
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, data = Json.decode(content)
    if not ok then
        return nil
    end
    
    if not data.data or not data.data.apiKeys then
        return nil
    end
    
    local normalized = characterName:lower()
    for key, value in pairs(data.data.apiKeys) do
        if key:lower() == normalized then
            return value
        end
    end
    
    return nil
end

function M.saveToFile(characterName, apiKey)
    local path = PathUtils.getConfigPath("ffxifriendlist.json")
    PathUtils.ensureDirectory(path)
    
    local file = io.open(path, "r")
    local data = {}
    if file then
        local content = file:read("*all")
        file:close()
        local ok, parsed = Json.decode(content)
        if ok then
            data = parsed
        end
    end
    
    if not data.data then
        data.data = {}
    end
    if not data.data.apiKeys then
        data.data.apiKeys = {}
    end
    
    data.data.apiKeys[characterName] = apiKey
    
    local jsonStr = Json.encode(data)
    file = io.open(path, "w")
    if not file then
        return false
    end
    
    file:write(jsonStr)
    file:close()
    return true
end

return M

