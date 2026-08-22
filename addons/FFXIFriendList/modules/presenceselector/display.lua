-- modules/presenceselector/display.lua
-- Presence selector that appears before character detection
-- Allows user to set their online status before connecting

local imgui = require('imgui')

local M = {}

-- State for the selector
local state = {
    selectedStatus = 'online', -- Default to online
    hasSetStatus = false,
    lastUpdatedAt = 0,
    pendingServerUpdate = false -- Track if server update is in progress
}

function M.Initialize(settings)
    -- Try to load current preference from app if available
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs and prefs.presenceStatus then
            state.selectedStatus = prefs.presenceStatus
            return
        end
    end
    
    -- Fall back to saved local setting if server preference not available
    local savedSettings = require('libs.settings')
    local data = savedSettings.get('data')
    
    if data and data.presenceSelector and data.presenceSelector.lastStatus then
        state.selectedStatus = data.presenceSelector.lastStatus
    else
        -- Default to online if no saved preference
        state.selectedStatus = 'online'
    end
end

function M.Render()
    -- Only render if game is NOT ready yet
    local App = require('app.App')
    if App.isGameReady() then
        return -- Character is loaded, hide selector
    end
    
    -- Position in top-left corner
    imgui.SetNextWindowPos({10, 10}, ImGuiCond_Always)
    imgui.SetNextWindowSize({250, 175}, ImGuiCond_Always)
    
    -- No close button, always on top, no resize
    local flags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoSavedSettings
    )
    
    local visible = imgui.Begin("Presence Selector", true, flags)
    if visible then
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "Login Status")
        imgui.Separator()
        imgui.Spacing()
        imgui.Text("Select your login status:")
        imgui.Spacing()
        
        -- Simple radio buttons
        if imgui.RadioButton("Online", state.selectedStatus == 'online') then
            if state.selectedStatus ~= 'online' then
                state.selectedStatus = 'online'
                state.hasSetStatus = true
                state.lastUpdatedAt = os.time() * 1000
                M.SaveStatus()
                M.UpdateServerStatus()
            end
        end
        
        if imgui.RadioButton("Away", state.selectedStatus == 'away') then
            if state.selectedStatus ~= 'away' then
                state.selectedStatus = 'away'
                state.hasSetStatus = true
                state.lastUpdatedAt = os.time() * 1000
                M.SaveStatus()
                M.UpdateServerStatus()
            end
        end
        
        if imgui.RadioButton("Invisible", state.selectedStatus == 'invisible') then
            if state.selectedStatus ~= 'invisible' then
                state.selectedStatus = 'invisible'
                state.hasSetStatus = true
                state.lastUpdatedAt = os.time() * 1000
                M.SaveStatus()
                M.UpdateServerStatus()
            end
        end
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        imgui.TextDisabled("Will connect as:")
        imgui.SameLine()
        
        -- Show status color-coded
        local statusColors = {
            online = {0.0, 1.0, 0.0, 1.0},   -- Green
            away = {1.0, 0.7, 0.0, 1.0},     -- Orange
            invisible = {0.5, 0.5, 0.5, 1.0} -- Gray
        }
        local color = statusColors[state.selectedStatus] or {1.0, 1.0, 1.0, 1.0}
        
        local statusLabels = {
            online = "Online",
            away = "Away",
            invisible = "Invisible"
        }
        imgui.TextColored(color, statusLabels[state.selectedStatus] or state.selectedStatus)
    end
    imgui.End()
end

function M.SaveStatus()
    -- Save to persisted settings so it remembers across restarts
    local savedSettings = require('libs.settings')
    local data = savedSettings.get('data') or {}
    
    if not data.presenceSelector then
        data.presenceSelector = {}
    end
    
    data.presenceSelector.lastStatus = state.selectedStatus
    
    savedSettings.set('data', data)
    savedSettings.save()
end

function M.UpdateServerStatus()
    -- Just mark that we have a pending update
    -- The actual HTTP request will happen when connection is ready
    state.pendingServerUpdate = true
end

-- Check if there's a pending status update that needs to be synced
function M.HasPendingUpdate()
    return state.hasSetStatus and state.pendingServerUpdate
end

-- Apply the pending status update using a direct HTTP call
function M.ApplyPendingUpdate(app)
    local success, err = pcall(function()
        if not state.hasSetStatus or not state.pendingServerUpdate then
            return false
        end
        
        if not app then
            return false
        end
        
        if not app.deps then
            return false
        end
        
        if not app.deps.net then
            return false
        end
        
        if not app.features then
            return false
        end
        
        if not app.features.connection then
            return false
        end
        
        local connection = app.features.connection
        if not connection.isConnected then
            return false
        end
        
        if not connection:isConnected() then
            return false
        end
        
        local apiKey = connection.apiKey
        if not apiKey or apiKey == "" then
            return false
        end
        
        if not connection.getBaseUrl then
            return false
        end
        
        local baseUrl = connection:getBaseUrl()
        if not baseUrl or baseUrl == "" then
            return false
        end
        
        -- Make direct PATCH request to update presence status
        local url = baseUrl .. "/api/preferences"
        local body = string.format('{"presenceStatus":"%s"}', state.selectedStatus)
        
        app.deps.net.request({
            url = url,
            method = "PATCH",
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. apiKey,
            },
            body = body,
            callback = function(success, response)
                state.pendingServerUpdate = false
            end
        })
        
        return true
    end)
    
    if not success then
        return false
    end
    
    return true
end

function M.GetSelectedStatus()
    return state.selectedStatus
end

function M.IsPendingServerUpdate()
    return state.pendingServerUpdate
end

function M.UpdateVisuals(settings)
    -- Nothing to do for visuals
end

function M.SetHidden(hidden)
    -- This module doesn't support hiding - it's always shown when needed
end

function M.Cleanup()
    state.selectedStatus = 'online'
    state.hasSetStatus = false
end

return M
