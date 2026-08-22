local ffi = require('ffi')

local M = {}

local VK_SHIFT = 16

local function isDebugEnabled()
    return gConfig and gConfig.debugMode
end

local function debugLog(msg)
    if isDebugEnabled() then
        print("[FFXIFriendList InputHelper] " .. msg)
    end
end

function M.isShiftDown()
    local success, keyState = pcall(function()
        return ffi.C.GetKeyState(VK_SHIFT)
    end)
    
    if success and keyState then
        return bit.band(keyState, 0x8000) ~= 0
    end
    
    if not success then
        debugLog("SHIFT detection failed - FFI unavailable")
    end
    
    return false
end

return M

