-- App.lua
-- App orchestrator: composes features and provides unified API
-- Entry file calls initialize() on load and release() on unload

local Connection = require("app.features.connection")
local Friends = require("app.features.friends")
local ServerList = require("app.features.serverlist")
local Themes = require("app.features.themes")
local Notifications = require("app.features.notifications")
local Preferences = require("app.features.preferences")
local Notes = require("app.features.notes")
local Tags = require("app.features.Tags")
local Blocklist = require("app.features.blocklist")
local WsClientAsync = require("platform.services.WsClientAsync")
local WsConnectionManager = require("platform.services.WsConnectionManager")
local WsEventHandler = require("app.features.wsEventHandler")
local VersionCheck = require("app.features.versioncheck")

local App = {}

-- Create app instance with injected dependencies
-- deps: { net, storage, logger, session, time? }
-- Returns app object with features and lifecycle methods
function App.create(deps)
    deps = deps or {}
    
    local app = {
        deps = deps,
        features = {},
        initialized = false,
        _missingFeatureLogged = {},  -- Track missing features for logging
        _startupRefreshCompleted = false,  -- Track if startup refresh has run
        _autoDetectAttempted = false,  -- Track if auto-detect has been tried
        _versionCheckCompleted = false  -- Track if version check has run
    }
    
    -- Initialize features with deps (all use new(deps) signature)
    app.features.connection = Connection.Connection.new(deps)
    
    -- Add connection to deps for features that need it
    deps.connection = app.features.connection
    
    app.features.friends = Friends.Friends.new(deps)
    app.features.serverlist = ServerList.ServerList.new(deps)
    app.features.themes = Themes.Themes.new(deps)
    app.features.notifications = Notifications.Notifications.new(deps)
    app.features.preferences = Preferences.Preferences.new(deps)
    app.features.notes = Notes.Notes.new(deps)
    app.features.tags = Tags.Tags.new(deps)
    app.features.blocklist = Blocklist.Blocklist.new(deps)
    app.features.versionCheck = VersionCheck.VersionCheck.new(deps)
    
    -- Initialize non-blocking WebSocket client
    app.features.wsClient = WsClientAsync.WsClientAsync.new(deps)
    
    -- Initialize connection manager with backoff (wraps wsClient)
    app.features.wsConnectionManager = WsConnectionManager.WsConnectionManager.new({
        logger = deps.logger,
        wsClient = app.features.wsClient,
        connection = app.features.connection,
        time = deps.time
    })
    
    -- Initialize event handler
    app.features.wsEventHandler = WsEventHandler.WsEventHandler.new({
        logger = deps.logger,
        friends = app.features.friends,
        blocklist = app.features.blocklist,
        preferences = app.features.preferences,
        notifications = app.features.notifications,
        connection = app.features.connection,
        tags = app.features.tags,
        notes = app.features.notes,
        time = deps.time
    })
    
    -- Register WS event handler with the event router
    if app.features.wsClient and app.features.wsClient.eventRouter then
        -- Create a single handler that routes to wsEventHandler
        local handler = function(payload, eventType, seq, timestamp)
            if app.features.wsEventHandler then
                app.features.wsEventHandler:handleEvent(payload, eventType, seq, timestamp)
            end
        end
        
        -- Register handlers for all WS event types (from friendlist-server/src/types/events.ts)
        local eventTypes = {
            "connected", "friends_snapshot", "friend_online", "friend_offline",
            "friend_state_changed", "friend_added", "friend_removed",
            "friend_request_received", "friend_request_accepted", "friend_request_declined",
            "blocked", "unblocked", "preferences_updated", "error"
        }
        for _, eventType in ipairs(eventTypes) do
            app.features.wsClient.eventRouter:registerHandler(eventType, handler)
        end
    end
    
    return app
end

-- Initialize app (load persisted state, start connections)
-- Entry file calls this on load event
function App.initialize(app)
    if app.initialized then
        return true
    end
    
    -- Load persisted preferences via deps.storage
    if app.features.preferences and app.features.preferences.load and app.deps.storage then
        local _ = app.features.preferences:load()
    end
    
    -- Load persisted notes via deps.storage
    if app.features.notes and app.features.notes.load and app.deps.storage then
        local _ = app.features.notes:load()
    end
    
    -- Load persisted tags via deps.storage
    if app.features.tags and app.features.tags.load and app.deps.storage then
        local _ = app.features.tags:load()
    end
    
    -- Load persisted themes from file
    if app.features.themes and app.features.themes.loadThemes then
        app.features.themes:loadThemes()
    end
    
    -- Refresh server list on startup (needed for server selection to work)
    -- Note: This is async, servers will populate on a later tick
    if app.features.serverlist and app.features.serverlist.refresh then
        app.features.serverlist:refresh()
    end
    
    -- Sync connection module with serverlist if server is already selected
    -- (will be set from persisted state if available)
    if app.features.connection and app.features.serverlist then
        local selected = app.features.serverlist:getSelected()
        if selected then
            app.features.connection:setServer(selected.id, selected.baseUrl)
        end
    end
    
    app.initialized = true
    return nil
end

-- Check if game is ready and character is loaded
-- Exported as App.isGameReady() for use by entry file and other modules
function App.isGameReady()
    if not AshitaCore then
        return false
    end
    
    local success, result = pcall(function()
        local memoryMgr = AshitaCore:GetMemoryManager()
        if not memoryMgr then
            return false
        end
        
        local party = memoryMgr:GetParty()
        if not party then
            return false
        end
        
        -- Check if character name is available
        local playerName = party:GetMemberName(0)
        if not playerName or playerName == "" then
            return false
        end
        
        return true
    end)
    
    return success and result == true
end

-- Tick app state machines (called with deltaTime in seconds)
-- dtSeconds: delta time in seconds
function App.tick(app, dtSeconds)
    if not app.initialized then
        return
    end
    
    -- Wait for game to be ready and character to be loaded before doing anything
    if not App.isGameReady() then
        return
    end
    
    -- Retry startup refresh if it was delayed waiting for preference update
    if app._retryStartupRefresh then
        local presenceSelectorModule = require('modules.presenceselector.display')
        if presenceSelectorModule.IsPendingServerUpdate and not presenceSelectorModule.IsPendingServerUpdate() then
            -- Update is complete, trigger refresh now
            App._triggerStartupRefresh(app)
        end
    end
    
    -- Attempt auto-detect and auto-select server on first tick after servers are loaded
    -- (deferred from initialize() because refresh() is async)
    if not app._autoDetectAttempted and app.features.serverlist and app.features.serverlist.servers and #app.features.serverlist.servers > 0 then
        app._autoDetectAttempted = true
        local autoConnected = App.attemptAutoDetectAndConnect(app)
        
        -- Check for addon updates after server connection
        if autoConnected and not app._versionCheckCompleted and app.features.versionCheck then
            app._versionCheckCompleted = true
            app.features.versionCheck:checkForUpdates()
        end
        
        -- If auto-connect succeeded, sync connection module with selected server
        if autoConnected and app.features.connection and app.features.serverlist then
            local selected = app.features.serverlist:getSelected()
            if selected then
                app.features.connection:setServer(selected.id, selected.baseUrl)
            end
        end
        
        -- Mark that we've finished the initial server detection attempt
        app._serverDetectionCompleted = true
    end
    
    -- Note: Startup refresh is now triggered immediately in connection.lua:handleAuthResponse()
    -- when connection is established, not waiting for tick. This ensures fastest possible startup.
    
    -- Tick all features that have tick methods
    if app.features.connection and app.features.connection.tick then
        app.features.connection:tick(dtSeconds)
    end
    if app.features.friends and app.features.friends.tick then
        app.features.friends:tick(dtSeconds)
    end
    if app.features.serverlist and app.features.serverlist.tick then
        app.features.serverlist:tick(dtSeconds)
    end
    
    -- Tick WebSocket connection manager (non-blocking backoff/retry)
    if app.features.wsConnectionManager then
        app.features.wsConnectionManager:tick()
    end
    
    -- Tick WebSocket client connect steps (non-blocking step machine)
    if app.features.wsClient and app.features.wsClient.tickConnect then
        app.features.wsClient:tickConnect()
    end
    
    -- Tick WebSocket client messages (non-blocking message processing)
    if app.features.wsClient and app.features.wsClient.tickMessages then
        app.features.wsClient:tickMessages()
    end
end

-- Trigger startup refresh after auto-connect completes
-- Fires all requests in parallel for maximum speed
-- Also establishes WebSocket connection for real-time updates
function App._triggerStartupRefresh(app)
    if not app.features.connection or not app.features.connection:isConnected() then
        return
    end
    
    -- Check if presence selector has a pending status update
    -- Apply it BEFORE checking if pending, so it can start the HTTP request
    local presenceSelectorModule = require('modules.presenceselector.display')
    if presenceSelectorModule.HasPendingUpdate and presenceSelectorModule.HasPendingUpdate() then
        if presenceSelectorModule.ApplyPendingUpdate then
            -- Apply the pending update (starts async HTTP request)
            presenceSelectorModule.ApplyPendingUpdate(app)
        end
    end
    
    -- Now check if the update is still pending (request in flight)
    if presenceSelectorModule.IsPendingServerUpdate and presenceSelectorModule.IsPendingServerUpdate() then
        -- Retry in a moment after the update completes
        app._retryStartupRefresh = true
        return
    end
    
    app._retryStartupRefresh = false
    
    -- Request WebSocket connection via connection manager (non-blocking)
    if app.features.wsConnectionManager then
        app.features.wsConnectionManager:requestConnect()
    end
    
    -- Fire all requests in parallel (they're independent)
    -- 1. Send heartbeat (safety signal only - NOT for friend status)
    if app.features.friends and app.features.friends.sendHeartbeat then
        app.features.friends:sendHeartbeat()
    end
    
    -- 2. Refresh friend list (bootstrap - WS will provide updates after)
    if app.features.friends and app.features.friends.refresh then
        app.features.friends:refresh()
    end
    
    -- 3. Sync preferences from server - parallel with other requests
    if app.features.preferences and app.features.preferences.refresh then
        app.features.preferences:refresh()
    end
    
    -- 4. Refresh friend requests (bootstrap - WS will provide updates after)
    if app.features.friends and app.features.friends.refreshFriendRequests then
        app.features.friends:refreshFriendRequests()
    end
    
    -- 5. Refresh blocklist - parallel with other requests
    if app.features.blocklist and app.features.blocklist.refresh then
        app.features.blocklist:refresh()
    end
end

-- Get read-only state snapshot for UI modules
-- Returns state table even if app not initialized (with uninitialized state)
function App.getState(app)
    local state = {
        connection = { state = "uninitialized" },
        friends = { friends = {}, incomingRequests = {}, outgoingRequests = {} },
        serverlist = { servers = {}, selected = nil },
        themes = { themeIndex = 0, presetName = "" },
        notifications = {},
        preferences = { prefs = {} },
        notes = {},
        tags = { tagOrder = {}, collapsedTags = {}, tagCount = 0 }
    }
    
    if not app.initialized then
        return state
    end
    
    -- Get state from each feature via getState() method only
    -- Never call feature-specific methods like isConnected(), getFriends(), etc.
    if app.features.connection and app.features.connection.getState then
        state.connection = app.features.connection:getState()
    elseif not app._missingFeatureLogged.connection then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing connection feature or getState() method")
        end
        app._missingFeatureLogged.connection = true
    end
    
    if app.features.friends and app.features.friends.getState then
        state.friends = app.features.friends:getState()
    elseif not app._missingFeatureLogged.friends then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing friends feature or getState() method")
        end
        app._missingFeatureLogged.friends = true
    end
    
    if app.features.serverlist and app.features.serverlist.getState then
        state.serverlist = app.features.serverlist:getState()
    elseif not app._missingFeatureLogged.serverlist then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing serverlist feature or getState() method")
        end
        app._missingFeatureLogged.serverlist = true
    end
    
    if app.features.themes and app.features.themes.getState then
        state.themes = app.features.themes:getState()
    elseif not app._missingFeatureLogged.themes then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing themes feature or getState() method")
        end
        app._missingFeatureLogged.themes = true
    end
    
    if app.features.notifications and app.features.notifications.getState then
        state.notifications = app.features.notifications:getState()
    elseif not app._missingFeatureLogged.notifications then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing notifications feature or getState() method")
        end
        app._missingFeatureLogged.notifications = true
    end
    
    if app.features.preferences and app.features.preferences.getState then
        state.preferences = app.features.preferences:getState()
    elseif not app._missingFeatureLogged.preferences then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing preferences feature or getState() method")
        end
        app._missingFeatureLogged.preferences = true
    end
    
    if app.features.notes and app.features.notes.getState then
        state.notes = app.features.notes:getState()
    elseif not app._missingFeatureLogged.notes then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing notes feature or getState() method")
        end
        app._missingFeatureLogged.notes = true
    end
    
    if app.features.tags and app.features.tags.getState then
        state.tags = app.features.tags:getState()
    elseif not app._missingFeatureLogged.tags then
        if app.deps.logger and app.deps.logger.error then
            app.deps.logger.error("[App] Missing tags feature or getState() method")
        end
        app._missingFeatureLogged.tags = true
    end
    
    -- Add WebSocket connection manager status for UI
    if app.features.wsConnectionManager then
        local statusText, statusDetail = app.features.wsConnectionManager:getStatus()
        local retryInfo = app.features.wsConnectionManager:getRetryInfo()
        state.wsConnection = {
            state = app.features.wsConnectionManager:getState(),
            isConnected = app.features.wsConnectionManager:isConnected(),
            statusText = statusText,
            statusDetail = statusDetail,
            retryInfo = retryInfo
        }
    else
        state.wsConnection = {
            state = "UNAVAILABLE",
            isConnected = false,
            statusText = "Unavailable",
            statusDetail = ""
        }
    end
    
    return state
end

-- Release app (save state, cleanup)
-- Entry file calls this on unload event
function App.release(app)
    if not app.initialized then
        return
    end
    
    -- Disconnect WebSocket cleanly
    if app.features.wsClient and app.features.wsClient.disconnect then
        app.features.wsClient:disconnect()
    end
    
    -- Save persisted state via deps.storage
    if app.features.preferences and app.features.preferences.save and app.deps.storage then
        local _ = app.features.preferences:save()
    end
    
    if app.features.notes and app.features.notes.save and app.deps.storage then
        local _ = app.features.notes:save()
    end
    
    if app.features.tags and app.features.tags.save and app.deps.storage then
        local _ = app.features.tags:save()
    end
    
    app.initialized = false
    return nil
end

-- Attempt to auto-detect server and auto-select it
-- Returns true if auto-detection and selection succeeded, false otherwise
function App.attemptAutoDetectAndConnect(app)
    if not app or not app.features or not app.features.connection or not app.features.serverlist then
        return false
    end
    
    -- If server is already selected, no need to auto-detect
    if app.features.serverlist:isServerSelected() then
        return true
    end
    
    -- Try to detect the realm from game data
    local realmDetector = app.deps and app.deps.realmDetector
    if not realmDetector then
        return false
    end
    
    -- Attempt detection
    local detectedRealmId = realmDetector:getRealmId()
    if not detectedRealmId or detectedRealmId == "" then
        -- Detection failed
        return false
    end
    
    -- Find matching server in the server list
    local serverlist = app.features.serverlist
    if not serverlist.servers or #serverlist.servers == 0 then
        -- Server list is empty, can't match
        return false
    end
    
    for _, server in ipairs(serverlist.servers) do
        if server.id and string.lower(server.id) == string.lower(detectedRealmId) then
            -- Found a match! Auto-select this server
            serverlist:selectServer(server.id)
            return true
        end
    end
    
    -- No matching server found for detected realm
    if app.deps.logger and app.deps.logger.warn then
        app.deps.logger.warn("[App] Auto-detected realm '" .. detectedRealmId .. "' but no matching server found")
    end
    return false
end

return App
