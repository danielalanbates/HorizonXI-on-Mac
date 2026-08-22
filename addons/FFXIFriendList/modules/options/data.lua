--[[
* Options Module - Data
* State management (read-only from app state)
]]

local M = {}

local state = {
    initialized = false,
    preferences = nil,
    connectionState = "uninitialized"
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
    
    if appState.preferences then
        state.preferences = appState.preferences.preferences
    end
    
    if appState.connection then
        state.connectionState = appState.connection.status or "uninitialized"
    end
end

function M.GetPreferences()
    return state.preferences
end

function M.GetConnectionState()
    return state.connectionState
end

function M.Cleanup()
    state.initialized = false
    state.preferences = nil
end

return M

