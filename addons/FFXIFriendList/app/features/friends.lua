local FriendList = require("core.friendlist")
local RequestEncoder = require("protocol.Encoding.RequestEncoder")
local Envelope = require("protocol.Envelope")
local TimingConstants = require("core.TimingConstants")
local Endpoints = require("protocol.Endpoints")
local utils = require("modules.friendlist.components.helpers.utils")

local M = {}

M.Friends = {}
M.Friends.__index = M.Friends

function M.Friends.new(deps)
    local self = setmetatable({}, M.Friends)
    self.deps = deps or {}
    
    self.friendList = FriendList.FriendList.new()
    self.incomingRequests = {}
    self.outgoingRequests = {}
    self.state = "idle"
    self.lastError = nil
    self.lastUpdatedAt = nil
    
    self.retryCount = 0
    self.retryDelay = TimingConstants.INITIAL_RETRY_DELAY_MS
    self.maxRetries = TimingConstants.MAX_RETRIES
    self.nextRetryAt = nil
    
    -- Heartbeat interval (safety signal only - NOT polling)
    self.heartbeatInterval = TimingConstants.HEARTBEAT_INTERVAL_MS
    self.lastHeartbeatAt = nil
    self.heartbeatInFlight = false
    self.refreshInFlight = false
    self.friendRequestsInFlight = false
    
    self.pendingZoneChange = nil
    self.zoneChangeScheduledAt = nil
    
    -- Track anonymous status from packets (for change detection and data)
    self.lastKnownAnonStatus = nil
    
    -- Track last sent presence to server (for deduplication)
    self.lastSentZoneId = nil
    self.lastSentMainJob = nil
    self.lastSentMainJobLevel = nil
    self.lastSentSubJob = nil
    self.lastSentSubJobLevel = nil
    self.lastSentIsAnonymous = nil
    
    -- Track zone-only updates to prevent immediate full updates
    self.lastZoneOnlyUpdateAt = nil
    
    -- Track presence changes for UI updates (Privacy tab auto-refresh)
    self.presenceChangedAt = nil
    
    -- Cache last valid presence for UI display (prevents "Unknown" during zone transitions)
    self.lastValidPresence = nil
    
    -- Track presence update state to prevent race conditions
    self.presenceUpdateInFlight = false
    self.hasPendingPresenceUpdate = false
    
    -- Notification state tracking
    self.previousOnlineStatus = {}      -- table: lowercase name -> bool
    self.initialStatusScanComplete = false
    self.processedRequestIds = {}       -- set: requestId -> true

    return self
end

local function getTime(self)
    if self.deps.time then
        return self.deps.time()
    end
    return os.time() * 1000
end

-- Helper: Read job data from memory (used when packet data is invalid)
local function getJobDataFromMemory()
    if not AshitaCore then
        return nil, nil, nil, nil
    end
    
    local memoryMgr = AshitaCore:GetMemoryManager()
    if not memoryMgr then
        return nil, nil, nil, nil
    end
    
    local player = memoryMgr:GetPlayer()
    if not player then
        return nil, nil, nil, nil
    end
    
    local playerData = player:GetRawStructure()
    if not playerData then
        return nil, nil, nil, nil
    end
    
    return playerData.MainJob, playerData.MainJobLevel, playerData.SubJob, playerData.SubJobLevel
end

-- Helper: Format job string from server state (job, subJob, jobLevel, subJobLevel)
-- Returns formatted string like "SMN 41/BLM 18" or empty string if no job data
local function formatJobFromState(state)
    if not state then return "" end
    
    local mainJob = state.job
    local mainJobLevel = state.jobLevel
    local subJob = state.subJob
    local subJobLevel = state.subJobLevel
    
    -- Type guards - ensure we have proper types
    if type(mainJobLevel) ~= "number" then mainJobLevel = nil end
    if type(subJobLevel) ~= "number" then subJobLevel = nil end
    
    -- If we already have a pre-formatted string (legacy compatibility), use it
    if type(mainJob) == "string" and mainJob ~= "" and not mainJobLevel then
        return mainJob
    end
    
    -- No main job data
    if not mainJob or mainJob == "" then
        return ""
    end
    
    -- Format main job
    local result = mainJob
    if mainJobLevel and mainJobLevel > 0 then
        result = result .. " " .. tostring(mainJobLevel)
    end
    
    -- Add sub job if present
    if subJob and subJob ~= "" then
        result = result .. "/" .. subJob
        if subJobLevel and subJobLevel > 0 then
            result = result .. " " .. tostring(subJobLevel)
        end
    end
    
    return result
end

function M.Friends:getState()
    local rawFriends = self.friendList:getFriends()
    local friendsWithPresence = {}
    
    for _, friend in ipairs(rawFriends) do
        local status = self.friendList:getFriendStatus(friend.name)
        
        local friendCopy = {
            name = friend.name,
            friendedAs = friend.friendedAs,
            linkedCharacters = friend.linkedCharacters,
            isOnline = status and status.isOnline or false,
            isAway = status and status.isAway or false,
            isPending = friend.isPending or false,
            friendAccountId = friend.friendAccountId,
            sharesOnlineStatus = status and status.showOnlineStatus ~= false or true,
            lastSeenAt = status and status.lastSeenAt or 0,
            realmId = friend.realmId,
            presence = {
                job = status and status.job or "",
                zone = status and status.zone or "",
                rank = status and status.rank or "",
                nation = status and status.nation or -1,
                lastSeenAt = status and status.lastSeenAt or 0
            }
        }
        table.insert(friendsWithPresence, friendCopy)
    end
    
    return {
        friends = friendsWithPresence,
        incomingRequests = self.incomingRequests,
        outgoingRequests = self.outgoingRequests,
        state = self.state,
        lastUpdatedAt = self.lastUpdatedAt,
        lastError = self.lastError
    }
end

function M.Friends:tick(dtSeconds)
    local now = getTime(self)
    
    -- Handle retry for failed requests
    if self.nextRetryAt and now >= self.nextRetryAt then
        if self.retryCount < self.maxRetries then
            self:refresh()
        else
            self.state = "error"
            self.nextRetryAt = nil
        end
    end
    
    -- Send heartbeat (safety signal only - NOT polling)
    -- Skip heartbeat until we've received initial friends snapshot (confirms WS fully connected)
    if self.deps.connection and self.deps.connection:isConnected() and self.lastUpdatedAt then
        if not self.heartbeatInFlight then
            local shouldHeartbeat = false
            if not self.lastHeartbeatAt then
                shouldHeartbeat = true
            elseif (now - self.lastHeartbeatAt) >= self.heartbeatInterval then
                shouldHeartbeat = true
            end
            
            if shouldHeartbeat then
                self:sendHeartbeat()
            end
        end
    end
    
    -- NO POLLING - removed refresh interval check
    -- WS events are the sole source of real-time updates
    
    -- Handle zone change debounce
    if self.zoneChangeScheduledAt and (now - self.zoneChangeScheduledAt) >= TimingConstants.ZONE_CHANGE_DEBOUNCE_MS then
        if self.pendingZoneChange then
            self:handleZoneChange(self.pendingZoneChange)
            self.pendingZoneChange = nil
            self.zoneChangeScheduledAt = nil
        end
    end
end

function M.Friends:refresh()
    -- Prevent duplicate in-flight requests
    if self.refreshInFlight then
        return false
    end
    
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        self.lastError = { type = "NotConnected", message = "Not connected to server" }
        return false
    end
    
    self.refreshInFlight = true
    self.state = "syncing"
    self.lastError = nil
    
    -- Use new server endpoint: GET /api/friends
    local url = self.deps.connection:getBaseUrl() .. Endpoints.FRIENDS.LIST
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    local requestId = self.deps.net.request({
        url = url,
        method = "GET",
        headers = headers,
        body = "",
        callback = function(success, response)
            self:handleRefreshResponse(success, response)
        end
    })
    
    return requestId ~= nil
end

function M.Friends:handleRefreshResponse(success, response)
    self.refreshInFlight = false
    
    local decodeStartMs = 0
    if self.deps.time then
        decodeStartMs = self.deps.time()
    else
        decodeStartMs = os.time() * 1000
    end
    
    if not success then
        self.state = "error"
        local errorMsg = response
        if type(errorMsg) == "table" then
            errorMsg = "Network error"
        else
            errorMsg = tostring(errorMsg or "Network error")
        end
        self.lastError = { type = "NetworkError", message = errorMsg }
        self:scheduleRetry()
        return
    end
    
    -- Use new envelope format: { success, data, timestamp }
    local ok, envelope, errorMsg = Envelope.decode(response)
    if not ok then
        self.state = "error"
        self.lastError = { type = "ProtocolError", message = errorMsg or "Failed to decode response" }
        self:scheduleRetry()
        return
    end
    
    -- Extract friends from data (new server format)
    local result = envelope.data or {}
    
    local stateUpdateStartMs = 0
    if self.deps.time then
        stateUpdateStartMs = self.deps.time()
    else
        stateUpdateStartMs = os.time() * 1000
    end
    local decodeTime = stateUpdateStartMs - decodeStartMs
    
    self.friendList:clear()
    
    -- New server returns { friends: FriendInfo[] }
    local friends = result.friends or {}
    for _, friendData in ipairs(friends) do
        -- New server uses accountId, characterName, isOnline, lastSeen, state
        local displayName = friendData.characterName or ""
        if displayName == "" then
            -- Fallback: use accountId prefix if no character name
            displayName = "Unknown (" .. string.sub(friendData.accountId or "???", 1, 8) .. ")"
        end
        local friend = FriendList.Friend.new(displayName, displayName)
        friend.friendAccountId = friendData.accountId
        friend.isOnline = friendData.isOnline == true
        -- Normalize lastSeen to numeric timestamp (handles ISO8601 from server)
        friend.lastSeenAt = utils.normalizeLastSeen(friendData.lastSeen)
        -- Store realm ID for cross-server friend display
        friend.realmId = friendData.realmId or nil
        
        -- State contains job, zone, nation, rank info
        local state = friendData.state or {}
        friend.job = formatJobFromState(state)
        friend.zone = state.zone or ""
        friend.nation = state.nation
        friend.rank = state.rank
        
        self.friendList:addFriend(friend)
        
        -- Also update status
        local status = FriendList.FriendStatus.new()
        status.characterName = string.lower(displayName)
        status.displayName = displayName
        status.isOnline = friend.isOnline
        status.job = friend.job
        status.zone = friend.zone
        status.nation = friend.nation or -1
        status.rank = friend.rank or ""
        status.lastSeenAt = friend.lastSeenAt
        status.showOnlineStatus = true
        
        self.friendList:updateFriendStatus(status)
    end
    
    self.state = "idle"
    self.lastError = nil
    self.lastUpdatedAt = getTime(self)
    self.lastRefreshAt = getTime(self)
    self.retryCount = 0
    self.nextRetryAt = nil
    
    local stateUpdateEndMs = 0
    if self.deps.time then
        stateUpdateEndMs = self.deps.time()
    else
        stateUpdateEndMs = os.time() * 1000
    end
    local stateUpdateTime = stateUpdateEndMs - stateUpdateStartMs
    
    -- Status change notifications are now handled via WS events
    -- See: wsEventHandler.lua
end

function M.Friends:scheduleRetry()
    self.retryCount = self.retryCount + 1
    if self.retryCount < self.maxRetries then
        self.retryDelay = self.retryDelay * 2
        self.nextRetryAt = getTime(self) + self.retryDelay
    end
end

function M.Friends:_getCharacterName()
    if self.deps.connection.getCharacterName then
        return self.deps.connection:getCharacterName()
    elseif self.deps.connection.lastCharacterName then
        return self.deps.connection.lastCharacterName
    end
    return ""
end

function M.Friends:addFriend(name)
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Get realm ID for the request
    local realmId = "unknown"
    if self.deps.connection.savedRealmId and self.deps.connection.savedRealmId ~= "" then
        realmId = self.deps.connection.savedRealmId
    elseif self.deps.connection.realmDetector and self.deps.connection.realmDetector.getRealmId then
        realmId = self.deps.connection.realmDetector:getRealmId() or "unknown"
    end

    local normalizedName = string.lower((tostring(name or ""):match("^%s*(.-)%s*$") or ""))
    
    -- Use new server endpoint: POST /api/friends/request
    local requestBody = RequestEncoder.encodeNewSendFriendRequest(normalizedName, realmId)
    local url = self.deps.connection:getBaseUrl() .. Endpoints.FRIENDS.SEND_REQUEST
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    -- Optimistic add to outgoing requests
    local tempRequest = {
        id = "pending_" .. normalizedName .. "_" .. os.time(),
        name = normalizedName,
        status = "PENDING",
        createdAt = os.time() * 1000
    }
    table.insert(self.outgoingRequests, tempRequest)
    
    local requestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = requestBody,
        callback = function(success, response)
            -- Remove optimistic request on any response
            for i, req in ipairs(self.outgoingRequests) do
                if req.id == tempRequest.id then
                    table.remove(self.outgoingRequests, i)
                    break
                end
            end
            
            if not success then
                -- Try to parse error from response
                local errorMsg = "Failed to send friend request"
                local errorCode = nil
                
                -- Envelope.decode returns: success, errorType, errorMessage, errorCode
                local ok, errorType, serverMsg, serverCode = Envelope.decode(response)
                
                if not ok and errorType == Envelope.DecodeError.ServerError then
                    errorMsg = serverMsg or errorMsg
                    errorCode = serverCode
                end
                
                -- Friendly message for CHARACTER_NOT_FOUND error
                if errorCode == "CHARACTER_NOT_FOUND" then
                    if self.deps.logger and self.deps.logger.echo then
                        self.deps.logger.echo("Player '" .. name .. "' doesn't have the addon installed.")
                        self.deps.logger.echo("Tell them to get it at: https://github.com/Tanyrus/FFXIFriendList")
                    end
                else
                    if self.deps.logger and self.deps.logger.echo then
                        self.deps.logger.echo("Friend request failed: " .. errorMsg)
                    end
                end
            else
                -- Success - parse response for real request ID and add to outgoing
                local ok, envelope = Envelope.decode(response)
                if ok and envelope.data then
                    local realRequestId = envelope.data.requestId
                    if realRequestId then
                        -- Use normalized UI format: { id, name, accountId, createdAt }
                        local realRequest = {
                            id = realRequestId,
                            name = normalizedName,
                            accountId = nil,  -- Will be filled by refreshFriendRequests
                            createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
                        }
                        table.insert(self.outgoingRequests, realRequest)
                    end
                end
                
                if self.deps.logger and self.deps.logger.echo then
                    self.deps.logger.echo("Friend request sent to " .. name)
                end
            end
        end
    })
    
    return requestId ~= nil
end

-- Add friend with explicit realm ID (for cross-server friend requests)
function M.Friends:addFriendWithRealm(name, realmId)
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    if not realmId or realmId == "" then
        -- Fall back to regular addFriend if no realm specified
        return self:addFriend(name)
    end

    local normalizedName = string.lower((tostring(name or ""):match("^%s*(.-)%s*$") or ""))
    
    -- Use new server endpoint: POST /api/friends/request with explicit realmId
    local requestBody = RequestEncoder.encodeNewSendFriendRequest(normalizedName, realmId)
    local url = self.deps.connection:getBaseUrl() .. Endpoints.FRIENDS.SEND_REQUEST
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    -- Optimistic add to outgoing requests
    local tempRequest = {
        id = "pending_" .. normalizedName .. "_" .. realmId .. "_" .. os.time(),
        name = normalizedName,
        status = "PENDING",
        createdAt = os.time() * 1000
    }
    table.insert(self.outgoingRequests, tempRequest)
    
    local requestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = requestBody,
        callback = function(success, response)
            -- Remove optimistic request on any response
            for i, req in ipairs(self.outgoingRequests) do
                if req.id == tempRequest.id then
                    table.remove(self.outgoingRequests, i)
                    break
                end
            end
            
            if not success then
                -- Try to parse error from response
                local errorMsg = "Failed to send cross-server friend request"
                local errorCode = nil
                
                -- Envelope.decode returns: success, errorType, errorMessage, errorCode
                local ok, errorType, serverMsg, serverCode = Envelope.decode(response)
                if not ok and errorType == Envelope.DecodeError.ServerError then
                    errorMsg = serverMsg or errorMsg
                    errorCode = serverCode
                end
                
                -- Friendly message for CHARACTER_NOT_FOUND error
                if errorCode == "CHARACTER_NOT_FOUND" then
                    if self.deps.logger and self.deps.logger.echo then
                        self.deps.logger.echo("Player '" .. normalizedName .. "' on " .. realmId .. " doesn't have the addon installed.")
                        self.deps.logger.echo("Tell them to get it at: github.com/Tanyrus/FFXIFriendList")
                    end
                else
                    if self.deps.logger and self.deps.logger.echo then
                        self.deps.logger.echo("Cross-server friend request failed: " .. errorMsg)
                    end
                end
            else
                -- Success - parse response for real request ID and add to outgoing
                local ok, envelope = Envelope.decode(response)
                if ok and envelope.data then
                    local realRequestId = envelope.data.requestId
                    if realRequestId then
                        local realRequest = {
                            id = realRequestId,
                            name = normalizedName,
                            accountId = nil,
                            createdAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
                        }
                        table.insert(self.outgoingRequests, realRequest)
                    end
                end
                
                if self.deps.logger and self.deps.logger.echo then
                    self.deps.logger.echo("Cross-server friend request sent to " .. name .. " on " .. realmId)
                end
            end
        end
    })
    
    return requestId ~= nil
end

function M.Friends:removeFriend(name)
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Find friend account ID by name
    local accountId = nil
    local allFriends = self.friendList:getFriends()
    for _, friend in ipairs(allFriends) do
        if string.lower(friend.name) == string.lower(name) then
            accountId = friend.friendAccountId
            break
        end
    end
    
    if not accountId then
        return false
    end
    
    -- Use new server endpoint: DELETE /api/friends/:accountId
    local url = self.deps.connection:getBaseUrl() .. Endpoints.friendRemove(accountId)
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    local requestId = self.deps.net.request({
        url = url,
        method = "DELETE",
        headers = headers,
        body = "",
        callback = function(success, response)
            -- HTTP response is confirmation only
            -- WS friend_removed event is authoritative
            if not success and self.deps.logger and self.deps.logger.warn then
                self.deps.logger.warn("[Friends] Remove friend failed: " .. tostring(response))
            end
        end
    })
    
    return requestId ~= nil
end

function M.Friends:acceptRequest(requestId)
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Use new server endpoint: POST /api/friends/requests/:id/accept
    local url = self.deps.connection:getBaseUrl() .. Endpoints.friendRequestAccept(requestId)
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    local netRequestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = "{}",
        callback = function(success, response)
            -- HTTP response is confirmation only
            -- WS friend_added event is authoritative
            if not success and self.deps.logger and self.deps.logger.warn then
                self.deps.logger.warn("[Friends] Accept request failed: " .. tostring(response))
            end
        end
    })
    
    return netRequestId ~= nil
end

function M.Friends:rejectRequest(requestId)
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Use new server endpoint: POST /api/friends/requests/:id/decline
    local url = self.deps.connection:getBaseUrl() .. Endpoints.friendRequestDecline(requestId)
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    local netRequestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = "{}",
        callback = function(success, response)
            -- HTTP response is confirmation only
            -- WS friend_request_declined event is authoritative
            if not success and self.deps.logger and self.deps.logger.warn then
                self.deps.logger.warn("[Friends] Reject request failed: " .. tostring(response))
            end
        end
    })
    
    return netRequestId ~= nil
end

-- Cancel outgoing request (decline our own request)
function M.Friends:cancelRequest(requestId)
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Use proper cancel endpoint: DELETE /api/friends/requests/:id
    local url = self.deps.connection:getBaseUrl() .. Endpoints.friendRequestCancel(requestId)
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    
    local netRequestId = self.deps.net.request({
        url = url,
        method = "DELETE",
        headers = headers,
        body = "",
        callback = function(success, response)
            -- HTTP response is confirmation only
            -- WS friend_request_declined event is authoritative
            if not success and self.deps.logger and self.deps.logger.warn then
                self.deps.logger.warn("[Friends] Cancel request failed: " .. tostring(response))
            end
        end
    })
    
    return netRequestId ~= nil
end

function M.Friends:getFriends()
    return self.friendList:getFriends()
end

function M.Friends:refreshFriendRequests()
    -- Prevent duplicate in-flight requests
    if self.friendRequestsInFlight then
        return false
    end
    
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    self.friendRequestsInFlight = true
    
    local headers = self.deps.connection:getHeaders(self:_getCharacterName())
    local baseUrl = self.deps.connection:getBaseUrl()
    
    -- Fetch pending (incoming) requests
    local pendingUrl = baseUrl .. Endpoints.FRIENDS.REQUESTS_PENDING
    self.deps.net.request({
        url = pendingUrl,
        method = "GET",
        headers = headers,
        body = "",
        callback = function(success, response)
            self:handleFriendRequestsResponse(success, response, "pending")
        end
    })
    
    -- Fetch outgoing requests
    local outgoingUrl = baseUrl .. Endpoints.FRIENDS.REQUESTS_OUTGOING
    self.deps.net.request({
        url = outgoingUrl,
        method = "GET",
        headers = headers,
        body = "",
        callback = function(success, response)
            self:handleFriendRequestsResponse(success, response, "outgoing")
            -- Clear in-flight flag after both complete
            self.friendRequestsInFlight = false
        end
    })
    
    return true
end

function M.Friends:handleFriendRequestsResponse(success, response, requestType)
    self.friendRequestsInFlight = false
    
    if not success then
        if self.deps.logger and self.deps.logger.warn then
            self.deps.logger.warn("[Friends] Failed to refresh friend requests: " .. tostring(response))
        end
        return
    end
    
    -- Use new envelope format: { success, data, timestamp }
    local ok, envelope, errorMsg = Envelope.decode(response)
    if not ok then
        if self.deps.logger and self.deps.logger.warn then
            self.deps.logger.warn("[Friends] Failed to decode friend requests: " .. tostring(errorMsg))
        end
        return
    end
    
    -- Extract requests from data
    local data = envelope.data or {}
    local rawRequests = data.requests or {}
    
    -- Normalize requests to UI-expected format: { id, name, accountId, createdAt }
    -- Server returns: { id, fromCharacterName/toCharacterName, fromAccountId/toAccountId, createdAt }
    local requests = {}
    for _, req in ipairs(rawRequests) do
        local normalized = {
            id = req.id,
            createdAt = req.createdAt
        }
        if requestType == "pending" then
            normalized.name = req.fromCharacterName
            normalized.accountId = req.fromAccountId
        elseif requestType == "outgoing" then
            normalized.name = req.toCharacterName
            normalized.accountId = req.toAccountId
        end
        table.insert(requests, normalized)
    end
    
    -- Update the appropriate list based on request type
    if requestType == "pending" then
        self.incomingRequests = requests
        -- Check for new friend requests and trigger notifications
        self:checkForNewFriendRequests(self.incomingRequests)
    elseif requestType == "outgoing" then
        self.outgoingRequests = requests
    end
end

function M.Friends:getIncomingRequests()
    return self.incomingRequests
end

function M.Friends:getOutgoingRequests()
    return self.outgoingRequests
end

function M.Friends:scheduleZoneChange(packet)
    if not packet or packet.type ~= "zone" then
        return false
    end
    
    self.pendingZoneChange = packet
    self.zoneChangeScheduledAt = getTime(self)
    return true
end

function M.Friends:handlePCUpdate(packet)
    if not packet or packet.type ~= "pc_update" then
        return
    end
    
    -- Skip during zone cooldown
    if self.lastZoneOnlyUpdateAt then
        local timeSinceZoneUpdate = getTime(self) - self.lastZoneOnlyUpdateAt
        if timeSinceZoneUpdate < 4000 then
            return  -- Skip during zone cooldown
        end
    end
    
    -- Track anonymous status from packet
    local currentAnon = packet.isAnonymous
    
    if self.lastKnownAnonStatus ~= currentAnon then
        self.lastKnownAnonStatus = currentAnon
        
        self.presenceChangedAt = getTime(self)
        self:updatePresence()
    end
end

function M.Friends:handleUpdateChar(packet)
    if not packet or packet.type ~= "update_char" then
        return
    end
    
    -- Skip during zone cooldown
    if self.lastZoneOnlyUpdateAt then
        local timeSinceZoneUpdate = getTime(self) - self.lastZoneOnlyUpdateAt
        if timeSinceZoneUpdate < 4000 then
            return  -- Skip during zone cooldown
        end
    end
    
    -- Track anonymous status from packet
    local currentAnon = packet.isAnonymous
    
    if self.lastKnownAnonStatus ~= currentAnon then
        self.lastKnownAnonStatus = currentAnon
        
        self.presenceChangedAt = getTime(self)
        self:updatePresence()
    end
end

function M.Friends:handleCharUpdate(packet)
    if not packet or packet.type ~= "char_update" then
        return
    end
    
    -- Skip during zone cooldown
    if self.lastZoneOnlyUpdateAt then
        local timeSinceZoneUpdate = getTime(self) - self.lastZoneOnlyUpdateAt
        if timeSinceZoneUpdate < 4000 then
            return  -- Skip during zone cooldown
        end
    end
    
    -- Packet detected job/level change - trigger update
    -- Actual data will be read from memory in updatePresence()
    self.presenceChangedAt = getTime(self)
    self:updatePresence()
end

function M.Friends:handleZoneChange(packet)
    if not packet or packet.type ~= "zone" then
        return false
    end
    
    -- Only send zone update, not job/nation/anonymous status
    -- This prevents sending stale or unchanged data
    self:updateZoneOnly()
    return true
end

function M.Friends:updateZoneOnly()
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Get current zone from memory
    local memoryMgr = AshitaCore:GetMemoryManager()
    if not memoryMgr then
        return false
    end
    
    local party = memoryMgr:GetParty()
    if not party then
        return false
    end
    
    local zoneId = party:GetMemberZone(0)
    if not zoneId or zoneId == 0 then
        return false
    end
    
    -- Don't update if zone hasn't actually changed
    if self.lastSentZoneId == zoneId then
        return true
    end
    
    local zoneName = self:getZoneNameFromId(zoneId)
    if not zoneName then
        return false
    end
    
    -- Track what we sent
    self.lastSentZoneId = zoneId
    self.lastZoneOnlyUpdateAt = getTime(self)
    
    -- Send zone-only update to server
    local body = RequestEncoder.encodePresenceUpdate({
        zone = zoneName
    })
    
    local url = self.deps.connection:getBaseUrl() .. Endpoints.PRESENCE.UPDATE
    
    local characterName = ""
    if self.deps.connection.getCharacterName then
        characterName = self.deps.connection:getCharacterName()
    end
    
    local headers = self.deps.connection:getHeaders(characterName)
    
    self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = body,
        callback = function(success, response)
            if not success and self.deps.logger and self.deps.logger.error then
                self.deps.logger.error("[Friends] Failed to update zone: " .. tostring(response))
            end
        end
    })
    
    return true
end

function M.Friends:updatePresence()
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Skip full update if we just sent a zone-only update (within 4 seconds)
    -- This prevents PC_UPDATE packets from overwriting with stale data
    if self.lastZoneOnlyUpdateAt then
        local timeSinceZoneUpdate = getTime(self) - self.lastZoneOnlyUpdateAt
        if timeSinceZoneUpdate < 4000 then
            return true  -- Skip this update
        end
    end
    
    -- If an update is already in flight, mark that we have a pending update
    -- The callback will retry once the current request completes
    if self.presenceUpdateInFlight then
        self.hasPendingPresenceUpdate = true
        return true  -- Will be sent after current update completes
    end
    
    local presence = self:queryPlayerPresence()
    if not presence or not presence.characterName or presence.characterName == "" then
        return false
    end
    
    -- Deduplicate: only send if something actually changed
    -- Compare against what we're about to send (presence object), not cached values
    -- This is important because queryPlayerPresence() might read from memory instead of cache
    if self.lastSentZoneId == presence.zoneId and
       self.lastSentMainJob == presence.mainJob and
       self.lastSentMainJobLevel == presence.mainJobLevel and
       self.lastSentSubJob == presence.subJob and
       self.lastSentSubJobLevel == presence.subJobLevel and
       self.lastSentIsAnonymous == presence.isAnonymous then
        return true  -- No change, skip update
    end
    
    -- Mark update as in-flight BEFORE sending
    self.presenceUpdateInFlight = true
    
    -- Track what we're about to send
    self.lastSentZoneId = presence.zoneId
    self.lastSentMainJob = presence.mainJob
    self.lastSentMainJobLevel = presence.mainJobLevel
    self.lastSentSubJob = presence.subJob
    self.lastSentSubJobLevel = presence.subJobLevel
    self.lastSentIsAnonymous = presence.isAnonymous
    
    -- Use new server endpoint: POST /api/presence/update
    local requestBody = RequestEncoder.encodePresenceUpdate(presence)
    local url = self.deps.connection:getBaseUrl() .. Endpoints.PRESENCE.UPDATE
    
    local characterName = presence.characterName or ""
    if characterName == "" and self.deps.connection.getCharacterName then
        characterName = self.deps.connection:getCharacterName()
    end
    
    local headers = self.deps.connection:getHeaders(characterName)
    
    local requestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = requestBody,
        callback = function(success, response)
            -- Clear in-flight flag
            self.presenceUpdateInFlight = false
            
            if not success and self.deps.logger and self.deps.logger.error then
                self.deps.logger.error("[Friends] Failed to update presence: " .. tostring(response))
            end
            
            -- If there was a pending update (job changed while request was in flight), send it now
            -- But still respect zone cooldown
            if self.hasPendingPresenceUpdate then
                self.hasPendingPresenceUpdate = false
                
                -- Check zone cooldown before retrying
                local canUpdate = true
                if self.lastZoneOnlyUpdateAt then
                    local timeSinceZoneUpdate = getTime(self) - self.lastZoneOnlyUpdateAt
                    if timeSinceZoneUpdate < 4000 then
                        canUpdate = false
                    end
                end
                
                if canUpdate then
                    self:updatePresence()
                end
            end
        end
    })
    
    return requestId ~= nil
end

-- Send heartbeat (safety signal only - response body is IGNORED)
-- This is NOT polling. Heartbeat is fire-and-forget.
-- WS is the sole source of real-time updates.
function M.Friends:sendHeartbeat()
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    self.heartbeatInFlight = true
    local now = getTime(self)
    self.lastHeartbeatAt = now
    
    local characterName = ""
    if self.deps.connection.getCharacterName then
        characterName = self.deps.connection:getCharacterName() or ""
    end
    if characterName == "" then
        local presence = self:queryPlayerPresence()
        characterName = presence.characterName or ""
    end
    
    if characterName == "" then
        self.heartbeatInFlight = false
        return false
    end
    
    -- Ensure realm ID is available (required by server)
    local realmId = nil
    if self.deps.connection.savedRealmId and self.deps.connection.savedRealmId ~= "" then
        realmId = self.deps.connection.savedRealmId
    elseif self.deps.connection.realmDetector and self.deps.connection.realmDetector.getRealmId then
        realmId = self.deps.connection.realmDetector:getRealmId()
    end
    
    if not realmId or realmId == "" then
        -- Realm not detected yet, skip heartbeat (will retry next interval)
        self.heartbeatInFlight = false
        return false
    end
    
    -- Use new server endpoint: POST /api/presence/heartbeat
    local RequestEncoder = require("protocol.Encoding.RequestEncoder")
    local requestBody = RequestEncoder.encodeHeartbeat()
    
    local url = self.deps.connection:getBaseUrl() .. Endpoints.PRESENCE.HEARTBEAT
    local headers = self.deps.connection:getHeaders(characterName)
    
    -- Ensure X-Realm-Id header is present (server requires it)
    if not headers["X-Realm-Id"] and realmId and realmId ~= "" then
        headers["X-Realm-Id"] = realmId
    end
    
    local requestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = requestBody,
        callback = function(success, response)
            self.heartbeatInFlight = false
            
            -- IGNORE response body entirely (per migration plan)
            -- Heartbeat is fire-and-forget safety signal
            -- WS events are authoritative for all state updates
            
            if not success then
                if self.deps.logger and self.deps.logger.warn then
                    self.deps.logger.warn("[Friends] Heartbeat failed: " .. tostring(response))
                end
            end
        end
    })
    
    return requestId ~= nil
end

-- REMOVED: updateFriendStatuses
-- This method was used for heartbeat status parsing which is now FORBIDDEN
-- WS events are the sole source of real-time updates
-- See: wsEventHandler.lua for WS-based status handling

local function capitalizeName(name)
    if not name or name == "" then
        return name
    end
    local result = name:sub(1, 1):upper() .. name:sub(2):lower()
    return result
end

-- Check for online status changes and trigger notifications
function M.Friends:checkForStatusChanges(currentStatuses)
    if not currentStatuses then
        return
    end
    
    -- Build current online status map
    local currentOnlineStatus = {}
    local displayNames = {}
    
    for _, status in ipairs(currentStatuses) do
        local friendNameLower = string.lower(status.characterName or "")
        if friendNameLower ~= "" then
            currentOnlineStatus[friendNameLower] = status.isOnline == true
            displayNames[friendNameLower] = capitalizeName(status.displayName or status.characterName or friendNameLower)
        end
    end
    
    -- On first scan, store baseline and return (no notifications)
    if not self.initialStatusScanComplete then
        self.previousOnlineStatus = currentOnlineStatus
        self.initialStatusScanComplete = true
        return
    end
    
    -- Compare current vs previous to find transitions
    local onlineTransitions = {}
    local offlineTransitions = {}
    
    for friendName, isCurrentlyOnline in pairs(currentOnlineStatus) do
        local wasPreviouslyOnline = self.previousOnlineStatus[friendName] == true
        
        if not wasPreviouslyOnline and isCurrentlyOnline then
            -- Friend came online
            table.insert(onlineTransitions, displayNames[friendName] or friendName)
        elseif wasPreviouslyOnline and not isCurrentlyOnline then
            -- Friend went offline
            table.insert(offlineTransitions, displayNames[friendName] or friendName)
        end
    end
    
    -- Get notifications feature from app
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notifications then
        local Notifications = require("app.features.notifications")
        
        -- Create toasts for friends coming online
        for _, displayName in ipairs(onlineTransitions) do
            app.features.notifications:push(Notifications.ToastType.FriendOnline, {
                title = "Friend Online",
                message = displayName .. " is now online",
                dedupeKey = "online_" .. string.lower(displayName)
            })
        end
        
        -- Create toasts for friends going offline
        for _, displayName in ipairs(offlineTransitions) do
            app.features.notifications:push(Notifications.ToastType.FriendOffline, {
                title = "Friend Offline",
                message = displayName .. " went offline",
                dedupeKey = "offline_" .. string.lower(displayName)
            })
        end
    end
    
    -- Update previous status with current
    self.previousOnlineStatus = currentOnlineStatus
end

-- Check for new friend requests and trigger notifications
function M.Friends:checkForNewFriendRequests(incomingRequests)
    if not incomingRequests then
        return
    end
    
    local newRequests = {}
    
    for _, request in ipairs(incomingRequests) do
        local requestId = request.id or request.requestId
        if requestId and not self.processedRequestIds[requestId] then
            -- Mark as processed
            self.processedRequestIds[requestId] = true
            
            -- Get display name from the request
            local displayName = request.fromCharacterName or request.name or request.senderName or "Unknown"
            displayName = capitalizeName(displayName)
            
            table.insert(newRequests, displayName)
        end
    end
    
    -- Get notifications feature from app
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notifications then
        local Notifications = require("app.features.notifications")
        
        -- Create toasts for new friend requests
        for _, displayName in ipairs(newRequests) do
            app.features.notifications:push(Notifications.ToastType.FriendRequestReceived, {
                title = "Friend Request",
                message = displayName .. " sent you a friend request",
                dedupeKey = "request_" .. string.lower(displayName)
            })
        end
    end
end

function M.Friends:queryPlayerPresence()
    local presence = {
        characterName = "",
        job = "",
        rank = "",
        nation = 0,
        zone = "",
        isAnonymous = false,
        timestamp = getTime(self)
    }
    
    if not AshitaCore then
        return presence
    end
    
    local memoryMgr = AshitaCore:GetMemoryManager()
    if not memoryMgr then
        return presence
    end
    
    -- Try to get character name from party first
    local party = memoryMgr:GetParty()
    if party then
        local success, playerName = pcall(function()
            return party:GetMemberName(0)
        end)
        if success and playerName and playerName ~= "" then
            presence.characterName = string.lower(playerName)
        end
    end
    
    -- Fallback: try entity manager (wrapped in pcall for safety)
    if presence.characterName == "" then
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
            presence.characterName = result
        end
    end
    
    if presence.characterName == "" then
        return presence
    end
    
    local party = memoryMgr:GetParty()
    local player = memoryMgr:GetPlayer()
    
    -- Use anonymous status from packet detection (0x037)
    local isAnonymous = self.lastKnownAnonStatus or false
    
    -- Always read job data from memory for accuracy
    local mainJob, mainJobLevel, subJob, subJobLevel = getJobDataFromMemory()
    
    if mainJob and mainJobLevel then
        presence.job = self:formatJobString(mainJob, mainJobLevel, subJob, subJobLevel)
        
        -- IMPORTANT: Set mainJob as numeric ID for server
        presence.mainJob = mainJob
        presence.mainJobLevel = mainJobLevel
        
        -- Set separate fields for server
        if mainJobLevel > 0 then
            presence.jobLevel = mainJobLevel
        end
        if subJob and subJob > 0 and subJob < 23 then
            local jobNames = {
                "NON", "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK", "BST",
                "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "BLU", "COR", "PUP", "DNC",
                "SCH", "GEO", "RUN"
            }
            presence.subJob = jobNames[subJob + 1]
            if subJobLevel and subJobLevel > 0 then
                presence.subJobLevel = subJobLevel
            end
        end
    end
    
    if player then
        local playerData = player:GetRawStructure()
        if playerData then
            local playerRank = playerData.Rank
            if playerRank and playerRank > 0 then
                presence.rank = "Rank " .. tostring(playerRank)
            end
            
            presence.nation = playerData.Nation or 0
        end
    end
    
    presence.isAnonymous = isAnonymous
    
    if party then
        local zoneId = party:GetMemberZone(0)
        if zoneId and zoneId > 0 then
            presence.zone = self:getZoneNameFromId(zoneId)
        end
    end
    
    -- Cache this as last valid presence if it has meaningful data
    if presence.characterName ~= "" and presence.job ~= "" then
        self.lastValidPresence = presence
    elseif self.lastValidPresence then
        -- During zone transitions, memory may return empty values
        -- Fall back to last valid presence but update zone if available
        local cachedPresence = {}
        for k, v in pairs(self.lastValidPresence) do
            cachedPresence[k] = v
        end
        if presence.zone ~= "" then
            cachedPresence.zone = presence.zone
        end
        cachedPresence.timestamp = getTime(self)
        return cachedPresence
    end
    
    return presence
end

function M.Friends:formatJobString(mainJob, mainJobLevel, subJob, subJobLevel)
    if not mainJob or mainJob == 0 or not mainJobLevel or mainJobLevel == 0 then
        return ""
    end
    
    local jobNames = {
        "NON", "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK", "BST",
        "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "BLU", "COR", "PUP", "DNC",
        "SCH", "GEO", "RUN"
    }
    
    if mainJob >= 23 then
        return ""
    end
    
    local job = jobNames[mainJob + 1] .. " " .. tostring(mainJobLevel)
    
    if subJob and subJob > 0 and subJobLevel and subJobLevel > 0 and subJob < 23 then
        job = job .. "/" .. jobNames[subJob + 1] .. " " .. tostring(subJobLevel)
    end
    
    return job
end

function M.Friends:getZoneNameFromId(zoneId)
    if not zoneId or zoneId == 0 then
        return "unknown"
    end
    
    if AshitaCore then
        local resourceMgr = AshitaCore:GetResourceManager()
        if resourceMgr then
            local zoneName = resourceMgr:GetString("zones.names", zoneId)
            if zoneName and zoneName ~= "" then
                return zoneName
            end
        end
    end
    
    local zoneMap = {
        [0] = "unknown",
        [1] = "Phanauet Channel",
        [2] = "Carpenters' Landing",
        [3] = "Manaclipper",
        [4] = "Bibiki Bay",
        [5] = "Uleguerand Range",
        [6] = "Bearclaw Pinnacle",
        [7] = "Attohwa Chasm",
        [8] = "Boneyard Gully",
        [9] = "Pso'Xja",
        [10] = "The Shrouded Maw",
        [11] = "Oldton Movalpolos",
        [12] = "Newton Movalpolos",
        [13] = "Mine Shaft #2716",
        [14] = "Hall of Transference",
        [16] = "Promyvion - Holla",
        [17] = "Spire of Holla",
        [18] = "Promyvion - Dem",
        [19] = "Spire of Dem",
        [20] = "Promyvion - Mea",
        [21] = "Spire of Mea",
        [22] = "Promyvion - Vahzl",
        [23] = "Spire of Vahzl",
        [24] = "Lufaise Meadows",
        [25] = "Misareaux Coast",
        [26] = "Tavnazian Safehold",
        [27] = "Phomiuna Aqueducts",
        [28] = "Sacrarium",
        [29] = "Riverne - Site #B01",
        [30] = "Riverne - Site #A01",
        [31] = "Monarch Linn",
        [32] = "Sealion's Den",
        [33] = "Al'Taieu",
        [34] = "Grand Palace of Hu'Xzoi",
        [35] = "The Garden of Ru'Hmet",
        [36] = "Empyreal Paradox",
        [37] = "Temenos",
        [38] = "Apollyon",
        [39] = "Dynamis - Valkurm",
        [40] = "Dynamis - Buburimu",
        [41] = "Dynamis - Qufim",
        [42] = "Dynamis - Tavnazia",
        [43] = "Diorama Abdhaljs-Ghelsba",
        [44] = "Abdhaljs Isle-Purgonorgo",
        [45] = "Abyssea - Tahrongi",
        [46] = "Abyssea - Konschtat",
        [47] = "Abyssea - La Theine",
        [48] = "Abyssea - Misareaux",
        [49] = "Abyssea - Vunkerl",
        [50] = "Abyssea - Attohwa",
        [51] = "Abyssea - Altepa",
        [52] = "Abyssea - Uleguerand",
        [53] = "Abyssea - Grauberg",
        [134] = "King Ranperre's Tomb",
        [135] = "Dangruf Wadi",
        [136] = "Inner Horutoto Ruins",
        [137] = "Ordelle's Caves",
        [138] = "Outer Horutoto Ruins",
        [139] = "Eldieme Necropolis",
        [140] = "Gusgen Mines",
        [141] = "Crawlers' Nest",
        [142] = "Maze of Shakhrami",
        [143] = "Garlaige Citadel",
        [144] = "Fei'Yin",
        [145] = "Ifrit's Cauldron",
        [146] = "Qu'Bia Arena",
        [147] = "Cloister of Flames",
        [148] = "Cloister of Frost",
        [149] = "Cloister of Gales",
        [150] = "Cloister of Storms",
        [151] = "Cloister of Tremors",
        [152] = "Gustav Tunnel",
        [153] = "Labyrinth of Onzozo",
        [160] = "Abyssea - Tahrongi",
        [161] = "Abyssea - Konschtat",
        [162] = "Abyssea - La Theine",
        [163] = "Abyssea - Misareaux",
        [164] = "Abyssea - Vunkerl",
        [165] = "Abyssea - Attohwa",
        [166] = "Abyssea - Altepa",
        [167] = "Abyssea - Uleguerand",
        [168] = "Abyssea - Grauberg",
        [169] = "Abyssea - Empyreal Paradox",
        [184] = "Western Adoulin",
        [185] = "Eastern Adoulin",
        [188] = "Rala Waterways",
        [189] = "Rala Waterways [U]",
        [190] = "Yahse Hunting Grounds",
        [191] = "Ceizak Battlegrounds",
        [192] = "Foret de Hennetiel",
        [193] = "Morimar Basalt Fields",
        [194] = "Marjami Ravine",
        [195] = "Kamihr Drifts",
        [196] = "Sih Gates",
        [197] = "Moh Gates",
        [198] = "Cirdas Caverns",
        [199] = "Cirdas Caverns [U]",
        [200] = "Dho Gates",
        [201] = "Woh Gates",
        [202] = "Outer Ra'Kaznar",
        [203] = "Outer Ra'Kaznar [U]",
        [204] = "Ra'Kaznar Inner Court",
        [211] = "Cloister of Tides",
        [212] = "Gustav Tunnel",
        [213] = "Labyrinth of Onzozo",
        [220] = "Ship bound for Selbina",
        [221] = "Ship bound for Mhaura",
        [223] = "San d'Oria-Jeuno Airship",
        [224] = "Bastok-Jeuno Airship",
        [225] = "Windurst-Jeuno Airship",
        [226] = "Kazham-Jeuno Airship",
        [227] = "Ship bound for Selbina",
        [228] = "Ship bound for Mhaura",
        [230] = "Southern San d'Oria",
        [231] = "Northern San d'Oria",
        [232] = "Port San d'Oria",
        [233] = "Chateau d'Oraguille",
        [234] = "Bastok Mines",
        [235] = "Bastok Markets",
        [236] = "Port Bastok",
        [237] = "Metalworks",
        [238] = "Windurst Waters",
        [239] = "Windurst Walls",
        [240] = "Port Windurst",
        [241] = "Windurst Woods",
        [242] = "Heavens Tower",
        [243] = "Ru'Lude Gardens",
        [244] = "Upper Jeuno",
        [245] = "Lower Jeuno",
        [246] = "Port Jeuno",
        [247] = "Rabao",
        [248] = "Selbina",
        [249] = "Mhaura",
        [250] = "Kazham",
        [251] = "Hall of the Gods",
        [252] = "Norg"
    }
    
    local zoneName = zoneMap[zoneId]
    if zoneName then
        return zoneName
    end
    
    return "Zone " .. tostring(zoneId)
end

function M.Friends:handleStatusUpdate(packet)
end

function M.Friends:_fetchCharacterList()
    if not self.deps.net or not self.deps.connection then
        return
    end
    
    if not self.deps.connection:isConnected() then
        return
    end
    
    local url = self.deps.connection:getBaseUrl() .. Endpoints.FRIENDS.CHARACTER_AND_FRIENDS
    
    local requestId = self.deps.net.request({
        url = url,
        method = "GET",
        headers = self.deps.connection:getHeaders(self:_getCharacterName()),
        body = "",
        callback = function(success, response)
            self:_handleCharacterListResponse(success, response)
        end
    })
end

function M.Friends:_handleCharacterListResponse(success, response)
    if not success then
        return
    end
    
    local ok, envelope, errorMsg = Envelope.decode(response)
    if not ok then
        return
    end
    
    local result = envelope.data or {}
    if result.characters then
        -- Update data module with character list
        local dataModule = require('modules.friendlist.data')
        if dataModule and dataModule.SetCharacters then
            dataModule.SetCharacters(result.characters)
        end
    end
end

return M
