local Envelope = require("protocol.Envelope")
local Endpoints = require("protocol.Endpoints")

local M = {}

M.Blocklist = {}
M.Blocklist.__index = M.Blocklist

function M.Blocklist.new(deps)
    local self = setmetatable({}, M.Blocklist)
    self.deps = deps or {}
    
    self.blocked = {}
    self.blockedByAccountId = {}
    self.isLoading = false
    self.lastError = nil
    self.lastUpdateTime = 0
    self.refreshInFlight = false
    
    return self
end

local function getTime(self)
    if self.deps.time then
        return self.deps.time()
    end
    return os.time() * 1000
end

local function log(self, level, message)
    if self.deps.logger and self.deps.logger[level] then
        self.deps.logger[level](message)
    end
end

function M.Blocklist:getState()
    return {
        blocked = self.blocked,
        isLoading = self.isLoading,
        lastError = self.lastError,
        lastUpdateTime = self.lastUpdateTime
    }
end

function M.Blocklist:getBlockedList()
    return self.blocked
end

function M.Blocklist:getBlockedCount()
    return #self.blocked
end

function M.Blocklist:isBlocked(accountId)
    return self.blockedByAccountId[accountId] == true
end

function M.Blocklist:findByName(name)
    local lowerName = string.lower(name or "")
    for _, entry in ipairs(self.blocked) do
        -- Server returns characterName, UI may expect displayName
        local entryName = entry.displayName or entry.characterName or ""
        if string.lower(entryName) == lowerName then
            return entry
        end
    end
    return nil
end

function M.Blocklist:refresh()
    if self.refreshInFlight then
        log(self, "debug", "[Blocklist] refresh() skipped: request already in flight")
        return false
    end
    
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    self.refreshInFlight = true
    self.isLoading = true
    
    local url = self.deps.connection:getBaseUrl() .. Endpoints.BLOCK.LIST
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

function M.Blocklist:handleRefreshResponse(success, response)
    self.refreshInFlight = false
    self.isLoading = false
    
    if not success then
        self.lastError = "Request failed"
        log(self, "warn", "[Blocklist] Failed to refresh: " .. tostring(response))
        return
    end
    
    -- Use new envelope format: { success, data, timestamp }
    local ok, result, errorMsg = Envelope.decode(response)
    if not ok then
        self.lastError = errorMsg or "Failed to decode response"
        log(self, "warn", "[Blocklist] Failed to decode: " .. tostring(errorMsg))
        return
    end
    
    -- Extract blocked list from data
    local data = result.data or {}
    self.blocked = data.blocked or {}
    self.blockedByAccountId = {}
    for _, entry in ipairs(self.blocked) do
        if entry.accountId then
            self.blockedByAccountId[entry.accountId] = true
        end
    end
    
    self.lastError = nil
    self.lastUpdateTime = getTime(self)
    
    log(self, "debug", "[Blocklist] Refreshed: " .. #self.blocked .. " blocked accounts")
end

function M.Blocklist:block(characterName, callback)
    if not self.deps.net or not self.deps.connection then
        if callback then callback(false, "Not connected") end
        return false
    end
    
    if not self.deps.connection:isConnected() then
        if callback then callback(false, "Not connected") end
        return false
    end
    
    -- Use new server endpoint: POST /api/block
    local url = self.deps.connection:getBaseUrl() .. Endpoints.BLOCK.ADD
    
    -- Get current user's character name for authentication headers
    local currentUserCharacterName = self:_getCharacterName()
    local headers = self.deps.connection:getHeaders(currentUserCharacterName)
    
    -- Get realm ID for the request
    local realmId = "unknown"
    if self.deps.connection.savedRealmId and self.deps.connection.savedRealmId ~= "" then
        realmId = self.deps.connection.savedRealmId
    elseif self.deps.connection.realmDetector and self.deps.connection.realmDetector.getRealmId then
        realmId = self.deps.connection.realmDetector:getRealmId() or "unknown"
    end
    
    -- New server expects: { characterName, realmId }
    local RequestEncoder = require("protocol.Encoding.RequestEncoder")
    local body = RequestEncoder.encodeBlock(tostring(characterName), realmId)
    
    local requestId = self.deps.net.request({
        url = url,
        method = "POST",
        headers = headers,
        body = body,
        callback = function(success, response)
            self:handleBlockResponse(success, response, characterName, callback)
        end
    })
    
    return requestId ~= nil
end

function M.Blocklist:handleBlockResponse(success, response, characterName, callback)
    if not success then
        log(self, "warn", "[Blocklist] Failed to block " .. tostring(characterName) .. ": " .. tostring(response))
        if callback then callback(false, "Request failed") end
        return
    end
    
    -- Use new envelope format: { success, data, timestamp }
    local ok, result, errorMsg = Envelope.decode(response)
    if not ok then
        log(self, "warn", "[Blocklist] Failed to decode block response: " .. tostring(errorMsg))
        if callback then callback(false, errorMsg or "Failed to decode response") end
        return
    end
    
    log(self, "info", "[Blocklist] Blocked " .. tostring(characterName))
    
    -- Refresh blocklist to get updated list from server
    -- (WS blocked event only goes to the blocked person, not the blocker)
    self:refresh()
    
    if callback then
        callback(true, {
            blocked = true
        })
    end
end

function M.Blocklist:unblock(accountId, callback)
    if not self.deps.net or not self.deps.connection then
        if callback then callback(false, "Not connected") end
        return false
    end
    
    if not self.deps.connection:isConnected() then
        if callback then callback(false, "Not connected") end
        return false
    end
    
    local url = self.deps.connection:getBaseUrl() .. Endpoints.blockRemove(accountId)
    local currentCharacterName = self:_getCharacterName()
    local headers = self.deps.connection:getHeaders(currentCharacterName)
    
    local requestId = self.deps.net.request({
        url = url,
        method = "DELETE",
        headers = headers,
        body = "",
        callback = function(success, response)
            self:handleUnblockResponse(success, response, accountId, callback)
        end
    })
    
    return requestId ~= nil
end

function M.Blocklist:handleUnblockResponse(success, response, accountId, callback)
    if not success then
        log(self, "warn", "[Blocklist] Failed to unblock accountId " .. tostring(accountId) .. ": " .. tostring(response))
        if callback then callback(false, "Request failed") end
        return
    end
    
    -- Use new envelope format: { success, data, timestamp }
    local ok, result, errorMsg = Envelope.decode(response)
    if not ok then
        log(self, "warn", "[Blocklist] Failed to decode unblock response: " .. tostring(errorMsg))
        if callback then callback(false, errorMsg or "Failed to decode response") end
        return
    end
    
    log(self, "info", "[Blocklist] Unblocked accountId " .. tostring(accountId))
    
    -- Refresh blocklist to get updated list from server
    -- (WS unblocked event only goes to the unblocked person, not the unblocker)
    self:refresh()
    
    if callback then
        callback(true, {
            unblocked = true
        })
    end
end

function M.Blocklist:unblockByName(characterName, callback)
    local entry = self:findByName(characterName)
    if not entry then
        if callback then callback(false, "Player not found in blocklist") end
        return false
    end
    
    return self:unblock(entry.accountId, callback)
end

function M.Blocklist:_getCharacterName()
    -- Try to get character name from connection (same pattern as preferences.lua)
    if self.deps.connection then
        if self.deps.connection.getCharacterName then
            local name = self.deps.connection:getCharacterName()
            if name and name ~= "" then
                return name
            end
        end
        if self.deps.connection.lastCharacterName then
            local name = self.deps.connection.lastCharacterName
            if name and name ~= "" then
                return name
            end
        end
    end
    
    -- Fallback: try to get from app
    local app = _G.FFXIFriendListApp
    if app and app.getCharacterName then
        return app.getCharacterName()
    end
    
    return nil
end

return M

