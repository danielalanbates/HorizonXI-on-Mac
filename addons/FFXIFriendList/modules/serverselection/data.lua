--[[
* ServerSelection Module - Data
* State management: reads server list from app.features.serverlist
]]

local M = {}

-- Module state
local state = {
    initialized = false,
    servers = {},
    selectedServerId = nil,
    draftSelectedServerId = "",
    detectedServerId = nil,
    detectedServerName = nil,
    state = "idle",  -- idle, loading, error
    lastError = nil,
    hasSavedServer = false
}

-- Initialize data module
function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
end

-- Update data from app state (called every frame before render)
function M.Update()
    if not state.initialized then
        return
    end
    
    -- Get app instance from global
    local app = _G.FFXIFriendListApp
    if not app then
        return
    end
    
    -- Get app state
    local App = require("app.App")
    local appState = App.getState(app)
    if not appState then
        return
    end
    
    -- Update server list
    if appState.serverlist and appState.serverlist.servers then
        state.servers = appState.serverlist.servers or {}
    end
    
    -- Update selected server
    if appState.serverlist and appState.serverlist.selected then
        state.selectedServerId = appState.serverlist.selected.id
        state.hasSavedServer = (state.selectedServerId ~= nil)
    else
        state.selectedServerId = nil
        state.hasSavedServer = false
    end
    
    -- Update state
    if appState.serverlist then
        state.state = appState.serverlist.state or "idle"
        state.lastError = appState.serverlist.lastError
    end
    
    -- Initialize draft with detected server if available and not already set
    if state.draftSelectedServerId == "" and state.detectedServerId then
        for _, server in ipairs(state.servers) do
            if server.id == state.detectedServerId then
                state.draftSelectedServerId = state.detectedServerId
                break
            end
        end
    end
end

-- Set detected server suggestion
function M.SetDetectedServerSuggestion(serverId, serverName)
    state.detectedServerId = serverId
    state.detectedServerName = serverName
    
    -- Initialize draft if not already set
    if state.draftSelectedServerId == "" then
        for _, server in ipairs(state.servers) do
            if server.id == serverId then
                state.draftSelectedServerId = serverId
                break
            end
        end
    end
end

-- Clear detected server suggestion
function M.ClearDetectedServerSuggestion()
    state.detectedServerId = nil
    state.detectedServerName = nil
end

-- Set draft selected server ID
function M.SetDraftSelectedServerId(serverId)
    state.draftSelectedServerId = serverId or ""
end

-- Get draft selected server ID
function M.GetDraftSelectedServerId()
    return state.draftSelectedServerId or ""
end

-- Get servers
function M.GetServers()
    return state.servers
end

-- Get state
function M.GetState()
    return state.state
end

-- Get error
function M.GetError()
    return state.lastError
end

-- Check if has saved server
function M.HasSavedServer()
    -- Check both app state and serverlist feature
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.serverlist then
        if app.features.serverlist:isServerSelected() then
            return true
        end
    end
    return state.hasSavedServer
end

-- Get detected server ID
function M.GetDetectedServerId()
    return state.detectedServerId
end

-- Get detected server name
function M.GetDetectedServerName()
    return state.detectedServerName
end

-- Refresh server list
function M.RefreshServerList()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.serverlist then
        app.features.serverlist:refresh()
    end
end

-- Save server selection
function M.SaveServerSelection(serverId)
    if not serverId or serverId == "" then
        return false
    end
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.serverlist then
        if app.features.serverlist:selectServer(serverId) then
            -- Find server info
            local selectedServer = app.features.serverlist:getSelected()
            if selectedServer then
                local baseUrl = selectedServer.baseUrl or selectedServer.url
                if baseUrl then
                    -- Update connection feature with new server
                    if app.features.connection then
                        app.features.connection:setServer(serverId, baseUrl)
                    end
                    
                    -- Save to config (must be done before config.save() is called)
                    if _G.gConfig then
                        if not _G.gConfig.data then
                            _G.gConfig.data = {}
                        end
                        if not _G.gConfig.data.serverSelection then
                            _G.gConfig.data.serverSelection = {}
                        end
                        _G.gConfig.data.serverSelection.savedServerId = serverId
                        _G.gConfig.data.serverSelection.savedServerBaseUrl = baseUrl
                        
                        -- Check if help has been seen for this server
                        if not _G.gConfig.data.serverSelection.helpSeenPerServer then
                            _G.gConfig.data.serverSelection.helpSeenPerServer = {}
                        end
                        
                        local helpSeen = _G.gConfig.data.serverSelection.helpSeenPerServer[serverId]
                        if not helpSeen then
                            -- Mark as seen
                            _G.gConfig.data.serverSelection.helpSeenPerServer[serverId] = true
                            -- Trigger help tab auto-open
                            M.triggerHelpTabAutoOpen = true
                        end
                    end
                    
                    return true
                end
            end
        end
    end
    
    return false
end

-- Check if help tab should auto-open
function M.ShouldAutoOpenHelpTab()
    local result = M.triggerHelpTabAutoOpen or false
    M.triggerHelpTabAutoOpen = false
    return result
end

-- Cleanup
function M.Cleanup()
    state.initialized = false
end

return M

