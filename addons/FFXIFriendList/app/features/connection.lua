local M = {}
local RequestEncoder = require("protocol.Encoding.RequestEncoder")
local Envelope = require("protocol.Envelope")
local Endpoints = require("protocol.Endpoints")
local ServerConfig = require("core.ServerConfig")
local VersionCore = require("core.versioncore")

M.ConnectionState = {
    Disconnected = "Disconnected",
    Connecting = "Connecting",
    Connected = "Connected",
    Reconnecting = "Reconnecting",
    Failed = "Failed"
}

M.NetworkBlockReason = {
    Allowed = "Allowed",
    BlockedByServerSelection = "BlockedByServerSelection"
}

M.Connection = {}
M.Connection.__index = M.Connection

local function isGameAlive()
    -- Safely check if game is alive and character is loaded
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
        
        local mainJobLevel = party:GetMemberMainJobLevel(0)
        if not mainJobLevel or mainJobLevel == 0 then
            return false
        end
        
        return true
    end)
    
    return success and result == true
end

local function getCharacterName()
    -- Safely get character name, returns "" if game/character not ready
    if not AshitaCore then
        return ""
    end
    
    local memoryMgr = AshitaCore:GetMemoryManager()
    if not memoryMgr then
        return ""
    end
    
    -- Primary method: Get name from party member 0 (the player)
    local party = memoryMgr:GetParty()
    if party then
        local success, playerName = pcall(function()
            return party:GetMemberName(0)
        end)
        if success and playerName and playerName ~= "" then
            return string.lower(playerName)
        end
    end
    
    -- Fallback: Try entity manager (wrapped in pcall for safety)
    local success, result = pcall(function()
        local entityMgr = memoryMgr:GetEntity()
        if entityMgr then
            -- Check player entity (index 0 is typically the player)
            local entityType = entityMgr:GetType(0)
            local namePtr = entityMgr:GetName(0)
            if entityType == 0 and namePtr and namePtr ~= "" then
                return string.lower(namePtr)
            end
        end
        return ""
    end)
    
    if success and result and result ~= "" then
        return result
    end
    
    return ""
end

function M.Connection.new(deps)
    local self = setmetatable({}, M.Connection)
    deps = deps or {}
    self.deps = deps
    self.logger = deps.logger
    self.net = deps.net
    self.session = deps.session
    self.prefsStore = deps.storage
    self.realmDetector = deps.realmDetector
    self._timeMs = deps.time or function() return os.clock() * 1000 end
    
    self.state = M.ConnectionState.Disconnected
    self.apiKey = ""  -- Single API key for the account
    self.savedServerId = nil
    self.savedServerBaseUrl = nil
    self.savedRealmId = nil
    self.draftServerId = nil
    self.detectedServerSuggestion = nil
    self.detectedServerShownOnce = false
    
    self.autoConnectAttempted = false
    self.autoConnectInProgress = false
    self.lastCharacterName = ""
    self.retryAttemptCount = 0
    self.nextAutoConnectAt = nil
    self.backoffBaseMs = 2000
    self.backoffMaxMs = 60000
    
    -- Load API key (single key model)
    if _G.gConfig and _G.gConfig.data and _G.gConfig.data.apiKey and _G.gConfig.data.apiKey ~= "" then
        self.apiKey = _G.gConfig.data.apiKey
    -- Migration: check old per-realm or per-character keys
    elseif _G.gConfig and _G.gConfig.data then
        -- Try apiKeysByRealm first
        if _G.gConfig.data.apiKeysByRealm then
            for _, apiKey in pairs(_G.gConfig.data.apiKeysByRealm) do
                if apiKey and apiKey ~= "" then
                    self.apiKey = apiKey
                    break
                end
            end
        end
        -- Try old apiKeys (per-character) if still empty
        if self.apiKey == "" and _G.gConfig.data.apiKeys then
            for _, apiKey in pairs(_G.gConfig.data.apiKeys) do
                if apiKey and apiKey ~= "" then
                    self.apiKey = apiKey
                    break
                end
            end
        end
    end
    
    if _G.gConfig and _G.gConfig.data and _G.gConfig.data.serverSelection then
        local serverSel = _G.gConfig.data.serverSelection
        if serverSel.savedServerId and serverSel.savedServerId ~= "" then
            self.savedServerId = serverSel.savedServerId
            self.savedServerBaseUrl = serverSel.savedServerBaseUrl or ServerConfig.DEFAULT_SERVER_URL
            self.savedRealmId = serverSel.savedServerId
        end
    end
    
    return self
end

function M.Connection:getState()
    return {
        state = self.state,
        isConnected = self:isConnected(),
        isConnecting = self:isConnecting(),
        hasServer = self:hasSavedServer(),
        baseUrl = self:getBaseUrl(),
        lastError = self.lastError
    }
end

function M.Connection:tick(dtSeconds)
    if not self:hasSavedServer() then
        return
    end
    
    local characterName = getCharacterName()
    if characterName == "" then
        return
    end
    
    -- BUG 2 FIX: Detect character change even when connected
    if characterName ~= self.lastCharacterName then
        local previousCharacter = self.lastCharacterName
        self.lastCharacterName = characterName
        
        if self:isConnected() then
            -- Character changed while connected - trigger re-auth to update active character
            -- Reset connection state to trigger re-auth
            self.autoConnectAttempted = false
            self.autoConnectInProgress = false
            self.state = M.ConnectionState.Disconnected
            -- Trigger immediate re-connect with new character
            self:autoConnect(characterName)
            return
        elseif self.autoConnectAttempted then
            self.autoConnectAttempted = false
            self.autoConnectInProgress = false
        end
    end
    
    -- If previously failed, schedule retry with backoff
    if (self.state == M.ConnectionState.Failed or self.state == M.ConnectionState.Disconnected) then
        if self.autoConnectInProgress then
            return
        end
        -- If a retry is scheduled and not yet due, wait
        if self.nextAutoConnectAt and self._timeMs() < self.nextAutoConnectAt then
            return
        end
        -- Ready to retry
        self.autoConnectAttempted = false
        self:autoConnect(characterName)
        return
    end

    if self:isConnected() or self.autoConnectInProgress or self.autoConnectAttempted then
        return
    end

    self:autoConnect(characterName)
end

function M.Connection:startConnecting()
    if self.state == M.ConnectionState.Disconnected or 
       self.state == M.ConnectionState.Failed then
        self.state = M.ConnectionState.Connecting
    end
end

function M.Connection:setConnected()
    if self.state == M.ConnectionState.Connecting or 
       self.state == M.ConnectionState.Reconnecting then
        self.state = M.ConnectionState.Connected
        
        local app = _G.FFXIFriendListApp
        if app and app.features and app.features.friends then
            local function sendInitialPresence()
                if app.features.friends.updatePresence then
                    app.features.friends:updatePresence()
                end
            end
            sendInitialPresence()
        end
    end
end

function M.Connection:setDisconnected()
    self.state = M.ConnectionState.Disconnected
    
    local app = _G.FFXIFriendListApp
    if app then
        app._startupRefreshCompleted = false
    end
end

function M.Connection:startReconnecting()
    if self.state == M.ConnectionState.Connected then
        self.state = M.ConnectionState.Reconnecting
    end
end

function M.Connection:setFailed()
    self.state = M.ConnectionState.Failed
    local errorMsg = self.lastError and (" (" .. tostring(self.lastError) .. ")") or ""
    if self.logger and self.logger.warn then
        self.logger.warn("[Connection] State: -> Failed" .. errorMsg)
    end
end

function M.Connection:isConnected()
    return self.state == M.ConnectionState.Connected
end

function M.Connection:isConnecting()
    return self.state == M.ConnectionState.Connecting or 
           self.state == M.ConnectionState.Reconnecting
end

function M.Connection:canConnect()
    return self.state == M.ConnectionState.Disconnected or 
           self.state == M.ConnectionState.Failed
end

-- Single API key for the account (characterName param kept for backward compat but ignored)
function M.Connection:getApiKey(characterName)
    return self.apiKey or ""
end

function M.Connection:setApiKey(characterName, apiKey)
    self.apiKey = apiKey or ""
end

function M.Connection:hasApiKey(characterName)
    return self.apiKey ~= nil and self.apiKey ~= ""
end

function M.Connection:clearApiKey(characterName)
    self.apiKey = ""
end

function M.Connection:hasSavedServer()
    return self.savedServerId ~= nil and self.savedServerId ~= ""
end

function M.Connection:isBlocked()
    return not self:hasSavedServer()
end

function M.Connection:setSavedServer(serverId, baseUrl)
    self.savedServerId = serverId
    self.savedServerBaseUrl = baseUrl
    self.savedRealmId = serverId
    
    -- Reset auto-connect flags so tick() will trigger a new connection attempt
    self.autoConnectAttempted = false
    self.autoConnectInProgress = false
end

function M.Connection:clearSavedServer()
    self.savedServerId = nil
    self.savedServerBaseUrl = nil
    self.savedRealmId = nil
end

function M.Connection:checkNetworkAccess()
    if self:isBlocked() then
        return M.NetworkBlockReason.BlockedByServerSelection
    end
    return M.NetworkBlockReason.Allowed
end

function M.Connection:getBlockReason()
    if self:isBlocked() then
        return "Server selection required"
    end
    return ""
end

function M.Connection:getBaseUrl()
    if self.savedServerBaseUrl and self.savedServerBaseUrl ~= "" then
        return self.savedServerBaseUrl
    end
    return ServerConfig.DEFAULT_SERVER_URL
end

function M.Connection:getCharacterName()
    return getCharacterName()
end

function M.Connection:isGameAlive()
    return isGameAlive()
end

-- Get auth headers matching new server middleware (friendlist-server/src/middleware/auth.ts)
-- Required: Authorization: Bearer <apiKey>
-- Optional: X-Character-Name, X-Realm-Id (for endpoints requiring character context)
function M.Connection:getHeaders(characterName)
    characterName = characterName or ""
    local addonVersion = addon and addon.version or VersionCore.ADDON_VERSION
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "FFXIFriendList/" .. addonVersion
    }
    
    -- Add character name header if provided
    if characterName ~= "" then
        headers["X-Character-Name"] = characterName
    end
    
    -- Add realm ID header
    local realmIdForHeader = nil
    if self.savedRealmId and self.savedRealmId ~= "" then
        realmIdForHeader = self.savedRealmId
    elseif self.realmDetector and self.realmDetector.getRealmId then
        realmIdForHeader = self.realmDetector:getRealmId()
    end
    if realmIdForHeader and realmIdForHeader ~= "" then
        headers["X-Realm-Id"] = realmIdForHeader
    end
    
    -- Add Authorization header (Bearer token format)
    if characterName ~= "" then
        local apiKey = self:getApiKey(characterName)
        if apiKey ~= "" then
            headers["Authorization"] = "Bearer " .. apiKey
        else
            if self.logger and self.logger.warn then
                self.logger.warn("[Connection] Headers: No API key for " .. characterName)
            end
        end
    end
    
    return headers
end

function M.Connection:autoConnect(characterName)
    if not characterName or characterName == "" then
        return false
    end
    
    if not self:hasSavedServer() then
        return false
    end
    
    if self.autoConnectAttempted or self.autoConnectInProgress then
        return false
    end
    
    self.autoConnectAttempted = true
    self.autoConnectInProgress = true
    
    local normalizedName = string.lower(characterName)
    local realmId = "notARealServer"
    if self.savedRealmId and self.savedRealmId ~= "" then
        realmId = self.savedRealmId
    elseif self.realmDetector and self.realmDetector.getRealmId then
        realmId = self.realmDetector:getRealmId() or "notARealServer"
    end
    
    self:startConnecting()
    
    local storedApiKey = self:getApiKey(normalizedName)
    
    -- With per-realm API keys, we don't need to search through character keys
    -- The getApiKey() already returns the realm's API key if available
    
    local function attemptConnect()
        local baseUrl = self:getBaseUrl()
        baseUrl = baseUrl:gsub("/+$", "")
        
        -- New server auth flow:
        -- If we have an API key, use /api/auth/add-character to add this character
        -- If no API key, use /api/auth/register to create a new account
        local hasApiKey = storedApiKey and storedApiKey ~= ""
        local url, requestBody
        
        if hasApiKey then
            -- Add character to account (creates if needed, links if exists)
            url = baseUrl .. Endpoints.AUTH.ADD_CHARACTER
            requestBody = RequestEncoder.encodeAddCharacter(normalizedName, realmId)
        else
            -- No API key - register as new user
            url = baseUrl .. Endpoints.AUTH.REGISTER
            requestBody = RequestEncoder.encodeRegister(normalizedName, realmId)
        end
        
        local addonVersion = addon and addon.version or VersionCore.ADDON_VERSION
        local headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "FFXIFriendList/" .. addonVersion,
            ["X-Character-Name"] = normalizedName
        }
        
        -- Add Authorization header (Bearer token format) if we have an API key
        if hasApiKey then
            headers["Authorization"] = "Bearer " .. storedApiKey
        end
        
        -- Add realm ID header
        local realmIdForHeader = nil
        if self.savedRealmId and self.savedRealmId ~= "" then
            realmIdForHeader = self.savedRealmId
        elseif self.realmDetector and self.realmDetector.getRealmId then
            realmIdForHeader = self.realmDetector:getRealmId()
        end
        if realmIdForHeader and realmIdForHeader ~= "" then
            headers["X-Realm-Id"] = realmIdForHeader
        end
        
        local requestId = self.net.request({
            url = url,
            method = "POST",
            headers = headers,
            body = requestBody,
            callback = function(success, response)
                self:handleAuthResponse(success, response, normalizedName, storedApiKey)
            end
        })
        
        return requestId ~= nil
    end
    
    return attemptConnect()
end

function M.Connection:handleAuthResponse(success, response, characterName, fallbackApiKey)
    self.autoConnectInProgress = false
    
    if not success then
        self:setFailed()
        self.lastError = response or "Network error"
        -- Schedule retry with exponential backoff + jitter
        local attempt = math.max(1, self.retryAttemptCount + 1)
        local delay = self.backoffBaseMs * (2 ^ (attempt - 1))
        delay = math.min(delay, self.backoffMaxMs)
        local jitterRange = math.floor(delay * 0.2)
        local jitter = (math.random(0, jitterRange * 2) - jitterRange)
        delay = math.max(250, delay + jitter)
        self.nextAutoConnectAt = self._timeMs() + delay
        self.retryAttemptCount = attempt
        self.autoConnectAttempted = false
        if self.logger and self.logger.warn then
            self.logger.warn(string.format("[Connection] Auth failed; retry in %.1fs (attempt %d)", delay / 1000, attempt))
        end
        if self.logger and self.logger.error then
            self.logger.error("[Connection] Auth failed: " .. tostring(self.lastError))
        end
        return
    end
    
    -- Use new envelope decoder for { success, data, timestamp } format
    local ok, result, errorMsg = Envelope.decode(response)
    if not ok then
        self:setFailed()
        self.lastError = errorMsg or result or "Failed to decode response"
        if self.logger and self.logger.error then
            self.logger.error("[Connection] Envelope decode failed: " .. tostring(self.lastError))
        end
        return
    end
    
    -- result contains { success, data, timestamp }
    local data = result.data or {}
    
    -- Check for API key in response (from /api/auth/register)
    -- The register endpoint returns { apiKey, accountId, character }
    local apiKey = data.apiKey or fallbackApiKey or ""
    
    if apiKey and apiKey ~= "" then
        self:setApiKey(nil, apiKey)  -- Single API key, characterName ignored
        -- Persist to config
        if _G.gConfig then
            if not _G.gConfig.data then
                _G.gConfig.data = {}
            end
            _G.gConfig.data.apiKey = apiKey
            -- Clean up old structures if present
            _G.gConfig.data.apiKeys = nil
            _G.gConfig.data.apiKeysByRealm = nil
            local settings = require("libs.settings")
            if settings and settings.save then
                settings.save()
            end
        end
    end
    
    -- BUG 2 FIX: Extract character ID and set as active character
    -- This ensures friends see the correct character after switching
    local characterId = nil
    if data.character and data.character.id then
        characterId = data.character.id
    end
    
    -- Store the character ID for later use
    self.lastCharacterId = characterId
    self.lastSetActiveAt = nil
    -- Reset backoff on success
    self.retryAttemptCount = 0
    self.nextAutoConnectAt = nil
    
    -- If we have a character ID, call set-active to ensure this is the active character
    if characterId and apiKey and apiKey ~= "" then
        self:setActiveCharacter(characterId, characterName, apiKey)
    else
        -- No character ID available, proceed with connection
        self:completeConnection(characterName)
    end
end

-- BUG 2 FIX: Set the active character on the server
function M.Connection:setActiveCharacter(characterId, characterName, apiKey)
    if not self.net then
        self:completeConnection(characterName)
        return
    end
    
    local baseUrl = self:getBaseUrl()
    baseUrl = baseUrl:gsub("/+$", "")
    
    local url = baseUrl .. Endpoints.AUTH.SET_ACTIVE
    local requestBody = RequestEncoder.encodeSetActiveCharacter(characterId)
    
    local addonVersion = addon and addon.version or VersionCore.ADDON_VERSION
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "FFXIFriendList/" .. addonVersion,
        ["Authorization"] = "Bearer " .. apiKey
    }
    
    self.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = requestBody,
        callback = function(success, response)
            if success then
                self.lastSetActiveAt = os.time() * 1000
            else
                if self.logger and self.logger.warn then
                    self.logger.warn("[Connection] Set active character failed: " .. tostring(response))
                end
            end
            -- Complete connection regardless of set-active result
            self:completeConnection(characterName)
        end
    })
end

-- Complete the connection process after auth and set-active
function M.Connection:completeConnection(characterName)
    self:setConnected()
    
    local app = _G.FFXIFriendListApp
    if app and not app._startupRefreshCompleted then
        local App = require("app.App")
        if App and App._triggerStartupRefresh then
            App._triggerStartupRefresh(app)
            app._startupRefreshCompleted = true
            -- Ensure WS connection requested (in case we came online later)
            if app.features and app.features.wsConnectionManager then
                app.features.wsConnectionManager:requestConnect()
            end
        end
    end
end

function M.Connection:connect(characterName)
    characterName = characterName or getCharacterName()
    if characterName == "" then
        if self.logger and self.logger.warn then
            self.logger.warn("[Connection] Cannot connect: character name not available")
        end
        return false
    end
    
    if not self:canConnect() then
        if self.logger and self.logger.warn then
            self.logger.warn("[Connection] Cannot connect: already connecting or connected")
        end
        return false
    end
    
    self.autoConnectAttempted = false
    self.autoConnectInProgress = false
    
    return self:autoConnect(characterName)
end

function M.Connection:disconnect()
    self:setDisconnected()
end

function M.Connection:setServer(serverId, baseUrl)
    self:setSavedServer(serverId, baseUrl)
end

function M.Connection:getStatus()
    return {
        state = self.state,
        isConnected = self:isConnected(),
        isConnecting = self:isConnecting(),
        hasServer = self:hasSavedServer(),
        baseUrl = self:getBaseUrl()
    }
end

return M
