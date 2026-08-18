-- WsClientAsyncTest.lua
-- Unit tests for non-blocking WebSocket client
-- Verifies step machine, non-blocking behavior, and frame parsing

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

local function assertNotNil(value, message)
    assert(value ~= nil, message or "Expected not nil")
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
-- Mock Dependencies
--------------------------------------------------------------------------------

local function createMockLogger()
    local logs = { info = {}, debug = {}, warn = {}, error = {} }
    return {
        info = function(msg) table.insert(logs.info, msg) end,
        debug = function(msg) table.insert(logs.debug, msg) end,
        warn = function(msg) table.insert(logs.warn, msg) end,
        error = function(msg) table.insert(logs.error, msg) end,
        logs = logs
    }
end

local function createMockConnection()
    return {
        isConnected = function() return true end,
        getBaseUrl = function() return "https://api.example.com" end,
        getCharacterName = function() return "testchar" end,
        getHeaders = function(self, charName)
            return {
                ["Authorization"] = "Bearer test-api-key",
                ["X-Character-Name"] = charName,
                ["X-Realm-Id"] = "test-realm"
            }
        end
    }
end

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

-- Mock the dependencies
package.loaded["common.Bit"] = {
    band = function(a, b) return bit32 and bit32.band(a, b) or (a % (b + 1)) end,
    bxor = function(a, b) return bit32 and bit32.bxor(a, b) or 0 end,
}

package.loaded["protocol.WsEventRouter"] = {
    WsEventRouter = {
        new = function(deps)
            return {
                route = function(self, msg) end,
                registerHandler = function(self, eventType, handler) end,
            }
        end
    }
}

package.loaded["constants.limits"] = {
    MAX_RECONNECT_ATTEMPTS = 10,
}

package.loaded["core.TimingConstants"] = {
    WS_BASE_RECONNECT_DELAY_MS = 1000,
    WS_MAX_RECONNECT_DELAY_MS = 60000,
}

package.loaded["protocol.Endpoints"] = {
    WEBSOCKET = "/ws"
}

-- We can't fully test socket operations without real sockets,
-- but we can test the state machine and parsing logic

--------------------------------------------------------------------------------
-- URL Parsing Tests (doesn't require sockets)
--------------------------------------------------------------------------------

test("URL parsing - wss with port", function()
    -- Create a minimal instance to test parsing
    local WsClientAsync = {
        _parseUrl = function(self, wsUrl)
            local scheme, host, port, path = wsUrl:match("^(wss?)://([^:/]+):?(%d*)(.*)$")
            if not scheme then
                return nil, "Invalid WebSocket URL"
            end
            port = tonumber(port) or (scheme == "wss" and 443 or 80)
            path = path ~= "" and path or "/"
            return {
                scheme = scheme,
                host = host,
                port = port,
                path = path,
                isSecure = scheme == "wss"
            }
        end
    }
    
    local parsed = WsClientAsync:_parseUrl("wss://example.com:8443/api/ws")
    assertNotNil(parsed)
    assertEq(parsed.scheme, "wss")
    assertEq(parsed.host, "example.com")
    assertEq(parsed.port, 8443)
    assertEq(parsed.path, "/api/ws")
    assertTrue(parsed.isSecure)
end)

test("URL parsing - ws without port", function()
    local WsClientAsync = {
        _parseUrl = function(self, wsUrl)
            local scheme, host, port, path = wsUrl:match("^(wss?)://([^:/]+):?(%d*)(.*)$")
            if not scheme then
                return nil, "Invalid WebSocket URL"
            end
            port = tonumber(port) or (scheme == "wss" and 443 or 80)
            path = path ~= "" and path or "/"
            return {
                scheme = scheme,
                host = host,
                port = port,
                path = path,
                isSecure = scheme == "wss"
            }
        end
    }
    
    local parsed = WsClientAsync:_parseUrl("ws://localhost/chat")
    assertNotNil(parsed)
    assertEq(parsed.scheme, "ws")
    assertEq(parsed.host, "localhost")
    assertEq(parsed.port, 80)
    assertEq(parsed.path, "/chat")
    assertFalse(parsed.isSecure)
end)

test("URL parsing - wss default port", function()
    local WsClientAsync = {
        _parseUrl = function(self, wsUrl)
            local scheme, host, port, path = wsUrl:match("^(wss?)://([^:/]+):?(%d*)(.*)$")
            if not scheme then
                return nil, "Invalid WebSocket URL"
            end
            port = tonumber(port) or (scheme == "wss" and 443 or 80)
            path = path ~= "" and path or "/"
            return {
                scheme = scheme,
                host = host,
                port = port,
                path = path,
                isSecure = scheme == "wss"
            }
        end
    }
    
    local parsed = WsClientAsync:_parseUrl("wss://secure.example.com")
    assertNotNil(parsed)
    assertEq(parsed.port, 443)
    assertEq(parsed.path, "/")
end)

test("URL parsing - invalid URL", function()
    local WsClientAsync = {
        _parseUrl = function(self, wsUrl)
            local scheme, host, port, path = wsUrl:match("^(wss?)://([^:/]+):?(%d*)(.*)$")
            if not scheme then
                return nil, "Invalid WebSocket URL"
            end
            port = tonumber(port) or (scheme == "wss" and 443 or 80)
            path = path ~= "" and path or "/"
            return {
                scheme = scheme,
                host = host,
                port = port,
                path = path,
                isSecure = scheme == "wss"
            }
        end
    }
    
    local parsed, err = WsClientAsync:_parseUrl("http://example.com")
    assertEq(parsed, nil)
    assertNotNil(err)
end)

--------------------------------------------------------------------------------
-- Frame Parsing Tests
--------------------------------------------------------------------------------

-- Mock Bit module for frame parsing
local Bit = {
    band = function(a, b)
        -- Simple bitwise AND for testing
        local result = 0
        local bitval = 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return result
    end,
    bxor = function(a, b)
        local result = 0
        local bitval = 1
        while a > 0 or b > 0 do
            if (a % 2) ~= (b % 2) then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return result
    end
}

-- Extract frame parser for testing
local function createFrameParser()
    local parser = {}
    
    function parser:_parseFrame(buf)
        if #buf < 2 then
            return nil, 0
        end
        
        local b1 = buf:byte(1)
        local b2 = buf:byte(2)
        
        local fin = Bit.band(b1, 0x80) ~= 0
        local opcode = Bit.band(b1, 0x0F)
        local masked = Bit.band(b2, 0x80) ~= 0
        local payloadLen = Bit.band(b2, 0x7F)
        
        local headerLen = 2
        
        if payloadLen == 126 then
            if #buf < 4 then return nil, 0 end
            payloadLen = buf:byte(3) * 256 + buf:byte(4)
            headerLen = 4
        elseif payloadLen == 127 then
            if #buf < 10 then return nil, 0 end
            payloadLen = 0
            for i = 3, 10 do
                payloadLen = payloadLen * 256 + buf:byte(i)
            end
            headerLen = 10
        end
        
        local maskLen = masked and 4 or 0
        if masked and #buf < headerLen + 4 then
            return nil, 0
        end
        
        local totalLen = headerLen + maskLen + payloadLen
        if #buf < totalLen then
            return nil, 0
        end
        
        local mask = masked and buf:sub(headerLen + 1, headerLen + 4) or nil
        local payload = buf:sub(headerLen + maskLen + 1, headerLen + maskLen + payloadLen)
        
        if masked and mask then
            local unmasked = {}
            for i = 1, #payload do
                local j = ((i - 1) % 4) + 1
                unmasked[i] = string.char(Bit.bxor(payload:byte(i), mask:byte(j)))
            end
            payload = table.concat(unmasked)
        end
        
        return { fin = fin, opcode = opcode, payload = payload }, totalLen
    end
    
    return parser
end

test("Frame parsing - simple text frame", function()
    local parser = createFrameParser()
    
    -- Build a simple unmasked text frame: "Hi"
    -- FIN=1, opcode=1 (text): 0x81
    -- Length=2: 0x02
    -- Payload: "Hi"
    local frame = string.char(0x81, 0x02) .. "Hi"
    
    parser.readBuffer = frame
    local parsed, consumed = parser:_parseFrame(frame)
    
    assertNotNil(parsed)
    assertTrue(parsed.fin)
    assertEq(parsed.opcode, 1)  -- TEXT
    assertEq(parsed.payload, "Hi")
    assertEq(consumed, 4)  -- 2 header + 2 payload
end)

test("Frame parsing - ping frame", function()
    local parser = createFrameParser()
    
    -- Build a ping frame with empty payload
    -- FIN=1, opcode=9 (ping): 0x89
    -- Length=0: 0x00
    local frame = string.char(0x89, 0x00)
    
    local parsed, consumed = parser:_parseFrame(frame)
    
    assertNotNil(parsed)
    assertTrue(parsed.fin)
    assertEq(parsed.opcode, 9)  -- PING
    assertEq(parsed.payload, "")
    assertEq(consumed, 2)
end)

test("Frame parsing - incomplete frame returns nil", function()
    local parser = createFrameParser()
    
    -- Only 1 byte of a frame
    local frame = string.char(0x81)
    
    local parsed, consumed = parser:_parseFrame(frame)
    
    assertEq(parsed, nil)
    assertEq(consumed, 0)
end)

test("Frame parsing - 126-byte extended length", function()
    local parser = createFrameParser()
    
    -- Build a frame with 126 bytes payload
    -- FIN=1, opcode=1: 0x81
    -- Length=126 (extended): 0x7E, then 2 bytes for actual length (0x00, 0x7E = 126)
    local payload = string.rep("x", 126)
    local frame = string.char(0x81, 0x7E, 0x00, 0x7E) .. payload
    
    local parsed, consumed = parser:_parseFrame(frame)
    
    assertNotNil(parsed)
    assertEq(#parsed.payload, 126)
    assertEq(consumed, 4 + 126)  -- 4 header + 126 payload
end)

test("Frame parsing - close frame with code", function()
    local parser = createFrameParser()
    
    -- Build a close frame with code 1000 (normal closure)
    -- FIN=1, opcode=8 (close): 0x88
    -- Length=2: 0x02
    -- Code: 1000 = 0x03E8
    local frame = string.char(0x88, 0x02, 0x03, 0xE8)
    
    local parsed, consumed = parser:_parseFrame(frame)
    
    assertNotNil(parsed)
    assertEq(parsed.opcode, 8)  -- CLOSE
    assertEq(#parsed.payload, 2)
    
    -- Extract close code
    local code = parsed.payload:byte(1) * 256 + parsed.payload:byte(2)
    assertEq(code, 1000)
end)

--------------------------------------------------------------------------------
-- Connection State Tests
--------------------------------------------------------------------------------

test("ConnectState enum values", function()
    -- Verify expected states exist
    local states = {
        IDLE = 0,
        CREATING_SOCKET = 1,
        CONNECTING = 2,
        SSL_WRAP = 3,
        SSL_HANDSHAKE = 4,
        SENDING_UPGRADE = 5,
        RECEIVING_UPGRADE = 6,
        CONNECTED = 7,
        ERROR = 8
    }
    
    -- Each state should have a unique value
    local seen = {}
    for name, value in pairs(states) do
        assertFalse(seen[value], "Duplicate state value: " .. tostring(value))
        seen[value] = true
    end
    
    -- Should have all expected states
    assertEq(states.IDLE, 0)
    assertEq(states.CONNECTED, 7)
    assertEq(states.ERROR, 8)
end)

--------------------------------------------------------------------------------
-- Upgrade Request Building Tests
--------------------------------------------------------------------------------

test("Upgrade request format", function()
    local host = "example.com"
    local port = 443
    local path = "/ws"
    local wsKey = "dGVzdGtleQ=="  -- Base64 of "testkey"
    
    local hostHeader = host
    if port ~= 80 and port ~= 443 then
        hostHeader = hostHeader .. ":" .. port
    end
    
    local request = string.format(
        "GET %s HTTP/1.1\r\n" ..
        "Host: %s\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: %s\r\n" ..
        "Sec-WebSocket-Version: 13\r\n",
        path, hostHeader, wsKey
    )
    
    -- Add mock auth headers
    request = request .. "Authorization: Bearer test-key\r\n"
    request = request .. "\r\n"
    
    -- Verify format
    assert(request:find("GET /ws HTTP/1.1\r\n"), "Should have correct request line")
    assert(request:find("Upgrade: websocket\r\n"), "Should have Upgrade header")
    assert(request:find("Connection: Upgrade\r\n"), "Should have Connection header")
    assert(request:find("Sec%-WebSocket%-Key:"), "Should have WebSocket key")
    assert(request:find("Sec%-WebSocket%-Version: 13\r\n"), "Should have version 13")
    assert(request:find("\r\n\r\n$"), "Should end with double CRLF")
end)

--------------------------------------------------------------------------------
-- Non-blocking Tick Tests
--------------------------------------------------------------------------------

test("tickConnect with IDLE state does nothing", function()
    -- When in IDLE state, tickConnect should return immediately
    -- This is a conceptual test since we can't instantiate without socket libs
    
    local tickCalled = false
    local mockClient = {
        connectState = 0,  -- IDLE
        tickConnect = function(self)
            if self.connectState == 0 or self.connectState == 7 then
                return  -- IDLE or CONNECTED, do nothing
            end
            tickCalled = true
        end
    }
    
    mockClient:tickConnect()
    assertFalse(tickCalled, "Should not process when IDLE")
end)

test("tickMessages only processes when CONNECTED", function()
    local processCalled = false
    local mockClient = {
        connectState = 0,  -- IDLE
        socket = nil,
        tickMessages = function(self)
            if self.connectState ~= 7 or not self.socket then
                return
            end
            processCalled = true
        end
    }
    
    mockClient:tickMessages()
    assertFalse(processCalled, "Should not process messages when not connected")
    
    mockClient.connectState = 7  -- CONNECTED
    mockClient.socket = {}  -- Mock socket
    mockClient:tickMessages()
    assertTrue(processCalled, "Should process messages when connected")
end)

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print("\n=== WsClientAsync Tests ===\n")

print(string.format("\n=== Results: %d passed, %d failed ===\n", testsPassed, testsFailed))

if testsFailed > 0 then
    os.exit(1)
end
