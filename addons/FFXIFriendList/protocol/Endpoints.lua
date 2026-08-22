-- Endpoints.lua
-- New server endpoint definitions (friendlist-server)
-- Source of truth: friendlist-server/src/routes/*.ts

local M = {}

-- API prefix
M.API_PREFIX = "/api"

-- Health check (no auth)
M.HEALTH = "/health"

-- Version (no auth)
M.VERSION = "/api/version"

-- Server list (no auth)
M.SERVERS = "/api/servers"

-- WebSocket upgrade endpoint
M.WEBSOCKET = "/ws"

-- Authentication endpoints
M.AUTH = {
    REGISTER = "/api/auth/register",
    ENSURE = "/api/auth/ensure",
    ADD_CHARACTER = "/api/auth/add-character",
    SET_ACTIVE = "/api/auth/set-active",
    ME = "/api/auth/me"
}

-- Friends endpoints
M.FRIENDS = {
    LIST = "/api/friends",
    SEND_REQUEST = "/api/friends/request",
    REQUESTS_PENDING = "/api/friends/requests/pending",
    REQUESTS_OUTGOING = "/api/friends/requests/outgoing",
    CHARACTER_AND_FRIENDS = "/api/friends/character-and-friends"
}

-- Friend request actions (dynamic paths)
function M.friendRequestAccept(requestId)
    return "/api/friends/requests/" .. tostring(requestId) .. "/accept"
end

function M.friendRequestDecline(requestId)
    return "/api/friends/requests/" .. tostring(requestId) .. "/decline"
end

-- Cancel friend request (dynamic path by requestId)
function M.friendRequestCancel(requestId)
    return "/api/friends/requests/" .. tostring(requestId)
end

-- Remove friend (dynamic path by accountId)
function M.friendRemove(accountId)
    return "/api/friends/" .. tostring(accountId)
end

-- Remove friend visibility only (dynamic path by characterName)
function M.friendVisibilityDelete(characterName)
    return "/api/friends/" .. tostring(characterName) .. "/visibility"
end

-- Block endpoints
M.BLOCK = {
    LIST = "/api/block",
    ADD = "/api/block"
}

-- Unblock (dynamic path by accountId)
function M.blockRemove(accountId)
    return "/api/block/" .. tostring(accountId)
end

-- Preferences endpoints
M.PREFERENCES = "/api/preferences"

-- Presence endpoints
M.PRESENCE = {
    ME = "/api/presence/me",
    UPDATE = "/api/presence/update",
    HEARTBEAT = "/api/presence/heartbeat"
}

return M
