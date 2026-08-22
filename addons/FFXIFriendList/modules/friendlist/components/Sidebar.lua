local imgui = require('imgui')
local FontManager = require('app.ui.FontManager')
local icons = require('libs.icons')
local UIConstants = require('core.UIConstants')
local UI = require('constants.ui')

local M = {}

function M.Render(state, dataModule, onSaveState)
    local incomingCount = 0
    if dataModule and dataModule.GetIncomingRequestsCount then
        incomingCount = dataModule.GetIncomingRequestsCount()
    end
    
    local requestsLabel = "Requests"
    if incomingCount > 0 then
        requestsLabel = "Requests (" .. incomingCount .. ")"
    end
    
    local tabs = {"Friends", requestsLabel, "View", "Privacy", "Tags", "Notifications", "Themes", "Help"}
    
    -- Use add-friend icon when there are incoming requests, otherwise use requests icon
    local requestsIcon = incomingCount > 0 and "add_friend" or "tab_requests"
    local tabIcons = {"tab_friends", requestsIcon, "tab_view", "tab_privacy", "tab_tags", "tab_notifications", "tab_themes", "tab_help"}
    local tabColorKeys = {"friends", "requests", "view", "privacy", "tags", "notifications", "themes", "help"}
    
    -- Check if we should use icons and get tint color
    local app = _G.FFXIFriendListApp
    local useIcons = false
    local defaultIconTint = {1, 1, 1, 1}
    local individualColors = {}
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        useIcons = prefs.useIconsForTabs or false
        if prefs.tabIconTint then
            defaultIconTint = {prefs.tabIconTint.r, prefs.tabIconTint.g, prefs.tabIconTint.b, prefs.tabIconTint.a}
        end
        -- Load individual icon colors
        if prefs.tabIconColors then
            for key, color in pairs(prefs.tabIconColors) do
                if color then
                    individualColors[key] = {color.r, color.g, color.b, color.a}
                end
            end
        end
    end
    
    local s = FontManager.scaled
    local framePadding = {s(10), s(8)}
    local buttonSize = {s(164), s(32)}
    local iconButtonSize = useIcons and {s(40), s(32)} or {s(164), s(32)}
    
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    
    for i = 0, #tabs - 1 do
        local isSelected = (state.selectedTab == i)
        local tabLabel = tabs[i + 1]
        local iconName = tabIcons[i + 1]
        
        if isSelected then
            imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.5, 0.8, 1.0})
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.3, 0.6, 0.9, 1.0})
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.1, 0.4, 0.7, 1.0})
        end
        
        local clicked = false
        
        if useIcons then
            -- Get color for this specific icon (individual color or default tint)
            local colorKey = tabColorKeys[i + 1]
            local iconTint = individualColors[colorKey] or defaultIconTint
            
            -- Try to render icon button with custom tint
            local iconClicked = icons.RenderIconButtonWithSize(iconName, s(UI.ICON_SIZES.TAB_ICON_BUTTON), s(UI.ICON_SIZES.TAB_ICON_BUTTON), tabLabel, iconTint)
            if iconClicked == nil then
                -- Fallback to text if icon not available
                clicked = imgui.Button(tabLabel .. "##tab_" .. i, iconButtonSize)
            else
                clicked = iconClicked
            end
        else
            -- Use text labels
            clicked = imgui.Button(tabLabel .. "##tab_" .. i, buttonSize)
        end
        
        if clicked then
            state.selectedTab = i
            if onSaveState then
                onSaveState()
            end
        end
        
        if isSelected then
            imgui.PopStyleColor(3)
        end
    end
    
    imgui.PopStyleVar()
end

return M
