--[[
* Options Module - Display
* ImGui rendering only
]]

local M = {}

local state = {
    initialized = false,
    hidden = false,
    windowOpen = true
}

local WINDOW_ID = "##options_main"

function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
    
    if gConfig and gConfig.windows and gConfig.windows.options then
        local windowState = gConfig.windows.options
        if windowState.visible ~= nil then
            state.windowOpen = windowState.visible
        end
    end
end

function M.UpdateVisuals(settings)
    state.settings = settings or {}
end

function M.SetHidden(hidden)
    state.hidden = hidden or false
end

function M.DrawWindow(settings, dataModule)
    if not state.initialized or state.hidden then
        return
    end
    
    if not dataModule then
        return
    end
    
    local guiManager = ashita and ashita.gui and ashita.gui.GetGuiManager and ashita.gui:GetGuiManager()
    if not guiManager then
        return
    end
    
    local windowFlags = 0
    local app = _G.FFXIFriendListApp
    local globalPositionLocked = false
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        globalPositionLocked = prefs and prefs.windowsPositionLocked or false
    end
    if globalPositionLocked or (gConfig and gConfig.windows and gConfig.windows.options and gConfig.windows.options.locked) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove)
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoResize)
    end
    
    -- Restore window position/size from config
    if gConfig and gConfig.windows and gConfig.windows.options then
        local windowState = gConfig.windows.options
        if windowState.posX and windowState.posY then
            guiManager:SetNextWindowPos(windowState.posX, windowState.posY, ImGuiCond_FirstUseEver)
        end
        if windowState.sizeX and windowState.sizeY then
            guiManager:SetNextWindowSize(windowState.sizeX, windowState.sizeY, ImGuiCond_FirstUseEver)
        end
    end
    
    local windowTitle = "Options" .. WINDOW_ID
    if not guiManager:Begin(windowTitle, state.windowOpen, windowFlags) then
        guiManager:End()
        if state.windowOpen ~= true then
            M.SaveWindowState()
        end
        return
    end
    
    state.windowOpen = true
    M.SaveWindowState()
    
    M.RenderContent(dataModule)
    
    guiManager:End()
end

function M.RenderContent(dataModule)
    local guiManager = ashita.gui:GetGuiManager()
    if not guiManager then
        return
    end
    
    local preferences = dataModule.GetPreferences()
    if not preferences then
        guiManager:Text("Loading preferences...")
        return
    end
    
    guiManager:Text("Settings")
    guiManager:Separator()
    
    -- Share friends across alts
    local shareFriends = preferences.shareFriendsAcrossAlts or false
    if guiManager:Checkbox("Share Friends Across Alts", shareFriends) then
        -- TODO: Update preference via app feature
    end
    
    guiManager:Spacing()
    
    -- Show online status
    local showOnline = preferences.showOnlineStatus or true
    if guiManager:Checkbox("Show Online Status", showOnline) then
        -- TODO: Update preference via app feature
    end
    
    guiManager:Spacing()
    
    -- Share location
    local shareLocation = preferences.shareLocation or true
    if guiManager:Checkbox("Share Location", shareLocation) then
        -- TODO: Update preference via app feature
    end
end

function M.SaveWindowState()
    if not gConfig then
        return
    end
    
    local guiManager = ashita and ashita.gui and ashita.gui.GetGuiManager and ashita.gui:GetGuiManager()
    if not guiManager then
        return
    end
    
    if not gConfig.windows then
        gConfig.windows = {}
    end
    
    if not gConfig.windows.options then
        gConfig.windows.options = {}
    end
    
    local windowState = gConfig.windows.options
    windowState.visible = state.windowOpen
    
    if state.windowOpen then
        local pos = guiManager:GetWindowPos()
        if pos then
            windowState.posX = pos.x
            windowState.posY = pos.y
        end
        
        local size = guiManager:GetWindowSize()
        if size then
            windowState.sizeX = size.x
            windowState.sizeY = size.y
        end
        
        windowState.locked = (gConfig.windows.options.locked == true)
    end
end

function M.Cleanup()
    state.initialized = false
end

return M

