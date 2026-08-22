-- wsEventHandler.lua
-- Dispatches WebSocket events to existing state update methods
-- Triggers notifications on relevant events

local WsEnvelope = require("protocol.WsEnvelope")
local FriendList = require("core.friendlist")
local utils = require("modules.friendlist.components.helpers.utils")

local M = {}

-- Job abbreviation lookup table
local JOB_NAMES = {
    "NON", "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK", "BST",
    "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "BLU", "COR", "PUP", "DNC",
    "SCH", "GEO", "RUN"
}

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

M.WsEventHandler = {}
M.WsEventHandler.__index = M.WsEventHandler

-- Create a new event handler
-- deps: { logger, friends, blocklist, preferences, notifications, connection, tags, notes }
function M.WsEventHandler.new(deps)
    local self = setmetatable({}, M.WsEventHandler)
    self.deps = deps or {}
    self.logger = deps.logger
    
    return self
end

-- Main event handler function (called by App.lua which gets events from WsEventRouter)
-- Signature matches router callback: (payload, eventType, seq, timestamp)
function M.WsEventHandler:handleEvent(payload, eventType, seq, timestamp)
    -- Call internal handler with appropriate event type
    self:_dispatch(eventType, payload)
end

-- Internal dispatch by event type
-- Event types are string values from friendlist-server/src/types/events.ts
function M.WsEventHandler:_dispatch(eventType, payload)
    if eventType == "connected" then
        self:_handleConnected(payload)
    elseif eventType == "friends_snapshot" then
        self:_handleFriendsSnapshot(payload)
    elseif eventType == "friend_online" then
        self:_handleFriendOnline(payload)
    elseif eventType == "friend_offline" then
        self:_handleFriendOffline(payload)
    elseif eventType == "friend_state_changed" then
        self:_handleFriendStateChanged(payload)
    elseif eventType == "friend_added" then
        self:_handleFriendAdded(payload)
    elseif eventType == "friend_removed" then
        self:_handleFriendRemoved(payload)
    elseif eventType == "friend_request_received" then
        self:_handleFriendRequestReceived(payload)
    elseif eventType == "friend_request_accepted" then
        self:_handleFriendRequestAccepted(payload)
    elseif eventType == "friend_request_declined" then
        self:_handleFriendRequestDeclined(payload)
    elseif eventType == "blocked" then
        self:_handleBlocked(payload)
    elseif eventType == "unblocked" then
        self:_handleUnblocked(payload)
    elseif eventType == "preferences_updated" then
        self:_handlePreferencesUpdated(payload)
    elseif eventType == "error" then
        self:_handleError(payload)
    else
        if self.logger and self.logger.warn then
            self.logger.warn("[WsEventHandler] Unknown event type: " .. tostring(eventType))
        end
    end
end

-- Handle 'connected' event
function M.WsEventHandler:_handleConnected(payload)
    -- Update connection state
    if self.deps.connection and self.deps.connection.setConnected then
        self.deps.connection:setConnected()
    end
end

-- Handle 'friends_snapshot' event - full friend list
function M.WsEventHandler:_handleFriendsSnapshot(payload)
    local friends = self.deps.friends
    if not friends then return end
    
    -- Clear existing friend list and repopulate
    if friends.friendList then
        friends.friendList:clear()
    end
    
    local friendsData = payload.friends or {}
    
    for _, friendData in ipairs(friendsData) do
        self:_addFriendFromPayload(friendData)
    end
    
    -- Update last updated timestamp
    friends.lastUpdatedAt = self:_getTime()
    friends.state = "idle"
end

-- Handle 'friend_online' event
function M.WsEventHandler:_handleFriendOnline(payload)
    local friends = self.deps.friends
    if not friends or not friends.friendList then return end
    
    local accountId = payload.accountId
    local characterName = payload.characterName
    local state = payload.state
    local isAway = payload.isAway or false
    local realmId = payload.realmId
    
    -- Update realmId on the Friend object (not just FriendStatus)
    local allFriends = friends.friendList:getFriends()
    for _, friend in ipairs(allFriends) do
        if friend.friendAccountId == accountId then
            if realmId then
                friend.realmId = realmId
            end
            break
        end
    end
    
    -- Update friend status - preserve existing status instead of creating new
    local status = friends.friendList:getFriendStatus(string.lower(characterName or ""))
    if not status then
        status = FriendList.FriendStatus.new()
        status.characterName = string.lower(characterName or "")
    end
    
    status.isOnline = true
    status.isAway = isAway
    
    -- Only update fields that are present in state
    if state then
        if state.job ~= nil or state.subJob ~= nil or state.jobLevel ~= nil or state.subJobLevel ~= nil then
            local formattedJob = formatJobFromState(state)
            if formattedJob ~= "" then
                status.job = formattedJob
            end
        end
        if state.zone ~= nil then status.zone = state.zone end
        if state.nation ~= nil then status.nation = state.nation end
        if state.rank ~= nil then status.rank = state.rank end
    end
    
    friends.friendList:updateFriendStatus(status)
    friends.lastUpdatedAt = self:_getTime()
    
    -- Trigger notification
    self:_notifyFriendOnline(characterName)
end

-- Handle 'friend_offline' event
function M.WsEventHandler:_handleFriendOffline(payload)
    local friends = self.deps.friends
    if not friends or not friends.friendList then return end
    
    local accountId = payload.accountId
    local lastSeen = payload.lastSeen
    -- Normalize lastSeen to numeric timestamp (handles ISO8601 from server)
    local lastSeenAt = utils.normalizeLastSeen(lastSeen)
    
    -- Find friend by account ID and update status
    local allFriends = friends.friendList:getFriends()
    for _, friend in ipairs(allFriends) do
        if friend.friendAccountId == accountId then
            -- Get existing status to preserve job/zone/nation/rank data
            local status = friends.friendList:getFriendStatus(friend.name)
            if not status then
                status = FriendList.FriendStatus.new()
                status.characterName = string.lower(friend.name or "")
            end
            -- Only update online status and lastSeen, preserve everything else
            status.isOnline = false
            status.isAway = false
            status.lastSeenAt = lastSeenAt
            friends.friendList:updateFriendStatus(status)
            break
        end
    end
    
    friends.lastUpdatedAt = self:_getTime()
end

-- Handle 'friend_state_changed' event
function M.WsEventHandler:_handleFriendStateChanged(payload)
    local friends = self.deps.friends
    if not friends or not friends.friendList then return end
    
    local accountId = payload.accountId
    local state = payload.state or {}
    
    -- Find friend by account ID and update state
    local allFriends = friends.friendList:getFriends()
    for _, friend in ipairs(allFriends) do
        if friend.friendAccountId == accountId then
            local status = friends.friendList:getFriendStatus(friend.name)
            if status then
                -- Only update fields that are actually present in the partial state
                -- This prevents zone-only updates from wiping job/nation data
                
                -- Check if ANY job field is present before formatting
                if state.job ~= nil or state.subJob ~= nil or state.jobLevel ~= nil or state.subJobLevel ~= nil then
                    local formattedJob = formatJobFromState(state)
                    if formattedJob ~= "" then 
                        status.job = formattedJob 
                    end
                end
                
                if state.zone ~= nil then status.zone = state.zone end
                if state.nation ~= nil then status.nation = state.nation end
                if state.rank ~= nil then status.rank = state.rank end
                
                friends.friendList:updateFriendStatus(status)
            end
            break
        end
    end
    
    friends.lastUpdatedAt = self:_getTime()
end

-- Handle 'friend_added' event
function M.WsEventHandler:_handleFriendAdded(payload)
    local friends = self.deps.friends
    if not friends or not friends.friendList then return end
    
    local friendData = payload.friend
    if friendData then
        self:_addFriendFromPayload(friendData)
        friends.lastUpdatedAt = self:_getTime()
        
        -- Clean up any incoming request from this account (request was accepted)
        if friendData.accountId then
            self:_removeRequestByAccountId(friends.incomingRequests, friendData.accountId)
        end
        
        -- Show notification with online status (isOnline is directly in payload)
        local characterName = friendData.characterName
        local isOnline = friendData.isOnline == true
        if characterName and characterName ~= "" then
            self:_notifyFriendAdded(characterName, isOnline)
        end
    end
end

-- Handle 'friend_removed' event
function M.WsEventHandler:_handleFriendRemoved(payload)
    local friends = self.deps.friends
    if not friends or not friends.friendList then return end
    
    -- Server sends { accountId, friendAccountId } - we need to find which one is the friend to remove
    local accountId = payload.accountId
    local friendAccountId = payload.friendAccountId
    
    -- Find and remove friend by either account ID (we could be on either side of the relationship)
    local allFriends = friends.friendList:getFriends()
    for _, friend in ipairs(allFriends) do
        if friend.friendAccountId == accountId or friend.friendAccountId == friendAccountId then
            friends.friendList:removeFriend(friend.name)
            -- Clear any mute entry for this friend
            if self.deps.preferences and friend.friendAccountId then
                self.deps.preferences:clearFriendMute(friend.friendAccountId)
            end
            break
        end
    end
    
    friends.lastUpdatedAt = self:_getTime()
end

-- Handle 'friend_request_received' event
function M.WsEventHandler:_handleFriendRequestReceived(payload)
    local friends = self.deps.friends
    if not friends then return end
    
    -- Check for duplicate (same requestId already in list)
    for _, existing in ipairs(friends.incomingRequests) do
        if existing.id == payload.requestId then
            return
        end
    end
    
    -- Normalize to UI-expected format: { id, name, accountId, createdAt }
    -- UI expects 'name' and 'accountId' for display and block button
    local request = {
        id = payload.requestId,
        name = payload.fromCharacterName,      -- UI displays this
        accountId = payload.fromAccountId,     -- UI uses for block
        fromAccountId = payload.fromAccountId, -- Keep for compatibility
        fromCharacterName = payload.fromCharacterName,
        createdAt = payload.createdAt
    }
    
    table.insert(friends.incomingRequests, request)
    
    -- Trigger notification
    self:_notifyFriendRequest(payload.fromCharacterName)
end

-- Handle 'friend_request_accepted' event
-- Server sends this to BOTH parties, so we need to clean up both lists
function M.WsEventHandler:_handleFriendRequestAccepted(payload)
    local friends = self.deps.friends
    if not friends then return end
    
    local requestId = payload.requestId
    
    -- Remove from BOTH incoming and outgoing requests (idempotent for both parties)
    self:_removeRequestById(friends.outgoingRequests, requestId)
    self:_removeRequestById(friends.incomingRequests, requestId)
    
    -- Show notification with the OTHER character's name (not our own)
    -- Get current character name for comparison
    local myCharacterName = nil
    if self.deps.connection and self.deps.connection.getCharacterName then
        myCharacterName = self.deps.connection:getCharacterName()
    elseif self.deps.connection and self.deps.connection.lastCharacterName then
        myCharacterName = self.deps.connection.lastCharacterName
    end
    myCharacterName = myCharacterName and string.lower(myCharacterName) or ""
    
    -- Pick the name that is NOT ours
    local acceptorName = payload.acceptorCharacterName or ""
    local requesterName = payload.requesterCharacterName or ""
    local friendName = nil
    
    if myCharacterName ~= "" and string.lower(acceptorName) == myCharacterName then
        -- We are the acceptor, show the requester's name
        friendName = requesterName
    elseif myCharacterName ~= "" and string.lower(requesterName) == myCharacterName then
        -- We are the requester, show the acceptor's name
        friendName = acceptorName
    else
        -- Fallback: show whichever name is available
        friendName = acceptorName ~= "" and acceptorName or requesterName
    end
    
    if friendName and friendName ~= "" then
        -- Note: Notification is now triggered from _handleFriendAdded where isOnline is available
        -- This handler just cleans up the request lists
    end
end

-- Handle 'friend_request_declined' event
-- MUST remove from BOTH incoming AND outgoing (idempotent)
function M.WsEventHandler:_handleFriendRequestDeclined(payload)
    local friends = self.deps.friends
    if not friends then return end
    
    local requestId = payload.requestId
    local declinedBy = payload.declinedBy
    
    -- Show notification if someone declined your outgoing request
    if declinedBy and declinedBy ~= "" then
        local notifications = self.deps.notifications
        if notifications then
            notifications:push(Notifications.ToastType.FriendRequestRejected, {
                title = "Friend Request Declined",
                message = declinedBy .. " declined your friend request",
                dedupeKey = "rejected_" .. string.lower(declinedBy)
            })
        end
    end
    
    -- Remove from BOTH lists (per plan requirement)
    self:_removeRequestById(friends.incomingRequests, requestId)
    self:_removeRequestById(friends.outgoingRequests, requestId)
end

-- Handle 'blocked' event
function M.WsEventHandler:_handleBlocked(payload)
    local blocklist = self.deps.blocklist
    if not blocklist then return end
    
    -- Refresh blocklist from server
    if blocklist.refresh then
        blocklist:refresh()
    end
end

-- Handle 'unblocked' event
function M.WsEventHandler:_handleUnblocked(payload)
    local blocklist = self.deps.blocklist
    if not blocklist then return end
    
    -- Refresh blocklist from server
    if blocklist.refresh then
        blocklist:refresh()
    end
end

-- Handle 'preferences_updated' event
function M.WsEventHandler:_handlePreferencesUpdated(payload)
    local preferences = self.deps.preferences
    if not preferences then return end
    
    local prefs = payload.preferences or {}
    
    -- Apply server preferences
    if prefs.presenceStatus then
        preferences.prefs.presenceStatus = prefs.presenceStatus
        preferences.prefs.showOnlineStatus = prefs.presenceStatus ~= "invisible"
    end
    if prefs.shareLocation ~= nil then
        preferences.prefs.shareLocation = prefs.shareLocation
    end
    if prefs.shareJobWhenAnonymous ~= nil then
        preferences.prefs.shareJobWhenAnonymous = prefs.shareJobWhenAnonymous
    end
    
    -- Save locally
    if preferences.save then
        preferences:save()
    end
end

-- Handle 'error' event
function M.WsEventHandler:_handleError(payload)
    if self.logger and self.logger.warn then
        self.logger.warn(string.format("[WsEventHandler] Server error: %s - %s",
            tostring(payload.code), tostring(payload.message)))
    end
end

-- Helper: Add friend from payload data
function M.WsEventHandler:_addFriendFromPayload(friendData)
    local friends = self.deps.friends
    if not friends or not friends.friendList then 
        if self.logger and self.logger.warn then
            self.logger.warn("[WsEventHandler] _addFriendFromPayload: friends or friendList is nil")
        end
        return 
    end
    
    local displayName = friendData.characterName or ""
    if displayName == "" then
        if self.logger and self.logger.warn then
            self.logger.warn("[WsEventHandler] _addFriendFromPayload: empty characterName")
        end
        return
    end
    
    -- Use addedAsCharacterName from server if available, otherwise fallback to friend's name
    local friendedAs = friendData.addedAsCharacterName or displayName
    local friend = FriendList.Friend.new(displayName, friendedAs)
    friend.friendAccountId = friendData.accountId
    friend.isOnline = friendData.isOnline == true
    friend.isAway = friendData.isAway == true  -- BUG 3 FIX: Read isAway from payload
    -- Normalize lastSeen to numeric timestamp (handles ISO8601 from server)
    friend.lastSeenAt = utils.normalizeLastSeen(friendData.lastSeen)
    -- Store realm ID for cross-server friend display
    friend.realmId = friendData.realmId or nil
    
    -- Initialize job fields even if state is nil
    friend.job = ""
    friend.zone = ""
    friend.nation = nil
    friend.rank = nil
    
    if friendData.state then
        friend.job = formatJobFromState(friendData.state)
        friend.zone = friendData.state.zone or ""
        friend.nation = friendData.state.nation
        friend.rank = friendData.state.rank
    end
    
    local addResult = friends.friendList:addFriend(friend)
    
    -- Consume any pending tag for this friend
    if self.deps.tags and self.deps.tags.consumePendingTag then
        local pendingTag = self.deps.tags:consumePendingTag(displayName)
        if pendingTag then
            self.deps.tags:setTagForFriend(displayName, pendingTag)
        end
    end
    
    -- Consume any pending note for this friend
    if self.deps.notes and self.deps.notes.consumePendingNote then
        local pendingNote = self.deps.notes:consumePendingNote(displayName)
        if pendingNote then
            self.deps.notes:setNote(displayName, pendingNote)
            -- Save notes after applying pending note
            if self.deps.notes.save then
                self.deps.notes:save()
            end
        end
    end
    
    -- Also add status
    local status = FriendList.FriendStatus.new()
    status.characterName = string.lower(displayName)
    status.displayName = displayName
    status.isOnline = friend.isOnline
    status.isAway = friend.isAway  -- BUG 3 FIX: Copy isAway from friend to status
    status.lastSeenAt = friend.lastSeenAt
    
    -- Initialize status fields even if state is nil
    status.job = ""
    status.zone = ""
    status.nation = nil
    status.rank = nil
    
    if friendData.state then
        status.job = formatJobFromState(friendData.state)
        status.zone = friendData.state.zone or ""
        status.nation = friendData.state.nation
        status.rank = friendData.state.rank
    end
    friends.friendList:updateFriendStatus(status)
end

-- Helper: Remove request by ID from a list
function M.WsEventHandler:_removeRequestById(requestList, requestId)
    for i = #requestList, 1, -1 do
        local req = requestList[i]
        if req.id == requestId or req.requestId == requestId then
            table.remove(requestList, i)
        end
    end
end

-- Helper: Remove request by account ID from a list
function M.WsEventHandler:_removeRequestByAccountId(requestList, accountId)
    for i = #requestList, 1, -1 do
        local req = requestList[i]
        if req.accountId == accountId or req.fromAccountId == accountId then
            table.remove(requestList, i)
        end
    end
end

-- Helper: Trigger friend online notification
function M.WsEventHandler:_notifyFriendOnline(characterName)
    local notifications = self.deps.notifications
    if not notifications then return end
    
    -- Check global mute preference
    local preferences = self.deps.preferences
    if preferences and preferences.prefs then
        if preferences.prefs.dontSendNotificationsGlobal then
            return  -- Global mute enabled
        end
    end
    
    -- Find friend by character name to get accountId and lastSeenAt
    local friends = self.deps.friends
    if friends and friends.friendList then
        local allFriends = friends.friendList:getFriends()
        for _, friend in ipairs(allFriends) do
            if string.lower(friend.name) == string.lower(characterName) then
                -- Check per-friend mute
                if preferences and friend.friendAccountId then
                    if preferences:isFriendMuted(friend.friendAccountId) then
                        return  -- Friend is muted
                    end
                end
                
                
                break
            end
        end
    end
    
    local Notifications = require("app.features.notifications")
    local displayName = self:_capitalizeName(characterName or "")
    
    notifications:push(Notifications.ToastType.FriendOnline, {
        title = "Friend Online",
        message = displayName .. " is now online",
        dedupeKey = "online_" .. string.lower(displayName)
    })
end

-- Helper: Trigger friend added notification (request accepted)
-- isOnline: optional boolean indicating friend's online status
function M.WsEventHandler:_notifyFriendAdded(characterName, isOnline)
    local notifications = self.deps.notifications
    if not notifications then return end
    
    local Notifications = require("app.features.notifications")
    local displayName = self:_capitalizeName(characterName or "")
    
    notifications:push(Notifications.ToastType.FriendRequestAccepted, {
        title = "Friend Added",
        message = displayName .. " is now your friend",
        dedupeKey = "added_" .. string.lower(displayName),
        isOnline = isOnline,
        characterName = displayName
    })
end

-- Helper: Trigger friend request notification
function M.WsEventHandler:_notifyFriendRequest(characterName)
    local notifications = self.deps.notifications
    if not notifications then return end
    
    local Notifications = require("app.features.notifications")
    local displayName = self:_capitalizeName(characterName or "")
    
    notifications:push(Notifications.ToastType.FriendRequestReceived, {
        title = "Friend Request",
        message = displayName .. " sent you a friend request",
        dedupeKey = "request_" .. string.lower(displayName)
    })
end

-- Helper: Capitalize name
function M.WsEventHandler:_capitalizeName(name)
    if not name or name == "" then return name end
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- Helper: Get current time
function M.WsEventHandler:_getTime()
    if self.deps.time then
        return self.deps.time()
    end
    return os.time() * 1000
end

return M

