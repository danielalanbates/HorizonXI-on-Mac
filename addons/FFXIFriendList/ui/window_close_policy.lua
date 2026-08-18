-- window_close_policy.lua
-- Centralized window close policy with priority order
-- Priority order: NoteEditor (highest) → QuickOnline → Main

local M = {}

-- Window priority (higher number = higher priority, closes first)
M.PRIORITY = {
    Main = 1,
    QuickOnline = 2,
    NoteEditor = 3,
    ServerSelection = 4  -- Only shown when needed, highest priority to dismiss
}

-- Window ID to module name mapping
local WINDOW_IDS = {
    NoteEditor = "noteEditor",
    QuickOnline = "quickOnline",
    Main = "friendList",
    ServerSelection = "serverSelection"
}

-- Get window visibility and lock state
-- Returns table of { name, visible, locked, priority }
local function getWindowStates()
    local states = {}
    
    -- Get module registry
    local moduleRegistry = _G.moduleRegistry
    if not moduleRegistry then
        return states
    end
    
    -- Check each window
    -- Note: configKey must match what's used in gConfig.windows (e.g., gConfig.windows.friendList)
    local windowConfigs = {
        { name = "NoteEditor", moduleName = "noteEditor", configKey = "noteEditor" },
        { name = "QuickOnline", moduleName = "quickOnline", configKey = "quickOnline" },
        { name = "Main", moduleName = "friendList", configKey = "friendList" },
        { name = "ServerSelection", moduleName = "serverSelection", configKey = "serverSelection" }
    }
    
    for _, config in ipairs(windowConfigs) do
        local entry = moduleRegistry.Get(config.moduleName)
        if entry and entry.module and entry.module.display then
            local display = entry.module.display
            
            -- Check if window is visible
            local visible = false
            if display.IsVisible then
                visible = display.IsVisible()
            elseif display.GetState then
                local state = display.GetState()
                visible = state and state.windowOpen or false
            end
            
            -- Check if window is locked (per-window or global)
            local locked = false
            if gConfig and gConfig.windows and gConfig.windows[config.configKey] then
                locked = gConfig.windows[config.configKey].locked or false
            end
            
            -- Also check global windowsLocked preference
            local app = _G.FFXIFriendListApp
            if app and app.features and app.features.preferences then
                local prefs = app.features.preferences:getPrefs()
                if prefs and prefs.windowsLocked then
                    locked = true
                end
            end
            
            table.insert(states, {
                name = config.name,
                moduleName = config.moduleName,
                visible = visible,
                locked = locked,
                priority = M.PRIORITY[config.name] or 0
            })
        end
    end
    
    -- Sort by priority (highest first)
    table.sort(states, function(a, b) return a.priority > b.priority end)
    
    return states
end

-- Check if any window is open
function M.anyWindowOpen()
    local states = getWindowStates()
    for _, state in ipairs(states) do
        if state.visible then
            return true
        end
    end
    return false
end

-- Close the top-most (highest priority) unlocked window
-- Returns the name of the window that was closed, or empty string if none
function M.closeTopMostWindow()
    local states = getWindowStates()
    
    for _, state in ipairs(states) do
        if state.visible and not state.locked then
            -- Close this window
            local moduleRegistry = _G.moduleRegistry
            if moduleRegistry then
                local entry = moduleRegistry.Get(state.moduleName)
                if entry and entry.module and entry.module.display then
                    local display = entry.module.display
                    
                    -- Try SetVisible method first
                    if display.SetVisible then
                        display.SetVisible(false)
                    elseif display.SetWindowOpen then
                        display.SetWindowOpen(false)
                    elseif display.Close then
                        display.Close()
                    end
                    
                    -- Save window state if available
                    if display.SaveWindowState then
                        display.SaveWindowState()
                    end
                    
                    return state.name
                end
            end
        end
    end
    
    return ""
end

-- Get the name of the top-most visible window
function M.getTopMostWindowName()
    local states = getWindowStates()
    for _, state in ipairs(states) do
        if state.visible then
            return state.name
        end
    end
    return ""
end

-- Check if all windows are locked
function M.areAllWindowsLocked()
    local states = getWindowStates()
    for _, state in ipairs(states) do
        if state.visible and not state.locked then
            return false
        end
    end
    return true
end

return M

