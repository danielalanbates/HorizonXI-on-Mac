--[[
* libs/storage.lua
* Storage wrapper for app features (preferences, notes)
* Uses INI files via persistence.lua
]]--

local persistence = require("libs.persistence")

local M = {}

-- Storage instance (requires installPath and createDirFunc)
function M.new(installPath, createDirFunc)
    local self = {
        installPath = installPath,
        createDirFunc = createDirFunc
    }
    
    return self
end

-- Note: M.load and M.save are not used - use M.create() factory function instead

-- Create storage instance (factory function)
function M.create(installPath, createDirFunc)
    local storage = {
        installPath = installPath,
        createDirFunc = createDirFunc
    }
    
    storage.load = function(key)
        if not storage.installPath then
            return nil
        end
        local filename = key .. ".ini"
        local data, err = persistence.loadIni(storage.installPath, filename, storage.createDirFunc)
        if err then
            return nil
        end
        return data
    end
    
    storage.save = function(key, data)
        if not storage.installPath then
            return false
        end
        local filename = key .. ".ini"
        local success, err = persistence.saveIni(storage.installPath, filename, data, storage.createDirFunc)
        return success
    end
    
    return storage
end

return M

