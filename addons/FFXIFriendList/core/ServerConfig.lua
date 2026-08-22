-- ServerConfig.lua
-- Centralized server URL configuration
-- This is the SINGLE SOURCE OF TRUTH for the default server URL

local M = {}

-- Default server URL - used when no saved URL is available
-- This value may change between releases (e.g., api.* -> api2.*)
M.DEFAULT_SERVER_URL = "https://api2.horizonfriendlist.com"

-- WebSocket path (appended to server URL)
M.WS_PATH = "/ws"

-- Build full WebSocket URL from base URL
function M.getWsUrl(baseUrl)
    baseUrl = baseUrl or M.DEFAULT_SERVER_URL
    -- Convert https:// to wss://
    local wsUrl = baseUrl:gsub("^https://", "wss://"):gsub("^http://", "ws://")
    return wsUrl .. M.WS_PATH
end

return M
