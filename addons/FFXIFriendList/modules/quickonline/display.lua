--[[
* QuickOnline Module - Display
* ImGui rendering for condensed friend list window (online friends sorted first)
]]

local imgui = require('imgui')
local ThemeHelper = require('libs.themehelper')
local icons = require('libs.icons')
local scaling = require('scaling')
local InputHelper = require('ui.helpers.InputHelper')
local HoverTooltip = require('ui.widgets.HoverTooltip')
local TooltipHelper = require('ui.helpers.TooltipHelper')
local FontManager = require('app.ui.FontManager')
local UIConst = require('constants.ui')
local Colors = require('constants.colors')

local FriendContextMenu = require('modules.friendlist.components.FriendContextMenu')
local FriendDetailsPopup = require('modules.friendlist.components.FriendDetailsPopup')
local CollapsibleTagSection = require('modules.friendlist.components.CollapsibleTagSection')
local FriendsTable = require('modules.friendlist.components.FriendsTable')
local utils = require('modules.friendlist.components.helpers.utils')
local tagcore = require('core.tagcore')
local taggrouper = require('core.taggrouper')

local M = {}

local function capitalizeName(name)
    if not name or name == "" then
        return "Unknown"
    end
    return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

-- Module state
local state = {
    initialized = false,
    hidden = false,
    -- NOTE: Window visibility is controlled by gConfig.showQuickOnline (single source of truth)
    selectedFriendForDetails = nil,
    locked = false,
    -- Friend table state (simplified - minimal columns)
    sortColumn = "name",
    sortDirection = "asc",
    filterText = {""},
    columnVisible = {
        name = true,
        job = true,
        zone = true,
        status = true
    },
    lastCloseKeyState = false,  -- For edge detection of close key
    -- Server selection state
    serverSelectionOpened = false,
    serverWindowNeedsCenter = false,
    serverListRefreshTriggered = false,
    -- Online/Offline grouping (groupByOnlineStatus and hideTopBar are read directly from gConfig)
    collapsedOnlineSection = false,
    collapsedOfflineSection = false
}

-- Window ID (stable internal ID with ## pattern)
local WINDOW_ID = "##quickonline_main"

-- Initialize display module
function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
    
    if gConfig and gConfig.windows and gConfig.windows.quickOnline then
        local windowState = gConfig.windows.quickOnline
        if windowState.locked ~= nil then
            state.locked = windowState.locked
        end
    end
    
    if gConfig then
        gConfig.showQuickOnline = false
    end
    
    -- Load quick online settings from config
    if gConfig and gConfig.quickOnlineSettings then
        local settings = gConfig.quickOnlineSettings
        if settings.sort then
            if settings.sort.column then
                state.sortColumn = settings.sort.column
            end
            if settings.sort.direction then
                state.sortDirection = settings.sort.direction
            end
        end
        if settings.filter then
            state.filterText[1] = settings.filter or ""
        end
        if settings.columns then
            if settings.columns.name ~= nil then
                state.columnVisible.name = settings.columns.name
            end
            if settings.columns.job ~= nil then
                state.columnVisible.job = settings.columns.job
            end
            if settings.columns.zone ~= nil then
                state.columnVisible.zone = settings.columns.zone
            end
            if settings.columns.status ~= nil then
                state.columnVisible.status = settings.columns.status
            end
        end
        -- Note: groupByOnlineStatus is read directly from gConfig, not cached in state
        if settings.collapsedOnlineSection ~= nil then
            state.collapsedOnlineSection = settings.collapsedOnlineSection
        end
        if settings.collapsedOfflineSection ~= nil then
            state.collapsedOfflineSection = settings.collapsedOfflineSection
        end
        -- Note: hideTopBar is read directly from gConfig, not cached in state
    end
end

-- Update visuals (called when settings change)
function M.UpdateVisuals(settings)
    -- No special visual updates needed
end

-- Set hidden state
function M.SetHidden(hidden)
    state.hidden = hidden or false
end

-- Check if window is visible (for close policy)
function M.IsVisible()
    return gConfig and gConfig.showQuickOnline or false
end

-- Set window visibility (for close policy)
function M.SetVisible(visible)
    if gConfig then
        local newValue = visible or false
        if gConfig.showQuickOnline ~= newValue then
            gConfig.showQuickOnline = newValue
            M.SaveWindowState()
        end
    end
end

-- Main render function
function M.DrawWindow(settings, dataModule)
    -- Don't draw if window is closed (gConfig.showQuickOnline is the single source of truth)
    if not state.initialized or state.hidden or not gConfig or not gConfig.showQuickOnline then
        return
    end
    
    if not dataModule then
        return
    end
    
    -- Check if server selection is needed BEFORE rendering main window
    local app = _G.FFXIFriendListApp
    local needsServerSelection = false
    if app and app.features and app.features.serverlist then
        -- Only show server not detected if:
        -- 1. No server is selected AND
        -- 2. Server detection has already been attempted (not just waiting for servers to load)
        if not app.features.serverlist:isServerSelected() and app._serverDetectionCompleted then
            needsServerSelection = true
        end
    end
    
    -- If server detection is still pending, wait without showing window
    -- Once detection completes, if no server was found, show error message
    if needsServerSelection then
        M.RenderServerNotDetectedWindow()
        return
    end
    
    -- Wait for connection to establish before showing main window
    -- This ensures auto-connect completes before rendering
    if app and app.features and app.features.connection then
        if not app.features.connection:isConnected() then
            return
        end
    end
    
    -- Server is connected - render main window normally
    local overlayEnabled = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.compact_overlay_enabled or false
    local disableInteraction = false
    local tooltipBgEnabled = false
    if overlayEnabled and gConfig and gConfig.quickOnlineSettings then
        disableInteraction = gConfig.quickOnlineSettings.compact_overlay_disable_interaction or false
        tooltipBgEnabled = gConfig.quickOnlineSettings.compact_overlay_tooltip_bg or false
    end
    
    local windowFlags = 0
    local app = _G.FFXIFriendListApp
    local globalLocked = false
    local globalPositionLocked = false
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        globalLocked = prefs and prefs.windowsLocked or false
        globalPositionLocked = prefs and prefs.windowsPositionLocked or false
    end
    
    if overlayEnabled then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoTitleBar)
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoResize)
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove)
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoBackground)
        if disableInteraction then
            windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoInputs)
            windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoFocusOnAppearing)
            windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoBringToFrontOnFocus)
        end
        if not state.locked then
            state.locked = true
            if gConfig then
                if not gConfig.windows then
                    gConfig.windows = {}
                end
                if not gConfig.windows.quickOnline then
                    gConfig.windows.quickOnline = {}
                end
                gConfig.windows.quickOnline.locked = true
            end
        end
    elseif globalPositionLocked or state.locked then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove)
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoResize)
    end
    
    if gConfig and gConfig.windows and gConfig.windows.quickOnline then
        local windowState = gConfig.windows.quickOnline
        if overlayEnabled then
            if windowState.posX and windowState.posY then
                imgui.SetNextWindowPos({windowState.posX, windowState.posY}, ImGuiCond_Always)
            end
        elseif windowState.forcePosition and windowState.posX and windowState.posY then
            imgui.SetNextWindowPos({windowState.posX, windowState.posY}, ImGuiCond_Always)
            windowState.forcePosition = false
        elseif windowState.posX and windowState.posY then
            imgui.SetNextWindowPos({windowState.posX, windowState.posY}, ImGuiCond_FirstUseEver)
        end
        if not overlayEnabled then
            if windowState.sizeX and windowState.sizeY then
                imgui.SetNextWindowSize({windowState.sizeX, windowState.sizeY}, ImGuiCond_FirstUseEver)
            else
                imgui.SetNextWindowSize({420, 320}, ImGuiCond_FirstUseEver)
            end
        end
    else
        if not overlayEnabled then
            imgui.SetNextWindowSize({420, 320}, ImGuiCond_FirstUseEver)
        end
    end
    
    -- Window title
    local windowTitle = "Compact Friend List" .. WINDOW_ID
    
    -- Update locked state from config
    if gConfig and gConfig.windows and gConfig.windows.quickOnline then
        state.locked = gConfig.windows.quickOnline.locked or false
    end
    
    -- ESC/close key handling is centralized in ui/input/close_input.lua
    
    -- Apply theme styles (only if not default theme)
    local themePushed = false
    local overlayStylePushed = false
    local overlayColorCount = 0
    
    -- ALWAYS apply addon theme first (unless using Ashita default theme)
    -- This ensures text colors, buttons, scrollbars etc. use our theme
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        local themesFeature = app.features.themes
        local themeIndex = themesFeature:getThemeIndex()
        
        -- Only apply theme if not default (themeIndex != -2)
        if themeIndex ~= -2 then
            local success, err = pcall(function()
                local themeColors = themesFeature:getCurrentThemeColors()
                local backgroundAlpha = themesFeature:getBackgroundAlpha()
                local textAlpha = themesFeature:getTextAlpha()
                
                if themeColors then
                    themePushed = ThemeHelper.pushThemeStyles(themeColors, backgroundAlpha, textAlpha)
                end
            end)
            if not success then
                if app.deps and app.deps.logger and app.deps.logger.error then
                    app.deps.logger.error("[QuickOnline Display] Theme application failed: " .. tostring(err))
                else
                    print("[FFXIFriendList ERROR] QuickOnline Display: Theme application failed: " .. tostring(err))
                end
            end
        end
    end
    
    -- THEN apply overlay transparency on top of the theme
    if overlayEnabled then
        imgui.PushStyleColor(ImGuiCol_WindowBg, Colors.TRANSPARENT)
        imgui.PushStyleColor(ImGuiCol_ChildBg, Colors.TRANSPARENT)
        overlayColorCount = 2
        if not disableInteraction and not tooltipBgEnabled then
            imgui.PushStyleColor(ImGuiCol_PopupBg, Colors.TRANSPARENT)
            overlayColorCount = 3
        end
        imgui.PushStyleColor(ImGuiCol_Border, Colors.TRANSPARENT)
        overlayColorCount = overlayColorCount + 1
        overlayStylePushed = true
    end
    
    -- Pass windowOpen as a table so ImGui can modify it when X button is clicked
    -- gConfig.showQuickOnline is the source of truth
    local isOpen = gConfig and gConfig.showQuickOnline or false
    local windowOpenTable = {isOpen}
    local windowOpen = imgui.Begin(windowTitle, windowOpenTable, windowFlags)
    
    -- Detect if X button was clicked (ImGui sets windowOpenTable[1] to false)
    local xButtonClicked = isOpen and not windowOpenTable[1]
    
    -- Handle X button close attempt
    if xButtonClicked then
        -- Locked windows ignore X button close
        if state.locked or globalLocked then
            -- Keep window open - locked windows can't be closed via X
        else
            local closeGating = require('ui.close_gating')
            if not closeGating.shouldDeferClose() then
                -- Close the window
                if gConfig then
                    gConfig.showQuickOnline = false
                end
                M.SaveWindowState()
            end
        end
    end
    
    if windowOpen then
        local app = _G.FFXIFriendListApp
        local fontSizePx = 14
        if app and app.features and app.features.themes then
            fontSizePx = app.features.themes:getFontSizePx() or 14
        end
        
        FontManager.withFont(fontSizePx, function()
            M.SaveWindowState()
            
            local hideTopBar = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.hideTopBar or false
            if not hideTopBar and not overlayEnabled then
                M.RenderTopBar(dataModule)
                imgui.Spacing()
            end
            
            local childFlags = 0
            if disableInteraction then
                childFlags = bit.bor(childFlags, ImGuiWindowFlags_NoInputs)
            end
            imgui.BeginChild("##quick_online_body", {0, 0}, false, childFlags)
            
            -- Context menu for window options
            if imgui.BeginPopupContextWindow("##quick_online_context") then
                local hideTopBar = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.hideTopBar or false
                local hideTopBarBuf = {hideTopBar}
                if imgui.Checkbox("Hide Top Bar", hideTopBarBuf) then
                    if gConfig then
                        if not gConfig.quickOnlineSettings then
                            gConfig.quickOnlineSettings = {}
                        end
                        gConfig.quickOnlineSettings.hideTopBar = hideTopBarBuf[1]
                        M.SaveWindowState()
                        local settings = require('libs.settings')
                        if settings and settings.save then
                            settings.save()
                        end
                    end
                end
                imgui.EndPopup()
            end
            
            if overlayEnabled then
                imgui.PushStyleColor(ImGuiCol_ChildBg, Colors.TRANSPARENT)
            end
            M.RenderFriendsTable(dataModule, overlayEnabled, disableInteraction, tooltipBgEnabled)
            if overlayEnabled then
                imgui.PopStyleColor()
            end
            imgui.EndChild()
        end)
    end
    
    imgui.End()
    
    -- Pop overlay styles if we pushed them (must pop before theme)
    if overlayStylePushed then
        imgui.PopStyleColor(overlayColorCount)
    end
    
    -- Pop theme styles if we pushed them
    if themePushed then
        local success, err = pcall(ThemeHelper.popThemeStyles)
        if not success then
            local app = _G.FFXIFriendListApp
            if app and app.deps and app.deps.logger and app.deps.logger.error then
                app.deps.logger.error("[QuickOnline Display] Theme pop failed: " .. tostring(err))
            else
                print("[FFXIFriendList ERROR] QuickOnline Display: Theme pop failed: " .. tostring(err))
            end
        end
    end
    
    -- Render friend details popup if needed (use shared component from main window)
    if state.selectedFriendForDetails then
        FriendDetailsPopup.Render(state.selectedFriendForDetails, state, M.GetCallbacks(dataModule))
    end
end

function M.RenderTopBar(dataModule)
    local isConnected = dataModule.IsConnected()
    local s = FontManager.scaled
    
    -- Get UI icon colors from preferences
    local app = _G.FFXIFriendListApp
    local uiIconColors = {}
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs.uiIconColors then
            for key, color in pairs(prefs.uiIconColors) do
                if color then
                    uiIconColors[key] = {color.r, color.g, color.b, color.a}
                end
            end
        end
    end
    
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {s(6), s(6)})
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, s(4))
    
    local lockIconName = state.locked and "lock" or "unlock"
    local lockTooltip = state.locked and "Window locked (click to unlock)" or "Lock window position"
    local lockColor = uiIconColors[lockIconName] or {1, 1, 1, 1}
    
    local lockIconSize = s(UIConst.ICON_SIZES.ACTION_ICON_BUTTON)
    local clicked = icons.RenderIconButtonWithSize(lockIconName, lockIconSize, lockIconSize, lockTooltip, lockColor)
    if clicked == nil then
        local lockLabel = state.locked and "Locked" or "Unlocked"
        clicked = imgui.Button(lockLabel .. "##lock_btn")
        if imgui.IsItemHovered() then
            imgui.SetTooltip(lockTooltip)
        end
    end
    
    if clicked then
        state.locked = not state.locked
        if gConfig then
            if not gConfig.windows then
                gConfig.windows = {}
            end
            if not gConfig.windows.quickOnline then
                gConfig.windows.quickOnline = {}
            end
            gConfig.windows.quickOnline.locked = state.locked
        end
    end
    
    imgui.SameLine(0, s(4))
    
    if not isConnected then
        imgui.PushStyleColor(ImGuiCol_Button, Colors.BUTTON.DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, Colors.BUTTON.DISABLED)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, Colors.BUTTON.DISABLED)
    end
    
    -- Refresh button - always use icon
    local refreshIconSize = s(UIConst.ICON_SIZES.ACTION_ICON_BUTTON)
    local refreshColor = uiIconColors.refresh or {1, 1, 1, 1}
    local refreshClicked = icons.RenderIconButtonWithSize("refresh", refreshIconSize, refreshIconSize, "Refresh friend list", refreshColor)
    if refreshClicked == nil then
        -- Fallback to text button
        refreshClicked = imgui.Button("Refresh")
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Refresh friend list")
        end
    end
    
    if refreshClicked then
        if isConnected then
            local app = _G.FFXIFriendListApp
            if app and app.features and app.features.friends then
                app.features.friends:refresh()
            end
        end
    end
    
    if not isConnected then
        imgui.PopStyleColor(3)
    end
    
    imgui.SameLine(0, s(4))
    
    -- Full button - always use expand icon
    local expandIconSize = s(UIConst.ICON_SIZES.ACTION_ICON_BUTTON)
    local expandColor = uiIconColors.expand or {1, 1, 1, 1}
    local expandClicked = icons.RenderIconButtonWithSize("expand", expandIconSize, expandIconSize, "Switch to full view (Main Window)", expandColor)
    if expandClicked == nil then
        -- Fallback to text button
        expandClicked = imgui.Button("Full")
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Switch to full view (Main Window)")
        end
    end
    
    if expandClicked then
        if gConfig then
            local posX, posY = imgui.GetWindowPos()
            
            if not gConfig.windows then gConfig.windows = {} end
            if not gConfig.windows.friendList then gConfig.windows.friendList = {} end
            gConfig.windows.friendList.posX = posX
            gConfig.windows.friendList.posY = posY
            gConfig.windows.friendList.forcePosition = true
            
            gConfig.showQuickOnline = false
            gConfig.showFriendList = true
            M.SaveWindowState()
            local settings = require('libs.settings')
            if settings and settings.save then
                settings.save()
            end
        end
    end
    
    -- Invisible button to fill remaining space and capture right-clicks
    imgui.SameLine()
    local availWidth, availHeight = imgui.GetContentRegionAvail()
    imgui.InvisibleButton("##topbar_space", {availWidth, s(24)})
    
    imgui.PopStyleVar(2)
    
    -- Context menu for top bar options (triggers on any item in the top bar)
    if imgui.BeginPopupContextItem("##quick_online_topbar_context", ImGuiPopupFlags_MouseButtonRight) then
        local hideTopBar = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.hideTopBar or false
        local hideTopBarBuf = {hideTopBar}
        if imgui.Checkbox("Hide Top Bar", hideTopBarBuf) then
            if gConfig then
                if not gConfig.quickOnlineSettings then
                    gConfig.quickOnlineSettings = {}
                end
                gConfig.quickOnlineSettings.hideTopBar = hideTopBarBuf[1]
                M.SaveWindowState()
                local settings = require('libs.settings')
                if settings and settings.save then
                    settings.save()
                end
            end
        end
        imgui.EndPopup()
    end
end

function M.RenderFriendsTable(dataModule, overlayEnabled, disableInteraction, tooltipBgEnabled)
    overlayEnabled = overlayEnabled or false
    disableInteraction = disableInteraction or false
    tooltipBgEnabled = tooltipBgEnabled or false
    local app = _G.FFXIFriendListApp
    local tagsFeature = app and app.features and app.features.tags
    
    local friends = dataModule.GetOnlineFriends()
    
    local filteredFriends = {}
    local filterText = string.lower(state.filterText[1] or "")
    if filterText == "" then
        filteredFriends = friends
    else
        for _, friend in ipairs(friends) do
            local friendName = type(friend.name) == "string" and string.lower(friend.name) or ""
            local presence = friend.presence or {}
            local job = type(presence.job) == "string" and string.lower(presence.job) or ""
            local zone = type(presence.zone) == "string" and string.lower(presence.zone) or ""
            if string.find(friendName, filterText, 1, true) or
               string.find(job, filterText, 1, true) or
               string.find(zone, filterText, 1, true) then
                table.insert(filteredFriends, friend)
            end
        end
    end
    
    if #filteredFriends == 0 then
        imgui.Text("No friends" .. (filterText ~= "" and " (filtered)" or ""))
        return
    end
    
    local tagOrder = {}
    if tagsFeature then
        tagOrder = tagsFeature:getAllTags() or {}
    end
    
    local getFriendTag = function(friend)
        if not tagsFeature then
            return nil
        end
        local friendKey = tagcore.getFriendKey(friend)
        return tagsFeature:getTagForFriend(friendKey)
    end
    
    local sortMode = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.sortMode or "status"
    local sortDirection = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.sortDirection or "asc"
    
    local callbacks = M.GetCallbacks(dataModule)
    local sectionCallbacks = {
        onSaveState = callbacks.onSaveState,
        onQueueRetag = function(friendKey, newTag)
            if tagsFeature then
                tagsFeature:queueRetag(friendKey, newTag)
            end
        end
    }
    
    local renderFriendsTable = function(groupFriends, renderState, renderCallbacks, sectionTag)
        M.RenderCompactFriendsList(groupFriends, sectionTag, dataModule, disableInteraction)
    end
    
    -- Read groupByOnlineStatus directly from gConfig (set in General tab)
    local groupByOnlineStatus = gConfig and gConfig.quickOnlineSettings and gConfig.quickOnlineSettings.groupByOnlineStatus or false
    if groupByOnlineStatus then
        -- Split friends by online/offline status first
        local onlineFriends = {}
        local offlineFriends = {}
        for _, friend in ipairs(filteredFriends) do
            if friend.isOnline then
                table.insert(onlineFriends, friend)
            else
                table.insert(offlineFriends, friend)
            end
        end
        
        -- Group online friends by tag
        local onlineGroups = taggrouper.groupFriendsByTag(onlineFriends, tagOrder, getFriendTag)
        taggrouper.sortAllGroups(onlineGroups, sortMode, sortDirection)
        
        -- Group offline friends by tag
        local offlineGroups = taggrouper.groupFriendsByTag(offlineFriends, tagOrder, getFriendTag)
        taggrouper.sortAllGroups(offlineGroups, sortMode, sortDirection)
        
        -- Render Online section
        local onlineCount = #onlineFriends
        -- Auto-collapse if empty
        local onlineShouldBeOpen = onlineCount > 0 and not state.collapsedOnlineSection
        if disableInteraction then
            imgui.SetNextItemOpen(onlineShouldBeOpen, ImGuiCond_Always)
        elseif not overlayEnabled then
            imgui.SetNextItemOpen(onlineShouldBeOpen)
        end
        if overlayEnabled or disableInteraction then
            imgui.PushStyleColor(ImGuiCol_Header, {0.0, 0.0, 0.0, 0.0})
            imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0.0, 0.0, 0.0, 0.0})
            imgui.PushStyleColor(ImGuiCol_HeaderActive, {0.0, 0.0, 0.0, 0.0})
        end
        local onlineExpanded = imgui.CollapsingHeader("Online (" .. onlineCount .. ")##qo_online_section")
        if overlayEnabled or disableInteraction then
            imgui.PopStyleColor(3)
        end
        if not overlayEnabled and not disableInteraction and imgui.IsItemClicked() then
            state.collapsedOnlineSection = not state.collapsedOnlineSection
            M.SaveWindowState()
        end
        
        if onlineExpanded then
            imgui.Indent(10)
            CollapsibleTagSection.RenderAllSections(onlineGroups, state, sectionCallbacks, renderFriendsTable, "_qo_online", overlayEnabled, disableInteraction, true)
            imgui.Unindent(10)
        end
        
        -- Render Offline section
        local offlineCount = #offlineFriends
        -- Auto-collapse if empty
        local offlineShouldBeOpen = offlineCount > 0 and not state.collapsedOfflineSection
        if disableInteraction then
            imgui.SetNextItemOpen(offlineShouldBeOpen, ImGuiCond_Always)
        elseif not overlayEnabled then
            imgui.SetNextItemOpen(offlineShouldBeOpen)
        end
        if overlayEnabled or disableInteraction then
            imgui.PushStyleColor(ImGuiCol_Header, {0.0, 0.0, 0.0, 0.0})
            imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0.0, 0.0, 0.0, 0.0})
            imgui.PushStyleColor(ImGuiCol_HeaderActive, {0.0, 0.0, 0.0, 0.0})
        end
        local offlineExpanded = imgui.CollapsingHeader("Offline (" .. offlineCount .. ")##qo_offline_section")
        if overlayEnabled or disableInteraction then
            imgui.PopStyleColor(3)
        end
        if not overlayEnabled and not disableInteraction and imgui.IsItemClicked() then
            state.collapsedOfflineSection = not state.collapsedOfflineSection
            M.SaveWindowState()
        end
        
        if offlineExpanded then
            imgui.Indent(10)
            CollapsibleTagSection.RenderAllSections(offlineGroups, state, sectionCallbacks, renderFriendsTable, "_qo_offline", overlayEnabled, disableInteraction, true)
            imgui.Unindent(10)
        end
    else
        -- Default behavior: just tag sections without online/offline grouping
        local groups = taggrouper.groupFriendsByTag(filteredFriends, tagOrder, getFriendTag)
        taggrouper.sortAllGroups(groups, sortMode, sortDirection)
        CollapsibleTagSection.RenderAllSections(groups, state, sectionCallbacks, renderFriendsTable, nil, overlayEnabled, disableInteraction, true)
    end
    
    if tagsFeature then
        tagsFeature:flushRetagQueue()
    end
end

function M.RenderCompactFriendsList(friends, sectionTag, dataModule, disableInteraction)
    disableInteraction = disableInteraction or false
    local app = _G.FFXIFriendListApp
    local hoverSettings = nil
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        hoverSettings = prefs and prefs.quickOnlineHoverTooltip
    end
    
    local tableId = "##quick_online_table_" .. (sectionTag or "default")
    if imgui.BeginTable(tableId, 1, 0) then
        imgui.TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch)
        
        for i, friend in ipairs(friends) do
            imgui.TableNextRow()
            imgui.TableNextColumn()
            
            local friendName = utils.capitalizeName(utils.getDisplayName(friend))
            local isOnline = friend.isOnline == true
            local isAway = friend.isAway == true
            local uniqueId = (sectionTag or "qo") .. "_" .. i
            
            if not icons.RenderStatusIcon(isOnline, false, 16, isAway) then
                if isAway then
                    imgui.TextColored({1.0, 0.7, 0.2, 1.0}, "A")
                elseif isOnline then
                    imgui.TextColored({0.0, 1.0, 0.0, 1.0}, "O")
                else
                    imgui.TextColored({0.5, 0.5, 0.5, 1.0}, "O")
                end
            end
            imgui.SameLine()
            
            if not isOnline then
                imgui.PushStyleColor(ImGuiCol_Text, {0.6, 0.6, 0.6, 1.0})
            end
            
            -- Render the friend name - either as text (disabled) or selectable (interactive)
            local itemHovered = false
            if disableInteraction then
                imgui.Text(friendName)
                -- Use TooltipHelper for hover detection even when interaction is disabled
                itemHovered = TooltipHelper.isItemHovered(true)
            else
                if imgui.Selectable(friendName .. "##friend_" .. uniqueId, false, ImGuiSelectableFlags_SpanAllColumns) then
                    if state.selectedFriendForDetails and state.selectedFriendForDetails.name == friend.name then
                        state.selectedFriendForDetails = nil
                    else
                        state.selectedFriendForDetails = friend
                    end
                end
                
                if imgui.BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID) then
                    local friendKey = tagcore.getFriendKey(friend)
                    if friendKey then
                        local dragState = FriendsTable.getDragState()
                        dragState.isDragging = true
                        dragState.friendKey = friendKey
                        dragState.friendName = friendName
                        imgui.Text("Move: " .. friendName)
                    end
                    imgui.EndDragDropSource()
                else
                    local dragState = FriendsTable.getDragState()
                    if dragState.isDragging and dragState.friendKey == tagcore.getFriendKey(friend) then
                        FriendsTable.endDrag()
                    end
                end
                
                itemHovered = imgui.IsItemHovered()
                
                if imgui.BeginPopupContextItem("##friend_context_" .. uniqueId) then
                    FriendContextMenu.Render(friend, state, M.GetCallbacks(dataModule))
                    imgui.EndPopup()
                end
            end
            
            -- Render tooltip if hovered (works for both disabled and enabled interaction)
            if itemHovered then
                local forceAll = InputHelper.isShiftDown()
                if overlayEnabled and tooltipBgEnabled then
                    local app = _G.FFXIFriendListApp
                    local popupBgColor = {0.2, 0.2, 0.2, 0.9}
                    if app and app.features and app.features.themes then
                        local themesFeature = app.features.themes
                        local themeIndex = themesFeature:getThemeIndex()
                        if themeIndex ~= -2 then
                            local themeColors = themesFeature:getCurrentThemeColors()
                            local bgAlpha = themesFeature:getBackgroundAlpha() or 0.95
                            if themeColors then
                                if themeColors.windowBgColor then
                                    popupBgColor = {
                                        themeColors.windowBgColor.r,
                                        themeColors.windowBgColor.g,
                                        themeColors.windowBgColor.b,
                                        themeColors.windowBgColor.a * bgAlpha
                                    }
                                elseif themeColors.frameBgColor then
                                    popupBgColor = {
                                        themeColors.frameBgColor.r,
                                        themeColors.frameBgColor.g,
                                        themeColors.frameBgColor.b,
                                        themeColors.frameBgColor.a * bgAlpha
                                    }
                                end
                            end
                        end
                    end
                    imgui.PushStyleColor(ImGuiCol_PopupBg, popupBgColor)
                    HoverTooltip.Render(friend, hoverSettings, forceAll)
                    imgui.PopStyleColor()
                else
                    HoverTooltip.Render(friend, hoverSettings, forceAll)
                end
            end
            
            if not isOnline then
                imgui.PopStyleColor()
            end
        end
        
        imgui.EndTable()
    end
end

-- Get callbacks for shared components (matches main window pattern)
function M.GetCallbacks(dataModule)
    local app = _G.FFXIFriendListApp
    
    return {
        onRefresh = function()
            if app and app.features and app.features.friends then
                app.features.friends:refresh()
            end
        end,
        
        onRemoveFriend = function(friendName)
            if app and app.features and app.features.friends then
                app.features.friends:removeFriend(friendName)
            end
        end,
        
        onSendTell = function(friendName)
            local chatManager = AshitaCore:GetChatManager()
            if chatManager then
                -- Use sendkey to open chat with "/"
                chatManager:QueueCommand(-1, '/sendkey / down')
                -- Wait for chat input to open, then set the tell command
                ashita.tasks.once(0, function()
                    while chatManager:IsInputOpen() ~= 0x11 do
                        coroutine.sleepf(1)
                    end
                    chatManager:SetInputText('/tell ' .. capitalizeName(friendName) .. ' ')
                end)
            end
        end,
        
        onOpenNoteEditor = function(friendName)
            local noteEditorModule = require('modules.noteeditor')
            if noteEditorModule and noteEditorModule.OpenEditor then
                noteEditorModule.OpenEditor(friendName)
            end
        end,
        
        onDeleteNote = function(friendName)
            -- Note deletion handled by note editor or friend details
        end,
        
        onSaveState = M.SaveWindowState,
    }
end

-- Save window state
function M.SaveWindowState()
    if not gConfig then
        return
    end
    
    if not gConfig.windows then
        gConfig.windows = {}
    end
    if not gConfig.windows.quickOnline then
        gConfig.windows.quickOnline = {}
    end
    
    local windowState = gConfig.windows.quickOnline
    
    -- Save visibility (from the single source of truth)
    windowState.visible = gConfig.showQuickOnline or false
    
    -- Save position and size if window is open
    if gConfig.showQuickOnline then
        local posX, posY = imgui.GetWindowPos()
        if posX and posY then
            windowState.posX = posX
            windowState.posY = posY
        end
        
        local sizeX, sizeY = imgui.GetWindowSize()
        if sizeX and sizeY then
            windowState.sizeX = sizeX
            windowState.sizeY = sizeY
        end
    end
    
    windowState.locked = state.locked
    
    -- Save quick online settings
    if not gConfig.quickOnlineSettings then
        gConfig.quickOnlineSettings = {}
    end
    
    local settings = gConfig.quickOnlineSettings
    settings.sort = {
        column = state.sortColumn,
        direction = state.sortDirection
    }
    settings.filter = state.filterText[1] or ""
    settings.columns = {
        name = state.columnVisible.name,
        job = state.columnVisible.job,
        zone = state.columnVisible.zone,
        status = state.columnVisible.status
    }
    -- Note: groupByOnlineStatus and hideTopBar are controlled by General tab, don't overwrite them here
    settings.collapsedOnlineSection = state.collapsedOnlineSection
    settings.collapsedOfflineSection = state.collapsedOfflineSection
    
    -- Persist to disk
    local settings = require('libs.settings')
    if settings and settings.save then
        settings.save()
    end
end

-- Simple error window when server auto-detection fails
function M.RenderServerNotDetectedWindow()
    local screenWidth = scaling.window.w
    local screenHeight = scaling.window.h
    
    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_AlwaysAutoResize
    )
    
    -- Center on screen
    local windowWidth = 400
    local windowHeight = 200
    local posX = (screenWidth - windowWidth) / 2
    local posY = (screenHeight - windowHeight) / 2
    imgui.SetNextWindowPos({posX, posY}, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({windowWidth, 0}, ImGuiCond_FirstUseEver)
    
    -- Apply theme
    local themePushed = M.ApplyTheme()
    
    local windowOpenTable = {true}
    if not imgui.Begin("Server Not Detected##qo_servernotdetected", windowOpenTable, windowFlags) then
        imgui.End()
        M.PopTheme(themePushed)
        return
    end
    
    local ServerProfiles = require("core.ServerProfiles")
    local loadError = ServerProfiles.getLoadError and ServerProfiles.getLoadError()
    
    imgui.TextColored({1.0, 0.3, 0.3, 1.0}, "Server Detection Failed")
    imgui.Separator()
    imgui.Spacing()
    
    if loadError then
        imgui.TextWrapped("Could not fetch server list: " .. tostring(loadError))
    else
        imgui.TextWrapped("Your FFXI server could not be auto-detected.")
    end
    
    imgui.Spacing()
    imgui.TextWrapped("This addon currently supports: Horizon, Eden")
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    imgui.TextColored({0.5, 0.8, 1.0, 1.0}, "Need your server added?")
    imgui.TextWrapped("Contact Tanyrus on Discord to request support for your server.")
    imgui.Spacing()
    
    if imgui.Button("Join Discord Server", {200, 30}) then
        os.execute('start https://discord.gg/horizonfriendlist')
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Click to open Discord (opens in default browser)")
    end
    
    imgui.End()
    M.PopTheme(themePushed)
end

-- DEPRECATED: Server selection window replaced by auto-detection only
function M.RenderServerSelectionWindow()
    local serverSelectionData = require('modules.serverselection.data')
    
    -- Ensure data module is initialized
    if not serverSelectionData.GetServers or #(serverSelectionData.GetServers() or {}) == 0 then
        if serverSelectionData.Initialize then
            serverSelectionData.Initialize({})
        end
    end
    
    if serverSelectionData.Update then
        serverSelectionData.Update()
    end
    
    local screenWidth = scaling.window.w
    local screenHeight = scaling.window.h
    
    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_AlwaysAutoResize
    )
    
    -- Center on screen when first opened
    if state.serverWindowNeedsCenter then
        local windowWidth = 350
        local windowHeight = 300
        local posX = (screenWidth - windowWidth) / 2
        local posY = (screenHeight - windowHeight) / 2
        imgui.SetNextWindowPos({posX, posY}, ImGuiCond_Always)
        state.serverWindowNeedsCenter = false
    end
    
    imgui.SetNextWindowSize({350, 0}, ImGuiCond_FirstUseEver)
    
    -- Apply theme
    local themePushed = false
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        local success, err = pcall(function()
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
        end)
    end
    
    local windowOpenTable = {true}
    if not imgui.Begin("Select Server##serverselection_qo", windowOpenTable, windowFlags) then
        imgui.End()
        if themePushed then ThemeHelper.popThemeStyles() end
        return
    end
    
    if not windowOpenTable[1] then
        state.serverSelectionOpened = false
        imgui.End()
        if themePushed then ThemeHelper.popThemeStyles() end
        return
    end
    
    -- Apply button rounding for this popup
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4)
    
    imgui.TextWrapped("Please select your server to connect to the FFXIFriendList service.")
    imgui.Separator()
    imgui.TextColored({1.0, 0.8, 0.0, 1.0}, "Warning:")
    imgui.TextWrapped("If you select the wrong server, you may not be able to find your friends.")
    imgui.Separator()
    
    local servers = serverSelectionData.GetServers() or {}
    local draftServerId = serverSelectionData.GetDraftSelectedServerId() or ""
    local detectedServerId = serverSelectionData.GetDetectedServerId()
    local detectedServerName = serverSelectionData.GetDetectedServerName()
    
    if #servers == 0 and not state.serverListRefreshTriggered then
        serverSelectionData.RefreshServerList()
        state.serverListRefreshTriggered = true
    end
    
    if detectedServerId and detectedServerName then
        imgui.Text("Detected server: " .. detectedServerName)
        imgui.Spacing()
    end
    
    if #servers == 0 then
        imgui.Text("Loading servers...")
        if imgui.Button("Refresh") then
            serverSelectionData.RefreshServerList()
        end
    else
        local previewText = "Select a server..."
        for _, server in ipairs(servers) do
            if server.id == draftServerId then
                previewText = server.name or server.id
                break
            end
        end
        
        if imgui.BeginCombo("Server", previewText) then
            for _, server in ipairs(servers) do
                local isSelected = (server.id == draftServerId)
                if detectedServerId and server.id == detectedServerId then
                    imgui.PushStyleColor(ImGuiCol_Text, {0.0, 1.0, 0.0, 1.0})
                end
                if imgui.Selectable(server.name or server.id, isSelected) then
                    serverSelectionData.SetDraftSelectedServerId(server.id)
                end
                if detectedServerId and server.id == detectedServerId then
                    imgui.PopStyleColor()
                end
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndCombo()
        end
    end
    
    imgui.Separator()
    
    local canSave = draftServerId ~= "" and draftServerId ~= nil
    if canSave then
        if imgui.Button("Save", {120, 0}) then
            serverSelectionData.SaveServerSelection(draftServerId)
            state.serverSelectionOpened = false
        end
    else
        imgui.PushStyleColor(ImGuiCol_Button, {0.3, 0.3, 0.3, 1.0})
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.3, 0.3, 0.3, 1.0})
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.3, 0.3, 0.3, 1.0})
        imgui.PushStyleColor(ImGuiCol_Text, {0.5, 0.5, 0.5, 1.0})
        imgui.Button("Save", {120, 0})
        imgui.PopStyleColor(4)
    end
    
    imgui.SameLine()
    
    if imgui.Button("Close", {120, 0}) then
        state.serverSelectionOpened = false
    end
    
    -- Pop button rounding
    imgui.PopStyleVar()
    
    imgui.End()
    if themePushed then ThemeHelper.popThemeStyles() end
end

-- Cleanup
function M.Cleanup()
    state.initialized = false
end

return M

