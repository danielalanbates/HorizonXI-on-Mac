local closeGating = require('ui.close_gating')
local windowClosePolicy = require('ui.window_close_policy')
local ffi = require('ffi')

ffi.cdef[[
    int16_t GetKeyState(int32_t vkey);
]]

local M = {}

local keyEdgeState = {
    lastKeyPressed = false,
}

local VK_ESCAPE = 27

local function isDebugEnabled()
    return gConfig and gConfig.debugMode
end

local function debugLog(msg)
    if isDebugEnabled() then
        print("[FFXIFriendList CloseInput] " .. msg)
    end
end

-- Check if a game menu is currently open
local function isGameMenuOpen()
    local inputHandler = require('handlers.input')
    if inputHandler and inputHandler.getMenuName then
        local menuName = inputHandler.getMenuName()
        if menuName and menuName ~= "" then
            debugLog("Game menu open: " .. menuName)
            return true
        end
    end
    return false
end

local function isCloseKeyPressed()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs and prefs.customCloseKeyCode then
            local code = tonumber(prefs.customCloseKeyCode)
            -- If code is 0, "None" is selected - no keyboard close allowed
            if code == 0 then
                return false
            end
            -- If code is valid, use it
            if code and code > 0 and code < 256 then
                local success, keyState = pcall(function()
                    return ffi.C.GetKeyState(code)
                end)
                if success and keyState then
                    return bit.band(keyState, 0x8000) ~= 0
                end
                return false
            end
        end
    end
    
    -- Default to ESC if no preference is set
    local success, keyState = pcall(function()
        return ffi.C.GetKeyState(VK_ESCAPE)
    end)
    
    if success and keyState then
        return bit.band(keyState, 0x8000) ~= 0
    end
    
    return false
end

function M.update()
    local keyPressed = isCloseKeyPressed()
    local keyRising = keyPressed and not keyEdgeState.lastKeyPressed
    keyEdgeState.lastKeyPressed = keyPressed
    
    if not keyRising then
        return false
    end
    
    debugLog("Close key pressed (ESC)")
    
    -- If a game menu is open, don't close addon windows - let game handle ESC first
    if isGameMenuOpen() then
        debugLog("Game menu is open - letting game handle ESC")
        return false
    end
    
    if closeGating.shouldDeferClose() then
        debugLog("Close deferred: popup/menu open")
        return false
    end
    
    if not windowClosePolicy.anyWindowOpen() then
        debugLog("No windows open to close")
        return false
    end
    
    local allLocked = windowClosePolicy.areAllWindowsLocked()
    local topWindow = windowClosePolicy.getTopMostWindowName()
    debugLog("Top window: " .. topWindow .. ", All locked: " .. tostring(allLocked))
    
    local closedWindow = windowClosePolicy.closeTopMostWindow()
    
    if closedWindow ~= "" then
        debugLog("Closed window: " .. closedWindow)
        return true
    else
        debugLog("Close pressed but all windows are locked")
        return false
    end
end

function M.reset()
    keyEdgeState.lastKeyPressed = false
end

return M

