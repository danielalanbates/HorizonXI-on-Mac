--[[
* ServerSelection Module - Display
* ImGui rendering for server selection dialog
]]

local imgui = require('imgui')
local ThemeHelper = require('libs.themehelper')
local FontManager = require('app.ui.FontManager')
local UIConst = require('constants.ui')
local Colors = require('constants.colors')

local M = {}

-- Window ID from centralized constants
local WINDOW_ID = UIConst.WINDOW_IDS.SERVER_SELECTION

-- Module state
local state = {
    initialized = false,
    hidden = false,
    windowOpen = false,
    locked = false,
    lastCloseKeyState = false  -- For edge detection of close key
}

-- Initialize display module
function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
    
    -- Load window state from config (default to false if not in config)
    -- Note: ServerSelection auto-shows if no server selected (handled in entry file)
    if gConfig and gConfig.windows and gConfig.windows.serverSelection then
        local windowState = gConfig.windows.serverSelection
        if windowState.visible ~= nil then
            state.windowOpen = windowState.visible
        else
            state.windowOpen = false  -- Default closed
        end
        if windowState.locked ~= nil then
            state.locked = windowState.locked
        end
    else
        state.windowOpen = false  -- Default closed on first run
    end
    
    -- Sync showServerSelection with window visible state
    if gConfig then
        gConfig.showServerSelection = state.windowOpen
    end
end

-- Update visuals (called when settings change)
function M.UpdateVisuals(settings)
    -- No special visual updates needed
end

-- Save window state to config (defined before SetVisible which uses it)
local function saveWindowState()
    if not gConfig then
        return
    end
    
    if not gConfig.windows then
        gConfig.windows = {}
    end
    
    gConfig.windows.serverSelection = {
        visible = state.windowOpen,
        locked = state.locked
    }
    
    -- Save to settings
    local settings = require('libs.settings')
    if settings and settings.save then
        settings.save()
    end
end

-- Set visible state (for close policy)
function M.SetVisible(visible)
    local newValue = visible or false
    if state.windowOpen ~= newValue then
        state.windowOpen = newValue
        -- Also update gConfig.showServerSelection so module registry renders correctly
        if gConfig then
            gConfig.showServerSelection = newValue
        end
        saveWindowState()
    end
end

-- Check if window is visible (for close policy)
function M.IsVisible()
    return state.windowOpen or false
end

-- Set hidden state
function M.SetHidden(hidden)
    state.hidden = hidden or false
end

-- Main render function
function M.DrawWindow(settings, dataModule)
    if not state.initialized or state.hidden or not state.windowOpen then
        return
    end
    
    if not dataModule then
        return
    end
    
    -- Don't show if server is already saved
    if dataModule.HasSavedServer() then
        state.windowOpen = false
        -- Also update gConfig.showServerSelection
        if gConfig then
            gConfig.showServerSelection = false
        end
        saveWindowState()
        return
    end
    
    -- Window flags - regular window with no collapse
    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_AlwaysAutoResize
    )
    
    -- Set size and center on screen (use centralized window sizes)
    imgui.SetNextWindowSize(UIConst.WINDOW_SIZES.SERVER_SELECTION, ImGuiCond_FirstUseEver)
    
    -- Apply theme styles
    local themePushed = false
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        local themesFeature = app.features.themes
        local themeIndex = themesFeature:getThemeIndex()
        
        if themeIndex ~= -2 then
            local themeColors = themesFeature:getCurrentThemeColors()
            local backgroundAlpha = themesFeature:getBackgroundAlpha()
            local textAlpha = themesFeature:getTextAlpha()
            
            if themeColors then
                themePushed = ThemeHelper.pushThemeStyles(themeColors, backgroundAlpha, textAlpha)
            end
        end
    end
    
    -- Begin regular window (not modal)
    local windowOpenTable = {state.windowOpen}
    if not imgui.Begin("Select Server##serverselection", windowOpenTable, windowFlags) then
        imgui.End()
        if themePushed then
            ThemeHelper.popThemeStyles()
        end
        return
    end
    
    -- Handle X button close
    if not windowOpenTable[1] then
        state.windowOpen = false
        if gConfig then
            gConfig.showServerSelection = false
        end
        saveWindowState()
    end
    
    local app = _G.FFXIFriendListApp
    local fontSizePx = 14
    if app and app.features and app.features.themes then
        fontSizePx = app.features.themes:getFontSizePx() or 14
    end
    
    FontManager.withFont(fontSizePx, function()
    imgui.TextWrapped("The plugin will not connect to the server until you select and save a server.")
    
    imgui.Separator()
    
    -- Warning text
    imgui.TextWrapped("Warning: If you select the wrong server, you may not be able to find your friends.")
    
    imgui.Separator()
    
    -- Loading/Error state
    local serverState = dataModule.GetState() or "idle"
    local errorMsg = dataModule.GetError()
    
    if serverState == "loading" and not errorMsg then
        imgui.Text("Loading server list...")
        imgui.SameLine()
        if imgui.Button("Retry") then
            dataModule.RefreshServerList()
        end
    elseif errorMsg then
        imgui.TextWrapped("Error: " .. tostring(errorMsg))
        imgui.Separator()
        imgui.TextWrapped("Please retry to load the server list.")
        imgui.Separator()
        if imgui.Button("Retry") then
            dataModule.RefreshServerList()
        end
    end
    
    imgui.Separator()
    
    -- Server list combo
    local servers = dataModule.GetServers() or {}
    local draftServerId = dataModule.GetDraftSelectedServerId() or ""
    
    if #servers == 0 then
        imgui.Text("No servers available.")
    else
        -- Build server names list (with "NONE" option)
        -- Use direct value comparison, not index-based
        local serverItems = {}
        local currentValue = ""  -- Empty string = "NONE"
        
        -- Add "NONE" option first
        table.insert(serverItems, { name = "NONE", id = nil })
        
        -- Add all servers
        for _, server in ipairs(servers) do
            table.insert(serverItems, {
                name = server.name or server.id or "Unknown",
                id = server.id
            })
        end
        
        -- Determine current selection value
        if draftServerId and draftServerId ~= "" then
            currentValue = draftServerId
        else
            currentValue = ""  -- "NONE"
        end
        
        -- Find current preview text
        local previewText = "NONE"
        for _, item in ipairs(serverItems) do
            local itemValue = item.id or ""
            if itemValue == currentValue then
                previewText = item.name
                break
            end
        end
        
        -- Show detected server suggestion
        local detectedServerId = dataModule.GetDetectedServerId()
        local detectedServerName = dataModule.GetDetectedServerName()
        if detectedServerId and detectedServerName then
            imgui.Text("Detected server: " .. detectedServerName)
            imgui.Spacing()
        end
        
        -- Server combo box
        if imgui.BeginCombo("Server", previewText) then
            for _, item in ipairs(serverItems) do
                local itemValue = item.id or ""  -- Empty string for "NONE"
                local isSelected = (itemValue == currentValue)
                local itemText = item.name
                
                -- Use a unique ID for each selectable
                local uniqueId = item.id or "NONE"
                imgui.PushID("server_" .. tostring(uniqueId))
                
                -- Highlight detected server
                if detectedServerId and item.id == detectedServerId then
                    imgui.PushStyleColor(ImGuiCol_Text, {0.0, 1.0, 0.0, 1.0})  -- Green
                end
                
                -- When Selectable is clicked, it returns true
                -- Only update if this item is different from current selection
                local clicked = imgui.Selectable(itemText, isSelected)
                if clicked and itemValue ~= currentValue then
                    -- User clicked on this item - set it as selected
                    if item.id then
                        -- Valid server selected
                        dataModule.SetDraftSelectedServerId(item.id)
                    else
                        -- "NONE" selected, set empty string
                        dataModule.SetDraftSelectedServerId("")
                    end
                end
                
                if detectedServerId and item.id == detectedServerId then
                    imgui.PopStyleColor()
                end
                
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
                
                imgui.PopID()
            end
            imgui.EndCombo()
        end
    end
    
    imgui.Separator()
    
    -- Buttons
    local canSave = (draftServerId ~= "" and draftServerId ~= nil)
    
    -- Save button (disabled if no server selected)
    if canSave then
        if imgui.Button("Save") then
            if dataModule.SaveServerSelection(draftServerId) then
                state.windowOpen = false
                if gConfig then
                    gConfig.showServerSelection = false
                end
                saveWindowState()
            end
        end
    else
        -- Render disabled button (grayed out, non-clickable)
        imgui.PushStyleColor(ImGuiCol_Button, Colors.BUTTON.DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, Colors.BUTTON.DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, Colors.BUTTON.DISABLED)
        imgui.PushStyleColor(ImGuiCol_Text, Colors.BUTTON.DISABLED_TEXT)
        imgui.Button("Save")
        imgui.PopStyleColor(4)
    end
    
    imgui.SameLine()
    
    if imgui.Button("Close") then
        state.windowOpen = false
        if gConfig then
            gConfig.showServerSelection = false
        end
        saveWindowState()
    end
    
    -- Save window position/size on close
    if not state.windowOpen then
        local posX, posY = imgui.GetWindowPos()
        local sizeX, sizeY = imgui.GetWindowSize()
        
        if gConfig then
            if not gConfig.windows then
                gConfig.windows = {}
            end
            if not gConfig.windows.serverSelection then
                gConfig.windows.serverSelection = {}
            end
            
            gConfig.windows.serverSelection.posX = posX
            gConfig.windows.serverSelection.posY = posY
            gConfig.windows.serverSelection.sizeX = sizeX
            gConfig.windows.serverSelection.sizeY = sizeY
        end
    end
    end)
    
    imgui.End()
    
    if themePushed then
        ThemeHelper.popThemeStyles()
    end
end

-- Cleanup
function M.Cleanup()
    state.initialized = false
end

return M

