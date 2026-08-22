--[[
* FriendList Module - Data
* State management and business logic (read-only from app state)
]]

local M = {}

-- Module state
local state = {
    initialized = false,
    friends = {},
    incomingRequests = {},
    outgoingRequests = {},
    characters = {},
    charactersFetched = false,
    connectionState = "uninitialized",
    wsConnectionState = "DISCONNECTED",
    wsStatusText = "Disconnected",
    wsStatusDetail = "",
    friendsState = "idle",  -- Track friends sync state: idle, syncing, error
    lastError = nil,
    lastUpdatedAt = nil
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
    
    -- Get app instance from global (set by entry file)
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
    
    -- Update friends state
    if appState.friends then
        state.friends = appState.friends.friends or {}
        state.incomingRequests = appState.friends.incomingRequests or {}
        state.outgoingRequests = appState.friends.outgoingRequests or {}
        state.lastError = appState.friends.lastError
        state.lastUpdatedAt = appState.friends.lastUpdatedAt
        state.friendsState = appState.friends.state or "idle"  -- Track sync state
    else
        state.friendsState = "idle"
    end
    
    -- Update connection state from connection feature (not friends feature)
    if appState.connection then
        if appState.connection.isConnected then
            state.connectionState = "connected"
        elseif appState.connection.state then
            -- Normalize state to lowercase for comparison
            state.connectionState = string.lower(appState.connection.state)
        else
            state.connectionState = "uninitialized"
        end
    else
        state.connectionState = "uninitialized"
    end
    
    -- Update WebSocket connection state for real-time status
    if appState.wsConnection then
        state.wsConnectionState = appState.wsConnection.state or "DISCONNECTED"
        state.wsStatusText = appState.wsConnection.statusText or "Disconnected"
        state.wsStatusDetail = appState.wsConnection.statusDetail or ""
    end
    
    -- Fetch characters list if we have app access (only once)
    if app and app.features and app.features.friends and not state.charactersFetched then
        state.charactersFetched = true
        M._FetchCharacters(app)
    end
end

-- Get friends list
function M.GetFriends()
    return state.friends
end

-- Get incoming requests
function M.GetIncomingRequests()
    return state.incomingRequests
end

-- Get outgoing requests
function M.GetOutgoingRequests()
    return state.outgoingRequests
end

-- Get incoming requests count
function M.GetIncomingRequestsCount()
    return #state.incomingRequests
end

-- Get connection state
function M.GetConnectionState()
    return state.connectionState
end

-- Get last error
function M.GetLastError()
    return state.lastError
end

-- Get last updated timestamp
function M.GetLastUpdatedAt()
    return state.lastUpdatedAt
end

-- Get friends sync state
function M.GetFriendsState()
    return state.friendsState or "idle"
end

-- Check if connected
function M.IsConnected()
    return state.connectionState == "connected"
end

-- Get WebSocket connection status for UI display
function M.GetWsStatus()
    return state.wsStatusText, state.wsStatusDetail
end

-- Check if WebSocket is connected
function M.IsWsConnected()
    return state.wsConnectionState == "CONNECTED"
end

-- Get blocked players list
function M.GetBlockedPlayers()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.blocklist then
        return app.features.blocklist:getBlockedList()
    end
    return {}
end

-- Get blocked players count
function M.GetBlockedPlayersCount()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.blocklist then
        return app.features.blocklist:getBlockedCount()
    end
    return 0
end

-- Get characters list
function M.GetCharacters()
    return state.characters
end

-- Fetch characters from server
function M._FetchCharacters(app)
    if not app or not app.features or not app.features.friends then
        return
    end
    
    -- Call the friends feature's refresh method which includes character data
    local friends = app.features.friends
    if friends and friends._fetchCharacterList then
        friends:_fetchCharacterList()
    end
end

-- Set characters (called by friends feature)
function M.SetCharacters(characters)
    state.characters = characters or {}
end

-- Cleanup
function M.Cleanup()
    state.initialized = false
    state.friends = {}
    state.incomingRequests = {}
    state.outgoingRequests = {}
    state.characters = {}
    state.charactersFetched = false
end

return M

