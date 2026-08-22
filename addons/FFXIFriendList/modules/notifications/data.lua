--[[
* Notifications Module - Data
* State management (read-only from app state)
]]

local M = {}

local state = {
    initialized = false,
    toasts = {},
    eventSystemActive = false
}

function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
end

function M.Update()
    if not state.initialized then
        return
    end
    
    local app = _G.FFXIFriendListApp
    if not app then
        return
    end
    
    local App = require("app.App")
    local appState = App.getState(app)
    if not appState then
        return
    end
    
    if appState.notifications then
        -- Get toasts from notifications feature
        state.toasts = appState.notifications.toasts or {}
        state.eventSystemActive = appState.notifications.eventSystemActive or false
    end
end

function M.GetToasts()
    return state.toasts
end

function M.GetEventSystemActive()
    return state.eventSystemActive
end

function M.Cleanup()
    state.initialized = false
    state.toasts = {}
end

return M

