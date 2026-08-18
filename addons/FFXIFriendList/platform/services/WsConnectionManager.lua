-- WsConnectionManager.lua
-- Non-blocking WebSocket connection manager with exponential backoff
-- CRITICAL: All socket operations are non-blocking to prevent game lag
-- Uses a step-machine pattern to spread work across frames

local TimingConstants = require("core.TimingConstants")
local Limits = require("constants.limits")

local M = {}

--------------------------------------------------------------------------------
-- Connection States
--------------------------------------------------------------------------------
M.State = {
    DISCONNECTED = "DISCONNECTED",
    CONNECTING = "CONNECTING",
    CONNECTED = "CONNECTED",
    BACKING_OFF = "BACKING_OFF",
    FAILED = "FAILED"
}

--------------------------------------------------------------------------------
-- Connection Manager
--------------------------------------------------------------------------------
M.WsConnectionManager = {}
M.WsConnectionManager.__index = M.WsConnectionManager

-- Backoff configuration (tunable)
local DEFAULT_CONFIG = {
    baseDelayMs = 1000,           -- 1 second base delay
    maxDelayMs = 60000,           -- 60 seconds max delay
    jitterPercent = 0.2,          -- ±20% jitter
    connectTimeoutMs = 5000,      -- 5 second connect timeout (reduced from 10)
    handshakeTimeoutMs = 5000,    -- 5 second TLS/upgrade timeout
    stableConnectionMs = 30000,   -- Reset backoff after 30s connected
    maxAttempts = Limits.MAX_RECONNECT_ATTEMPTS or 10,
    logThrottleMs = 10000,        -- Log same error at most every 10 seconds
}

function M.WsConnectionManager.new(deps)
    local self = setmetatable({}, M.WsConnectionManager)
    
    deps = deps or {}
    self.deps = deps
    self.logger = deps.logger
    self.wsClient = deps.wsClient
    self.time = deps.time or function() return os.clock() * 1000 end
    
    -- State machine
    self.state = M.State.DISCONNECTED
    self.connectAttemptInFlight = false
    
    -- Backoff tracking
    self.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        self.config[k] = deps.config and deps.config[k] or v
    end
    
    self.attemptCount = 0
    self.nextAttemptAt = nil
    self.lastConnectedAt = nil
    
    -- Log throttling
    self.lastLoggedError = nil
    self.lastLoggedErrorTime = 0
    self.errorCount = 0
    
    -- Status for UI (pre-computed, not per-frame)
    self.statusText = "Disconnected"
    self.statusDetail = ""
    
    -- Wire up disconnect callback from wsClient
    if self.wsClient then
        local manager = self
        self.wsClient:setOnClose(function(reason)
            manager:onConnectionLost(reason)
        end)
    end
    
    return self
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Request a connection (idempotent, non-blocking)
function M.WsConnectionManager:requestConnect()
    if self.state == M.State.CONNECTED then
        return true  -- Already connected
    end
    
    if self.state == M.State.CONNECTING then
        return false  -- Already attempting
    end
    
    if self.state == M.State.BACKING_OFF then
        -- Don't override scheduled retry
        return false
    end
    
    -- Start connecting
    self:_scheduleConnect(0)
    return true
end

-- Request disconnect
function M.WsConnectionManager:disconnect()
    self.state = M.State.DISCONNECTED
    self.nextAttemptAt = nil
    self.attemptCount = 0
    self.connectAttemptInFlight = false
    
    if self.wsClient then
        self.wsClient:disconnect()
    end
    
    self:_updateStatus()
end

-- Called each frame - must be non-blocking
function M.WsConnectionManager:tick()
    local now = self.time()
    
    -- Check if we need to reset backoff (stable connection)
    if self.state == M.State.CONNECTED and self.lastConnectedAt then
        local connectedDuration = now - self.lastConnectedAt
        if connectedDuration >= self.config.stableConnectionMs and self.attemptCount > 0 then
            self.attemptCount = 0  -- Reset backoff
            self:_logThrottled("info", "[WsConnectionManager] Stable connection, backoff reset")
        end
    end
    
    -- Check if scheduled attempt is due
    if self.nextAttemptAt and now >= self.nextAttemptAt then
        self.nextAttemptAt = nil
        self:_attemptConnect()
    end
    
    -- Tick the underlying WsClient (non-blocking message processing only)
    if self.wsClient and self.state == M.State.CONNECTED then
        self.wsClient:tickMessages()
    end
end

-- Get current state
function M.WsConnectionManager:getState()
    return self.state
end

-- Check if connected
function M.WsConnectionManager:isConnected()
    return self.state == M.State.CONNECTED
end

-- Get UI-friendly status (pre-computed, no allocations)
function M.WsConnectionManager:getStatus()
    return self.statusText, self.statusDetail
end

-- Get retry info for UI
function M.WsConnectionManager:getRetryInfo()
    if self.state ~= M.State.BACKING_OFF or not self.nextAttemptAt then
        return nil
    end
    
    local now = self.time()
    local remaining = math.max(0, math.floor((self.nextAttemptAt - now) / 1000))
    return {
        attemptNumber = self.attemptCount,
        maxAttempts = self.config.maxAttempts,
        nextRetryInSeconds = remaining
    }
end

--------------------------------------------------------------------------------
-- Internal Methods
--------------------------------------------------------------------------------

function M.WsConnectionManager:_scheduleConnect(delayMs)
    local now = self.time()
    self.nextAttemptAt = now + delayMs
    
    if delayMs > 0 then
        self.state = M.State.BACKING_OFF
    end
    
    self:_updateStatus()
end

function M.WsConnectionManager:_attemptConnect()
    if self.connectAttemptInFlight then
        return  -- Guard against re-entry
    end
    
    if not self.wsClient then
        self:_handleConnectFailed("No WsClient available")
        return
    end
    
    self.state = M.State.CONNECTING
    self.connectAttemptInFlight = true
    self.attemptCount = self.attemptCount + 1
    
    self:_updateStatus()
    self:_logThrottled("info", "[WsConnectionManager] Connect attempt " .. self.attemptCount)
    
    -- Start async connect (WsClient must implement connectAsync)
    local success, err = self.wsClient:connectAsync({
        connectTimeoutMs = self.config.connectTimeoutMs,
        handshakeTimeoutMs = self.config.handshakeTimeoutMs,
        onSuccess = function()
            self:_handleConnectSuccess()
        end,
        onFailure = function(errorMsg)
            self:_handleConnectFailed(errorMsg)
        end
    })
    
    if not success then
        self:_handleConnectFailed(err or "Connect initiation failed")
    end
end

function M.WsConnectionManager:_handleConnectSuccess()
    self.connectAttemptInFlight = false
    self.state = M.State.CONNECTED
    self.lastConnectedAt = self.time()
    self.errorCount = 0
    
    self:_updateStatus()
    self:_logThrottled("info", "[WsConnectionManager] Connected")
end

function M.WsConnectionManager:_handleConnectFailed(errorMsg)
    self.connectAttemptInFlight = false
    errorMsg = errorMsg or "Unknown error"
    
    -- Track error for throttled logging
    self.errorCount = self.errorCount + 1
    self:_logThrottled("warn", "[WsConnectionManager] " .. errorMsg, errorMsg)
    
    -- Check if max attempts reached
    if self.attemptCount >= self.config.maxAttempts then
        self.state = M.State.FAILED
        self:_updateStatus()
        self:_logThrottled("error", string.format(
            "[WsConnectionManager] Max attempts (%d) reached, giving up",
            self.config.maxAttempts
        ))
        return
    end
    
    -- Schedule retry with exponential backoff + jitter
    local delay = self:_calculateBackoff()
    self:_scheduleConnect(delay)
    
    self:_logThrottled("info", string.format(
        "[WsConnectionManager] Retry in %.1fs (attempt %d/%d)",
        delay / 1000, self.attemptCount, self.config.maxAttempts
    ))
end

function M.WsConnectionManager:_calculateBackoff()
    -- Exponential backoff: base * 2^(attempt-1)
    local delay = self.config.baseDelayMs * (2 ^ (self.attemptCount - 1))
    delay = math.min(delay, self.config.maxDelayMs)
    
    -- Add jitter: ±jitterPercent
    local jitterRange = delay * self.config.jitterPercent
    local jitter = (math.random() * 2 - 1) * jitterRange
    delay = math.floor(delay + jitter)
    
    return math.max(100, delay)  -- Minimum 100ms
end

function M.WsConnectionManager:_updateStatus()
    if self.state == M.State.CONNECTED then
        self.statusText = "Connected"
        self.statusDetail = ""
    elseif self.state == M.State.CONNECTING then
        self.statusText = "Connecting..."
        self.statusDetail = string.format("Attempt %d/%d", self.attemptCount, self.config.maxAttempts)
    elseif self.state == M.State.BACKING_OFF then
        local info = self:getRetryInfo()
        if info then
            self.statusText = "Offline"
            self.statusDetail = string.format("Retry in %ds", info.nextRetryInSeconds)
        else
            self.statusText = "Offline"
            self.statusDetail = "Waiting..."
        end
    elseif self.state == M.State.FAILED then
        self.statusText = "Offline"
        self.statusDetail = "Connection failed"
    else
        self.statusText = "Disconnected"
        self.statusDetail = ""
    end
end

function M.WsConnectionManager:_logThrottled(level, message, errorKey)
    if not self.logger then
        return
    end
    
    local logFn = self.logger[level]
    if not logFn then
        return
    end
    
    -- If errorKey provided, throttle repeated identical errors
    if errorKey then
        local now = self.time()
        if errorKey == self.lastLoggedError and 
           (now - self.lastLoggedErrorTime) < self.config.logThrottleMs then
            return  -- Throttled
        end
        self.lastLoggedError = errorKey
        self.lastLoggedErrorTime = now
    end
    
    logFn(message)
end

-- Notify manager that connection was lost (called by WsClient)
function M.WsConnectionManager:onConnectionLost(reason)
    if self.state ~= M.State.CONNECTED then
        return
    end
    
    self.state = M.State.DISCONNECTED
    self.connectAttemptInFlight = false
    
    self:_logThrottled("warn", "[WsConnectionManager] Connection lost: " .. tostring(reason))
    
    -- Auto-reconnect with initial backoff
    local delay = self:_calculateBackoff()
    self:_scheduleConnect(delay)
end

-- Reset the manager (e.g., when server selection changes)
function M.WsConnectionManager:reset()
    self:disconnect()
    self.attemptCount = 0
    self.errorCount = 0
    self.lastLoggedError = nil
    self.lastLoggedErrorTime = 0
    self:_updateStatus()
end

return M
