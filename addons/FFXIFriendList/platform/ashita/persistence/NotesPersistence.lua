-- NotesPersistence.lua

local Json = require("protocol.Json")
local PathUtils = require("platform.assets.PathUtils")

local M = {}

function M.loadFromFile()
    local path = PathUtils.getConfigPath("ffxifriendlist.json")
    local file = io.open(path, "r")
    if not file then
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, data = Json.decode(content)
    if not ok then
        return {}
    end
    
    return data.data and data.data.notes or {}
end

function M.saveToFile(notes)
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
    data.data.notes = notes
    
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

