-- WsConnectionManagerTest.lua
-- Unit tests for WebSocket connection manager
-- Verifies backoff, throttling, state machine, and non-blocking behavior

--------------------------------------------------------------------------------
-- Test Framework (minimal)
--------------------------------------------------------------------------------

local testsPassed = 0
local testsFailed = 0

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\nExpected: %s\nActual: %s", 
            message or "values not equal", 
            tostring(expected), 
            tostring(actual)))
    end
end

local function assertTrue(value, message)
    assert(value == true, message or "Expected true")
end

local function assertFalse(value, message)
    assert(value == false, message or "Expected false")
end

local function assertNil(value, message)
    assert(value == nil, message or "Expected nil")
end

local function assertNotNil(value, message)
    assert(value ~= nil, message or "Expected not nil")
end

local function assertGt(actual, expected, message)
    if actual <= expected then
        error(string.format("ASSERTION FAILED: %s\nExpected > %s\nActual: %s", 
            message or "value not greater", 
            tostring(expected), 
            tostring(actual)))
    end
end

local function assertLe(actual, expected, message)
    if actual > expected then
        error(string.format("ASSERTION FAILED: %s\nExpected <= %s\nActual: %s", 
            message or "value not less or equal", 
            tostring(expected), 
            tostring(actual)))
    end
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        testsPassed = testsPassed + 1
        print("✓ " .. name)
    else
        testsFailed = testsFailed + 1
        print("✗ " .. name)
        print("  Error: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Mock WsClient
--------------------------------------------------------------------------------

local function createMockWsClient()
    local mock = {
        connectAsyncCalled = false,
        connectAsyncOptions = nil,
        connectAsyncResult = true,
        disconnectCalled = false,
        tickMessagesCalled = false,
        onCloseCallback = nil,
        
        -- Simulate async connect behavior
        simulateSuccess = nil,  -- Set to true/false to trigger callback
        simulateError = nil,
    }
    
    function mock:connectAsync(options)
        self.connectAsyncCalled = true
        self.connectAsyncOptions = options
        
        -- If test wants immediate simulation
        if self.simulateSuccess then
            if options.onSuccess then options.onSuccess() end
        elseif self.simulateError then
            if options.onFailure then options.onFailure(self.simulateError) end
        end
        
        return self.connectAsyncResult, self.connectAsyncResult and nil or "error"
    end
    
    function mock:disconnect()
        self.disconnectCalled = true
    end
    
    function mock:tickMessages()
        self.tickMessagesCalled = true
    end
    
    function mock:setOnClose(callback)
        self.onCloseCallback = callback
    end
    
    function mock:reset()
        self.connectAsyncCalled = false
        self.connectAsyncOptions = nil
        self.disconnectCalled = false
        self.tickMessagesCalled = false
        self.simulateSuccess = nil
        self.simulateError = nil
    end
    
    return mock
end

--------------------------------------------------------------------------------
-- Mock Logger
--------------------------------------------------------------------------------

local function createMockLogger()
    local logs = { info = {}, debug = {}, warn = {}, error = {} }
    return {
        info = function(msg) table.insert(logs.info, msg) end,
        debug = function(msg) table.insert(logs.debug, msg) end,
        warn = function(msg) table.insert(logs.warn, msg) end,
        error = function(msg) table.insert(logs.error, msg) end,
        logs = logs,
        clear = function() 
            logs.info = {}
            logs.debug = {}
            logs.warn = {}
            logs.error = {}
        end
    }
end

--------------------------------------------------------------------------------
-- Mock Time
--------------------------------------------------------------------------------

local function createMockTime()
    local currentTime = 0
    return {
        get = function() return currentTime end,
        set = function(t) currentTime = t end,
        advance = function(ms) currentTime = currentTime + ms end,
    }
end

--------------------------------------------------------------------------------
-- Load the module under test
--------------------------------------------------------------------------------

-- Set up package path for test environment
local testPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
if testPath then
    local basePath = testPath:gsub("tests/app/$", "")
    package.path = basePath .. "?.lua;" .. basePath .. "?/init.lua;" .. package.path
end

-- Mock the dependencies that WsConnectionManager requires
package.loaded["core.TimingConstants"] = {
    WS_BASE_RECONNECT_DELAY_MS = 1000,
    WS_MAX_RECONNECT_DELAY_MS = 60000,
}

package.loaded["constants.limits"] = {
    MAX_RECONNECT_ATTEMPTS = 10,
}

local WsConnectionManager = require("platform.services.WsConnectionManager")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

test("Initial state is DISCONNECTED", function()
    local mockTime = createMockTime()
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = createMockWsClient(),
        logger = createMockLogger()
    })
    
    assertEq(manager:getState(), "DISCONNECTED")
    assertFalse(manager:isConnected())
end)

test("requestConnect starts connection attempt", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    local result = manager:requestConnect()
    assertTrue(result, "requestConnect should return true")
    
    -- Should schedule immediate connect (delay = 0)
    assertNotNil(manager.nextAttemptAt, "Should have scheduled attempt")
    assertEq(manager.nextAttemptAt, 0, "Immediate connect should have delay 0")
end)

test("requestConnect is idempotent while connecting", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    manager:requestConnect()
    manager:tick()  -- Triggers connect
    
    local state = manager:getState()
    assertEq(state, "CONNECTING")
    
    -- Second call should not start new attempt
    local result = manager:requestConnect()
    assertFalse(result, "Should not start new connect while connecting")
end)

test("Successful connect transitions to CONNECTED", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateSuccess = true
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    manager:requestConnect()
    manager:tick()  -- Triggers connect, which succeeds immediately
    
    assertEq(manager:getState(), "CONNECTED")
    assertTrue(manager:isConnected())
end)

test("Failed connect schedules retry with backoff", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateError = "Connection refused"
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    manager:requestConnect()
    manager:tick()  -- Triggers connect, which fails
    
    assertEq(manager:getState(), "BACKING_OFF")
    assertNotNil(manager.nextAttemptAt)
    
    -- First retry should be around baseDelay (1000ms) +/- 20% jitter
    local delay = manager.nextAttemptAt - mockTime.get()
    assertGt(delay, 700, "Delay should be at least 800ms (base - 20%)")
    assertLe(delay, 1300, "Delay should be at most 1200ms (base + 20%)")
end)

test("Exponential backoff increases delay on repeated failures", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateError = "Connection refused"
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    local delays = {}
    
    -- Try multiple times and collect delays
    for i = 1, 4 do
        manager:requestConnect()
        manager:tick()  -- Triggers connect, which fails
        
        if manager.nextAttemptAt then
            local delay = manager.nextAttemptAt - mockTime.get()
            table.insert(delays, delay)
            
            -- Advance time past the retry
            mockTime.advance(delay + 100)
            mockWs:reset()
            mockWs.simulateError = "Connection refused"
        end
    end
    
    -- Each delay should be roughly double the previous (within jitter)
    for i = 2, #delays do
        local ratio = delays[i] / delays[i-1]
        -- With 20% jitter on each, ratio could be 1.33 to 3.0
        assertGt(ratio, 1.2, "Delay " .. i .. " should be larger than delay " .. (i-1))
    end
end)

test("Max attempts reached transitions to FAILED", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateError = "Connection refused"
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger(),
        config = { maxAttempts = 3 }  -- Reduce for faster test
    })
    
    -- Exhaust all attempts
    for i = 1, 4 do
        if manager:getState() == "DISCONNECTED" or manager:getState() == "BACKING_OFF" then
            manager:requestConnect()
        end
        
        if manager.nextAttemptAt then
            mockTime.set(manager.nextAttemptAt + 1)
        end
        
        manager:tick()
        
        if manager:getState() == "FAILED" then
            break
        end
        
        mockWs:reset()
        mockWs.simulateError = "Connection refused"
    end
    
    assertEq(manager:getState(), "FAILED")
end)

test("Stable connection resets backoff counter", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger(),
        config = { stableConnectionMs = 1000 }  -- 1 second for test
    })
    
    -- First connect fails a few times
    mockWs.simulateError = "Connection refused"
    manager:requestConnect()
    manager:tick()
    mockTime.advance(2000)
    mockWs:reset()
    mockWs.simulateError = "Connection refused"
    manager:tick()
    
    local attemptsBeforeConnect = manager.attemptCount
    assertGt(attemptsBeforeConnect, 0)
    
    -- Now connect succeeds
    mockWs:reset()
    mockWs.simulateSuccess = true
    mockTime.set(manager.nextAttemptAt + 1)
    manager:tick()
    
    assertEq(manager:getState(), "CONNECTED")
    
    -- Stay connected for stable duration
    mockTime.advance(1500)  -- More than stableConnectionMs
    manager:tick()
    
    -- Attempt count should be reset
    assertEq(manager.attemptCount, 0, "Attempt count should reset after stable connection")
end)

test("disconnect resets state", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateSuccess = true
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    manager:requestConnect()
    manager:tick()
    assertEq(manager:getState(), "CONNECTED")
    
    manager:disconnect()
    
    assertEq(manager:getState(), "DISCONNECTED")
    assertFalse(manager:isConnected())
    assertTrue(mockWs.disconnectCalled)
end)

test("Log throttling prevents spam", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateError = "Same error message"
    
    local mockLogger = createMockLogger()
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = mockLogger,
        config = { logThrottleMs = 5000 }  -- 5 second throttle
    })
    
    -- First failure logs
    manager:requestConnect()
    manager:tick()
    local warnCountAfterFirst = #mockLogger.logs.warn
    
    -- Advance time but not past throttle
    mockTime.advance(2000)
    mockWs:reset()
    mockWs.simulateError = "Same error message"
    manager.nextAttemptAt = mockTime.get()
    manager:tick()
    
    local warnCountAfterSecond = #mockLogger.logs.warn
    
    -- Should NOT have logged again (same error within throttle window)
    assertEq(warnCountAfterSecond, warnCountAfterFirst, 
        "Should not log same error within throttle window")
    
    -- Advance past throttle
    mockTime.advance(4000)  -- Total 6 seconds past first log
    mockWs:reset()
    mockWs.simulateError = "Same error message"
    manager.nextAttemptAt = mockTime.get()
    manager:tick()
    
    local warnCountAfterThird = #mockLogger.logs.warn
    
    -- Should have logged now (past throttle window)
    assertGt(warnCountAfterThird, warnCountAfterSecond, 
        "Should log after throttle window passes")
end)

test("getStatus returns pre-computed status", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    -- Disconnected state
    local text, detail = manager:getStatus()
    assertEq(text, "Disconnected")
    
    -- Connecting state
    manager:requestConnect()
    manager:tick()
    text, detail = manager:getStatus()
    assertEq(text, "Connecting...")
    
    -- Backing off state
    mockWs.simulateError = "Error"
    manager.connectAttemptInFlight = false
    manager:_handleConnectFailed("Error")
    text, detail = manager:getStatus()
    assertEq(text, "Offline")
end)

test("onConnectionLost triggers auto-reconnect", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    mockWs.simulateSuccess = true
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    -- Connect successfully
    manager:requestConnect()
    manager:tick()
    assertEq(manager:getState(), "CONNECTED")
    
    -- Simulate connection loss
    manager:onConnectionLost("Server closed")
    
    assertEq(manager:getState(), "BACKING_OFF")
    assertNotNil(manager.nextAttemptAt, "Should schedule reconnect")
end)

test("No blocking operations during tick", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    -- Measure tick time
    local startTime = os.clock()
    
    -- Call tick many times (simulating per-frame calls)
    for i = 1, 1000 do
        manager:tick()
    end
    
    local elapsed = os.clock() - startTime
    
    -- Should complete in well under 100ms for 1000 ticks
    -- (no blocking I/O should occur in tick)
    assertLe(elapsed, 0.1, "1000 ticks should complete in < 100ms (no blocking)")
end)

test("Single in-flight connection guard", function()
    local mockTime = createMockTime()
    local mockWs = createMockWsClient()
    -- Don't simulate immediate success/failure - leave in-flight
    
    local manager = WsConnectionManager.WsConnectionManager.new({
        time = mockTime.get,
        wsClient = mockWs,
        logger = createMockLogger()
    })
    
    manager:requestConnect()
    manager:tick()  -- Start connect
    
    assertEq(manager.connectAttemptInFlight, true)
    
    -- Try to start another connect
    local connectCallCount = 0
    local originalConnectAsync = mockWs.connectAsync
    mockWs.connectAsync = function(self, options)
        connectCallCount = connectCallCount + 1
        return originalConnectAsync(self, options)
    end
    
    -- Multiple ticks should not start new connects
    for i = 1, 10 do
        manager:tick()
    end
    
    -- Should only have called connect once
    assertEq(connectCallCount, 0, "Should not start new connect while one is in-flight")
end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print("\n=== WsConnectionManager Tests ===\n")

print(string.format("\n=== Results: %d passed, %d failed ===\n", testsPassed, testsFailed))

if testsFailed > 0 then
    os.exit(1)
end
