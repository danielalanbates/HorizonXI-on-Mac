local imgui = require('imgui')

local M = {}

local fontCache = {}
local initialized = false

local VALID_SIZES = {14, 18, 24, 32}
local SIZE_TO_INDEX = {[14] = 1, [18] = 2, [24] = 3, [32] = 4}
local DEFAULT_SIZE = 14

function M.init()
    if initialized then
        return true
    end
    
    local success, err = pcall(function()
        local io = imgui.GetIO()
        if not io or not io.Fonts or not io.Fonts.Fonts then
            return
        end
        
        local fonts = io.Fonts.Fonts
        fontCache[14] = fonts[1]
        fontCache[18] = fonts[2]
        fontCache[24] = fonts[3]
        fontCache[32] = fonts[4]
    end)
    
    if success then
        initialized = true
    end
    
    return initialized
end

function M.get(sizePx)
    if not initialized then
        M.init()
    end
    
    local size = tonumber(sizePx) or DEFAULT_SIZE
    if not SIZE_TO_INDEX[size] then
        size = DEFAULT_SIZE
    end
    
    return fontCache[size]
end

function M.getValidSizes()
    return VALID_SIZES
end

function M.isValidSize(size)
    return SIZE_TO_INDEX[tonumber(size)] ~= nil
end

function M.normalizeSize(size)
    local num = tonumber(size)
    if num and SIZE_TO_INDEX[num] then
        return num
    end
    return DEFAULT_SIZE
end

function M.getScale()
    local app = _G.FFXIFriendListApp
    local fontSizePx = DEFAULT_SIZE
    if app and app.features and app.features.themes then
        fontSizePx = app.features.themes:getFontSizePx() or DEFAULT_SIZE
    end
    return fontSizePx / DEFAULT_SIZE
end

function M.scaled(value)
    return math.floor(value * M.getScale() + 0.5)
end

function M.withFont(sizePx, fn)
    if not fn then
        return
    end
    
    local font = M.get(sizePx)
    local pushed = false
    
    if font then
        local pushSuccess = pcall(function()
            imgui.PushFont(font)
        end)
        pushed = pushSuccess
    end
    
    local ok, err = pcall(fn)
    
    if pushed then
        pcall(imgui.PopFont)
    end
    
    if not ok then
        error(err, 2)
    end
end

return M

