-- PreferencesStore.lua

local Json = require("protocol.Json")
local PathUtils = require("platform.assets.PathUtils")

local M = {}
M.PreferencesStore = {}
M.PreferencesStore.__index = M.PreferencesStore

function M.PreferencesStore.new()
    local self = setmetatable({}, M.PreferencesStore)
    return self
end

function M.PreferencesStore:getSettingsJsonPath()
    return PathUtils.getConfigPath("ffxifriendlist.json")
end

function M.PreferencesStore:getCacheJsonPath()
    return PathUtils.getConfigPath("cache.json")
end

function M.PreferencesStore:loadServerPreferences()
    local path = self:getSettingsJsonPath()
    local file = io.open(path, "r")
    if not file then
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, prefs = Json.decode(content)
    if not ok then
        return {}
    end
    
    return prefs.data and prefs.data.serverPreferences or {}
end

function M.PreferencesStore:saveServerPreferences(prefs)
    local path = self:getSettingsJsonPath()
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
    data.data.serverPreferences = prefs
    
    local jsonStr = Json.encode(data)
    file = io.open(path, "w")
    if not file then
        return false
    end
    
    file:write(jsonStr)
    file:close()
    return true
end

function M.PreferencesStore:loadLocalPreferences()
    local path = self:getSettingsJsonPath()
    local file = io.open(path, "r")
    if not file then
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, prefs = Json.decode(content)
    if not ok then
        return {}
    end
    
    return prefs.data and prefs.data.localPreferences or {}
end

function M.PreferencesStore:saveLocalPreferences(prefs)
    local path = self:getSettingsJsonPath()
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
    data.data.localPreferences = prefs
    
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

