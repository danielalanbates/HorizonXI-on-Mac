-- IconManager.lua

local PathUtils = require("platform.assets.PathUtils")

local M = {}
M.IconManager = {}
M.IconManager.__index = M.IconManager

function M.IconManager.new(guiManager)
    local self = setmetatable({}, M.IconManager)
    self.guiManager = guiManager
    self.iconCache = {}
    return self
end

function M.IconManager:loadIcon(iconName)
    if self.iconCache[iconName] then
        return self.iconCache[iconName]
    end
    
    local path = PathUtils.getAssetPath("icons", iconName .. ".png")
    
    if self.guiManager and self.guiManager.LoadTexture then
        local texture = self.guiManager.LoadTexture(path)
        if texture then
            self.iconCache[iconName] = texture
            return texture
        end
    end
    
    return nil
end

function M.IconManager:getIcon(iconName)
    return self.iconCache[iconName]
end

function M.IconManager:clearCache()
    self.iconCache = {}
end

return M

