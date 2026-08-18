-- RealmDetector.lua
-- Detects the current realm/server by delegating to ServerDetector
-- Provides backwards compatibility with existing code that uses realmId

local ServerDetector = require("platform.services.ServerDetector")

local M = {}
M.RealmDetector = {}
M.RealmDetector.__index = M.RealmDetector

function M.RealmDetector.new(ashitaCore, logger)
    local self = setmetatable({}, M.RealmDetector)
    self.ashitaCore = ashitaCore
    self.logger = logger
    self.cachedRealmId = ""
    self.serverDetector = ServerDetector.ServerDetector.new(ashitaCore, logger)
    self.detectionResult = nil
    return self
end

-- Detect realm using ServerDetector
-- @return realmId string (server id like "horizon", "eden", etc.)
function M.RealmDetector:detectRealm()
    if not self.ashitaCore then
        return ""
    end
    
    -- If manually set, use that
    if self.cachedRealmId ~= "" then
        return self.cachedRealmId
    end
    
    -- Use ServerDetector to auto-detect
    self.detectionResult = self.serverDetector:detect()
    
    if self.detectionResult.success and self.detectionResult.profile then
        self.cachedRealmId = self.detectionResult.profile.id
        return self.cachedRealmId
    end
    
    -- Fallback to "horizon" for backwards compatibility
    return "horizon"
end

-- Get the current realm ID (cached)
function M.RealmDetector:getRealmId()
    if self.cachedRealmId == "" then
        self.cachedRealmId = self:detectRealm()
    end
    return self.cachedRealmId
end

-- Manually set the realm ID (overrides auto-detection)
function M.RealmDetector:setRealmId(realmId)
    self.cachedRealmId = realmId
    if self.serverDetector then
        self.serverDetector:setManualOverride(realmId)
    end
end

-- Clear the cached realm and force re-detection
function M.RealmDetector:clearCache()
    self.cachedRealmId = ""
    self.detectionResult = nil
    if self.serverDetector then
        self.serverDetector:clearManualOverride()
        self.serverDetector:invalidateCache()
    end
end

-- Get the API base URL for the detected server
function M.RealmDetector:getApiBaseUrl()
    if self.detectionResult and self.detectionResult.profile then
        return self.detectionResult.profile.apiBaseUrl
    end
    local ServerConfig = require("core.ServerConfig")
    return ServerConfig.DEFAULT_SERVER_URL
end

-- Get the detected server profile
function M.RealmDetector:getServerProfile()
    if not self.detectionResult then
        self:detectRealm()
    end
    return self.detectionResult and self.detectionResult.profile or nil
end

-- Get detection diagnostics
function M.RealmDetector:getDiagnostics()
    if self.serverDetector then
        return self.serverDetector:getDiagnostics()
    end
    return {
        detectionMethod = "none",
        success = false,
        serverProfile = nil,
        error = "ServerDetector not initialized"
    }
end

-- Check if detection was successful
function M.RealmDetector:isDetectionSuccessful()
    return self.detectionResult ~= nil and self.detectionResult.success == true
end

-- Get the raw detection result (triggers detection if not already done)
function M.RealmDetector:getDetectionResult()
    if not self.detectionResult then
        self:detectRealm()
    end
    return self.detectionResult
end

return M

