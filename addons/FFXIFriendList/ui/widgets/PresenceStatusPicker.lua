-- ui/widgets/PresenceStatusPicker.lua
-- Shared component for Online/Away/Invisible status selection
-- Syncs with server via preferences feature

local imgui = require('imgui')

local M = {}

-- Status display configuration
local STATUS_CONFIG = {
    online = {
        label = "Online",
        tooltip = "You appear online to friends with full status.",
        showOnlineStatus = true,
    },
    away = {
        label = "Away",
        tooltip = "You appear online but marked as 'Away' to friends.",
        showOnlineStatus = true,
    },
    invisible = {
        label = "Invisible",
        tooltip = "You appear offline to friends.\nFriends will not see your online status or activity.",
        showOnlineStatus = false,
    },
}

local STATUS_ORDER = { "online", "away", "invisible" }

--- Get the preferences feature from the app
-- @return table|nil The preferences feature or nil if unavailable
local function getPreferencesFeature()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        return app.features.preferences
    end
    return nil
end

--- Get current presence status
-- @return string The current status ("online", "away", or "invisible")
function M.getCurrentStatus()
    local prefsFeature = getPreferencesFeature()
    if prefsFeature then
        local prefs = prefsFeature:getPrefs()
        return prefs.presenceStatus or "online"
    end
    return "online"
end

--- Set presence status and sync to server
-- @param status string The status to set ("online", "away", or "invisible")
local function setStatus(status)
    local config = STATUS_CONFIG[status]
    if not config then return end
    
    local prefsFeature = getPreferencesFeature()
    if not prefsFeature then return end
    
    prefsFeature:setPref("presenceStatus", status)
    prefsFeature:setPref("showOnlineStatus", config.showOnlineStatus)
    prefsFeature:save()
    prefsFeature:syncToServer()
end

--- Render presence status as radio buttons (horizontal layout)
-- @param idSuffix string Optional ID suffix to avoid conflicts
-- @param showTooltips boolean Whether to show tooltips (default: true)
function M.RenderRadioButtons(idSuffix, showTooltips)
    idSuffix = idSuffix or ""
    if showTooltips == nil then showTooltips = true end
    
    local currentStatus = M.getCurrentStatus()
    
    for i, status in ipairs(STATUS_ORDER) do
        local config = STATUS_CONFIG[status]
        local isSelected = (currentStatus == status)
        
        if i > 1 then
            imgui.SameLine()
        end
        
        if imgui.RadioButton(config.label .. "##presence_" .. status .. idSuffix, isSelected) then
            if not isSelected then
                setStatus(status)
            end
        end
        
        if showTooltips and imgui.IsItemHovered() then
            imgui.SetTooltip(config.tooltip)
        end
    end
end

--- Render presence status as compact radio buttons (for toolbar)
-- Same as RenderRadioButtons but with smaller spacing
-- @param idSuffix string Optional ID suffix
function M.RenderCompact(idSuffix)
    M.RenderRadioButtons(idSuffix, true)
end

return M
