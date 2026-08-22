-- WsEnvelope.lua
-- WebSocket event envelope decoding
-- Server pushes: { type, timestamp, protocolVersion, seq, payload }

local Json = require("protocol.Json")

local M = {}

M.DecodeError = {
    InvalidJson = "InvalidJson",
    MissingType = "MissingType",
    MissingPayload = "MissingPayload"
}

-- Decode a WebSocket event envelope
-- Returns: success, event (or error code, error message)
function M.decode(jsonString)
    if not jsonString or jsonString == "" then
        return false, M.DecodeError.InvalidJson, "Empty message"
    end
    
    local ok, data = Json.decode(jsonString)
    if not ok then
        local errorMsg = data
        if type(errorMsg) == "table" then
            errorMsg = "Invalid JSON"
        else
            errorMsg = tostring(errorMsg or "Invalid JSON")
        end
        return false, M.DecodeError.InvalidJson, errorMsg
    end
    
    if type(data) ~= "table" then
        return false, M.DecodeError.InvalidJson, "Message is not an object"
    end
    
    -- Type is required
    if not data.type or type(data.type) ~= "string" then
        return false, M.DecodeError.MissingType, "Missing event type"
    end
    
    -- Build event object
    local event = {
        type = data.type,
        timestamp = data.timestamp or "",
        protocolVersion = data.protocolVersion or "1.0.0",
        seq = data.seq or 0,
        requestId = data.requestId,
        payload = data.payload or {}
    }
    
    return true, event
end

-- Event types (from friendlist-server/src/types/events.ts)
M.EventType = {
    Connected = "connected",
    FriendsSnapshot = "friends_snapshot",
    FriendOnline = "friend_online",
    FriendOffline = "friend_offline",
    FriendStateChanged = "friend_state_changed",
    FriendAdded = "friend_added",
    FriendRemoved = "friend_removed",
    FriendRequestReceived = "friend_request_received",
    FriendRequestAccepted = "friend_request_accepted",
    FriendRequestDeclined = "friend_request_declined",
    Blocked = "blocked",
    Unblocked = "unblocked",
    PreferencesUpdated = "preferences_updated",
    Error = "error"
}

return M

