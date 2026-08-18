-- WsClientAsync.lua
-- Non-blocking WebSocket client for server-to-client push events
-- CRITICAL: NO blocking socket operations - all work spread across frames
-- Uses step-machine pattern similar to nonBlockingRequests library

local Bit = require("common.Bit")
local WsEventRouter = require("protocol.WsEventRouter")
local Limits = require("constants.limits")
local TimingConstants = require("core.TimingConstants")

local M = {}

--------------------------------------------------------------------------------
-- Connection States (step machine)
--------------------------------------------------------------------------------
M.ConnectState = {
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

-- WebSocket opcodes (RFC 6455 Section 5.2)
local OPCODE = {
    CONTINUATION = 0x0,
    TEXT = 0x1,
    BINARY = 0x2,
    CLOSE = 0x8,
    PING = 0x9,
    PONG = 0xA
}

--------------------------------------------------------------------------------
-- WsClientAsync
--------------------------------------------------------------------------------
M.WsClientAsync = {}
M.WsClientAsync.__index = M.WsClientAsync

function M.WsClientAsync.new(deps)
    local self = setmetatable({}, M.WsClientAsync)
    
    deps = deps or {}
    self.deps = deps
    self.logger = deps.logger
    self.connection = deps.connection
    self.time = deps.time or function() return os.clock() * 1000 end
    
    -- Socket libraries (lazy loaded)
    self.socketLib = nil
    self.sslLib = nil
    self.mimeLib = nil
    self.wsAvailable = false
    
    -- Connection state
    self.connectState = M.ConnectState.IDLE
    self.socket = nil
    self.url = nil
    self.host = nil
    self.port = nil
    self.path = nil
    self.isSecure = false
    
    -- Async connect tracking
    self.connectStartTime = nil
    self.connectTimeoutMs = 5000
    self.handshakeTimeoutMs = 5000
    self.onConnectSuccess = nil
    self.onConnectFailure = nil
    self.wsKey = nil
    self.upgradeBuffer = ""
    
    -- Message buffer
    self.readBuffer = ""
    
    -- Event router
    self.eventRouter = WsEventRouter.WsEventRouter.new({ logger = self.logger })
    
    -- Callbacks
    self.onOpen = nil
    self.onMessage = nil
    self.onClose = nil
    self.onError = nil
    
    -- Track snapshot receipt
    self.receivedSnapshot = false
    
    -- Check capability on creation
    self:_checkCapability()
    
    return self
end

--------------------------------------------------------------------------------
-- Capability Check
--------------------------------------------------------------------------------
function M.WsClientAsync:_checkCapability()
    -- LuaSocket
    local hasSocket, socketLib = pcall(require, "socket")
    if not hasSocket then
        self:_log("warn", "[WsClientAsync] LuaSocket not available")
        return
    end
    self.socketLib = socketLib
    
    -- LuaSec
    local hasSsl, sslLib = pcall(require, "socket.ssl")
    if not hasSsl then
        self:_log("warn", "[WsClientAsync] LuaSec not available")
        return
    end
    self.sslLib = sslLib
    
    -- mime for base64
    local hasMime, mimeLib = pcall(require, "mime")
    if not hasMime then
        self:_log("warn", "[WsClientAsync] mime not available")
        return
    end
    self.mimeLib = mimeLib
    
    self.wsAvailable = true
    self:_log("debug", "[WsClientAsync] WebSocket capability available")
end

function M.WsClientAsync:isAvailable()
    return self.wsAvailable
end

--------------------------------------------------------------------------------
-- Async Connect API
--------------------------------------------------------------------------------

-- Start async connection (non-blocking)
-- options: { connectTimeoutMs, handshakeTimeoutMs, onSuccess, onFailure }
function M.WsClientAsync:connectAsync(options)
    options = options or {}
    
    if not self.wsAvailable then
        local err = "WebSocket libraries not available"
        if options.onFailure then
            options.onFailure(err)
        end
        return false, err
    end
    
    if not self.connection or not self.connection:isConnected() then
        local err = "HTTP connection not established"
        if options.onFailure then
            options.onFailure(err)
        end
        return false, err
    end
    
    if self.connectState ~= M.ConnectState.IDLE and 
       self.connectState ~= M.ConnectState.ERROR then
        local err = "Connect already in progress"
        if options.onFailure then
            options.onFailure(err)
        end
        return false, err
    end
    
    -- Build WebSocket URL
    local baseUrl = self.connection:getBaseUrl()
    local wsUrl = baseUrl:gsub("^https://", "wss://"):gsub("^http://", "ws://")
    local Endpoints = require("protocol.Endpoints")
    self.url = wsUrl .. Endpoints.WEBSOCKET
    
    -- Parse URL
    local parsed, parseErr = self:_parseUrl(self.url)
    if not parsed then
        local err = "Invalid URL: " .. tostring(parseErr)
        if options.onFailure then
            options.onFailure(err)
        end
        return false, err
    end
    
    self.host = parsed.host
    self.port = parsed.port
    self.path = parsed.path
    self.isSecure = parsed.isSecure
    
    -- Store callbacks
    self.onConnectSuccess = options.onSuccess
    self.onConnectFailure = options.onFailure
    self.connectTimeoutMs = options.connectTimeoutMs or 5000
    self.handshakeTimeoutMs = options.handshakeTimeoutMs or 5000
    self.connectStartTime = self.time()
    
    -- Reset state
    self.upgradeBuffer = ""
    self.readBuffer = ""
    self.receivedSnapshot = false
    self.wsKey = nil
    
    -- Start step machine
    self.connectState = M.ConnectState.CREATING_SOCKET
    
    self:_log("info", "[WsClientAsync] Starting async connect to " .. self.host)
    return true
end

-- Disconnect (immediate)
function M.WsClientAsync:disconnect()
    if self.socket then
        pcall(function()
            self:_sendFrame(OPCODE.CLOSE, "")
        end)
        pcall(function()
            self.socket:close()
        end)
        self.socket = nil
    end
    
    self.connectState = M.ConnectState.IDLE
    self.upgradeBuffer = ""
    self.readBuffer = ""
    self.wsKey = nil
    
    if self.onClose then
        self.onClose("Disconnected")
    end
end

-- Check if connected
function M.WsClientAsync:isConnected()
    return self.connectState == M.ConnectState.CONNECTED
end

--------------------------------------------------------------------------------
-- Tick - MUST be called each frame (non-blocking)
--------------------------------------------------------------------------------

-- Tick connect steps (for connection manager)
function M.WsClientAsync:tickConnect()
    local state = self.connectState
    
    if state == M.ConnectState.IDLE or state == M.ConnectState.CONNECTED then
        return
    end
    
    -- Check overall timeout
    if self:_isTimedOut() then
        self:_failConnect("Connection timeout")
        return
    end
    
    -- Step through connection states
    if state == M.ConnectState.CREATING_SOCKET then
        self:_stepCreateSocket()
    elseif state == M.ConnectState.CONNECTING then
        self:_stepConnect()
    elseif state == M.ConnectState.SSL_WRAP then
        self:_stepSslWrap()
    elseif state == M.ConnectState.SSL_HANDSHAKE then
        self:_stepSslHandshake()
    elseif state == M.ConnectState.SENDING_UPGRADE then
        self:_stepSendUpgrade()
    elseif state == M.ConnectState.RECEIVING_UPGRADE then
        self:_stepReceiveUpgrade()
    end
end

-- Tick messages only (for when connected)
function M.WsClientAsync:tickMessages()
    if self.connectState ~= M.ConnectState.CONNECTED or not self.socket then
        return
    end
    
    self:_processMessages()
end

--------------------------------------------------------------------------------
-- Connection Step Machine
--------------------------------------------------------------------------------

function M.WsClientAsync:_stepCreateSocket()
    local sock, err = self.socketLib.tcp()
    if not sock then
        self:_failConnect("Failed to create socket: " .. tostring(err))
        return
    end
    
    -- Set non-blocking immediately
    sock:settimeout(0)
    
    self.socket = sock
    self.connectState = M.ConnectState.CONNECTING
    
    self:_log("debug", "[WsClientAsync] Socket created, starting connect")
end

function M.WsClientAsync:_stepConnect()
    local result, err = self.socket:connect(self.host, self.port)
    
    if result then
        -- Connected immediately (rare)
        self:_advanceToNextState()
    elseif err == "timeout" or err == "Operation already in progress" or 
           err == "already connected" then
        -- In progress, check if writable
        local _, writable = self.socketLib.select(nil, {self.socket}, 0)
        if writable and #writable > 0 then
            -- Connection complete
            self:_advanceToNextState()
        end
        -- else: still connecting, wait for next tick
    elseif err == "connection refused" or err == "No connection" or
           err:find("refused") or err:find("unreachable") then
        self:_failConnect("Connection refused: " .. tostring(err))
    else
        -- Some other error, might still be in progress
        -- On Windows, "timeout" means still connecting
        self:_log("debug", "[WsClientAsync] Connect returned: " .. tostring(err))
    end
end

function M.WsClientAsync:_advanceToNextState()
    if self.isSecure then
        self.connectState = M.ConnectState.SSL_WRAP
    else
        self.connectState = M.ConnectState.SENDING_UPGRADE
    end
end

function M.WsClientAsync:_stepSslWrap()
    local sslParams = {
        mode = "client",
        protocol = "any",
        options = {"all", "no_sslv2", "no_sslv3"},
        verify = "none"
    }
    
    local sslSock, err = self.sslLib.wrap(self.socket, sslParams)
    if not sslSock then
        self:_failConnect("SSL wrap failed: " .. tostring(err))
        return
    end
    
    -- Set SNI
    pcall(function() sslSock:sni(self.host) end)
    
    -- Non-blocking
    sslSock:settimeout(0)
    
    self.socket = sslSock
    self.connectState = M.ConnectState.SSL_HANDSHAKE
    
    self:_log("debug", "[WsClientAsync] SSL wrapped, starting handshake")
end

function M.WsClientAsync:_stepSslHandshake()
    local success, err = self.socket:dohandshake()
    
    if success then
        self.connectState = M.ConnectState.SENDING_UPGRADE
        self:_log("debug", "[WsClientAsync] SSL handshake complete")
    elseif err == "wantread" or err == "wantwrite" or err == "timeout" then
        -- In progress, wait for next tick
    else
        self:_failConnect("SSL handshake failed: " .. tostring(err))
    end
end

function M.WsClientAsync:_stepSendUpgrade()
    -- Generate WebSocket key if not yet done
    if not self.wsKey then
        self.wsKey = self:_generateKey()
        self.upgradeRequest = self:_buildUpgradeRequest()
        self.upgradeSentBytes = 0
    end
    
    -- Send request (may take multiple ticks)
    local remaining = self.upgradeRequest:sub(self.upgradeSentBytes + 1)
    local sent, err, lastSent = self.socket:send(remaining)
    
    local bytesSent = sent or lastSent or 0
    self.upgradeSentBytes = self.upgradeSentBytes + bytesSent
    
    if self.upgradeSentBytes >= #self.upgradeRequest then
        self.connectState = M.ConnectState.RECEIVING_UPGRADE
        self:_log("debug", "[WsClientAsync] Upgrade request sent")
    elseif err and err ~= "timeout" and err ~= "wantwrite" then
        self:_failConnect("Failed to send upgrade: " .. tostring(err))
    end
end

function M.WsClientAsync:_stepReceiveUpgrade()
    -- Read available data (non-blocking)
    local data, err, partial = self.socket:receive(4096)
    local chunk = data or partial
    
    if chunk and #chunk > 0 then
        self.upgradeBuffer = self.upgradeBuffer .. chunk
    end
    
    -- Check for complete response (ends with \r\n\r\n)
    local headerEnd = self.upgradeBuffer:find("\r\n\r\n")
    if headerEnd then
        local headers = self.upgradeBuffer:sub(1, headerEnd - 1)
        
        -- Parse response
        local statusLine = headers:match("^([^\r\n]+)")
        if not statusLine or not statusLine:match("^HTTP/1.1 101") then
            self:_failConnect("Upgrade failed: " .. tostring(statusLine))
            return
        end
        
        -- Verify upgrade headers
        local sawUpgrade = headers:lower():find("upgrade: websocket")
        local sawConnection = headers:lower():find("connection:") and 
                              headers:lower():find("upgrade")
        
        if not sawUpgrade or not sawConnection then
            self:_failConnect("Missing upgrade headers")
            return
        end
        
        -- Success!
        self.connectState = M.ConnectState.CONNECTED
        self.readBuffer = self.upgradeBuffer:sub(headerEnd + 4)  -- Keep any extra data
        self.upgradeBuffer = ""
        
        self:_log("info", "[WsClientAsync] WebSocket connected")
        
        if self.onConnectSuccess then
            self.onConnectSuccess()
        end
        if self.onOpen then
            self.onOpen()
        end
        
    elseif err and err ~= "timeout" and err ~= "wantread" then
        self:_failConnect("Receive error: " .. tostring(err))
    end
end

function M.WsClientAsync:_isTimedOut()
    if not self.connectStartTime then
        return false
    end
    
    local elapsed = self.time() - self.connectStartTime
    local timeout = self.connectTimeoutMs + self.handshakeTimeoutMs
    return elapsed > timeout
end

function M.WsClientAsync:_failConnect(reason)
    self:_log("warn", "[WsClientAsync] Connect failed: " .. tostring(reason))
    
    if self.socket then
        pcall(function() self.socket:close() end)
        self.socket = nil
    end
    
    self.connectState = M.ConnectState.ERROR
    
    if self.onConnectFailure then
        self.onConnectFailure(reason)
    end
    if self.onError then
        self.onError(reason)
    end
    
    -- Reset for next attempt
    self.connectState = M.ConnectState.IDLE
end

--------------------------------------------------------------------------------
-- Message Processing (non-blocking)
--------------------------------------------------------------------------------

function M.WsClientAsync:_processMessages()
    if not self.socket then return end
    
    -- Read available data (non-blocking, timeout=0)
    local data, err, partial = self.socket:receive(4096)
    local chunk = data or partial
    
    if chunk and #chunk > 0 then
        self.readBuffer = self.readBuffer .. chunk
    end
    
    -- Handle errors
    if err and err ~= "timeout" and err ~= "wantread" then
        self:_log("warn", "[WsClientAsync] Receive error: " .. tostring(err))
        self:_handleDisconnect()
        return
    end
    
    -- Process complete frames
    local framesProcessed = 0
    local maxFramesPerTick = 10  -- Limit work per frame
    
    while #self.readBuffer >= 2 and framesProcessed < maxFramesPerTick do
        local frame, consumed, frameErr = self:_parseFrame()
        
        if frameErr then
            self:_log("warn", "[WsClientAsync] Frame error: " .. tostring(frameErr))
            self:_handleDisconnect()
            return
        end
        
        if not frame then
            break  -- Need more data
        end
        
        self.readBuffer = self.readBuffer:sub(consumed + 1)
        self:_handleFrame(frame)
        framesProcessed = framesProcessed + 1
    end
end

function M.WsClientAsync:_parseFrame()
    local buf = self.readBuffer
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

function M.WsClientAsync:_handleFrame(frame)
    if frame.opcode == OPCODE.TEXT then
        if self.eventRouter then
            self.eventRouter:route(frame.payload)
        end
        
        if frame.payload:find('"type":"friends_snapshot"') then
            self.receivedSnapshot = true
        end
        
        if self.onMessage then
            self.onMessage(frame.payload)
        end
        
    elseif frame.opcode == OPCODE.PING then
        self:_sendFrame(OPCODE.PONG, frame.payload)
        
    elseif frame.opcode == OPCODE.PONG then
        -- Heartbeat response, ignore
        
    elseif frame.opcode == OPCODE.CLOSE then
        local code = 0
        if #frame.payload >= 2 then
            code = frame.payload:byte(1) * 256 + frame.payload:byte(2)
        end
        self:_log("info", "[WsClientAsync] Server closed connection: " .. code)
        self:_handleDisconnect()
    end
end

function M.WsClientAsync:_sendFrame(opcode, payload)
    if not self.socket then return false end
    
    payload = payload or ""
    local len = #payload
    
    -- Client frames MUST be masked
    local mask = string.char(
        math.random(0, 255), math.random(0, 255),
        math.random(0, 255), math.random(0, 255)
    )
    
    local header = string.char(0x80 + opcode)
    
    if len <= 125 then
        header = header .. string.char(0x80 + len)
    elseif len <= 65535 then
        header = header .. string.char(0x80 + 126)
        header = header .. string.char(math.floor(len / 256), len % 256)
    else
        header = header .. string.char(0x80 + 127)
        for i = 7, 0, -1 do
            header = header .. string.char(math.floor(len / (256^i)) % 256)
        end
    end
    
    local masked = {}
    for i = 1, len do
        local j = ((i - 1) % 4) + 1
        masked[i] = string.char(Bit.bxor(payload:byte(i), mask:byte(j)))
    end
    
    local frame = header .. mask .. table.concat(masked)
    
    local sent, err = self.socket:send(frame)
    if not sent and err ~= "timeout" then
        self:_log("warn", "[WsClientAsync] Send failed: " .. tostring(err))
        return false
    end
    
    return true
end

function M.WsClientAsync:_handleDisconnect()
    if self.socket then
        pcall(function() self.socket:close() end)
        self.socket = nil
    end
    
    local wasConnected = self.connectState == M.ConnectState.CONNECTED
    self.connectState = M.ConnectState.IDLE
    self.readBuffer = ""
    
    if wasConnected and self.onClose then
        self.onClose("Connection lost")
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function M.WsClientAsync:_parseUrl(wsUrl)
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

function M.WsClientAsync:_generateKey()
    local bytes = {}
    for _ = 1, 16 do
        bytes[#bytes + 1] = string.char(math.random(0, 255))
    end
    return self.mimeLib.b64(table.concat(bytes))
end

function M.WsClientAsync:_buildUpgradeRequest()
    local hostHeader = self.host
    if self.port ~= 80 and self.port ~= 443 then
        hostHeader = hostHeader .. ":" .. self.port
    end
    
    local request = string.format(
        "GET %s HTTP/1.1\r\n" ..
        "Host: %s\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: %s\r\n" ..
        "Sec-WebSocket-Version: 13\r\n",
        self.path, hostHeader, self.wsKey
    )
    
    -- Add auth headers
    if self.connection then
        local characterName = ""
        if self.connection.getCharacterName then
            characterName = self.connection:getCharacterName()
        end
        local headers = self.connection:getHeaders(characterName)
        
        if headers["Authorization"] then
            request = request .. "Authorization: " .. headers["Authorization"] .. "\r\n"
        end
        if headers["X-Character-Name"] then
            request = request .. "X-Character-Name: " .. headers["X-Character-Name"] .. "\r\n"
        end
        if headers["X-Realm-Id"] then
            request = request .. "X-Realm-Id: " .. headers["X-Realm-Id"] .. "\r\n"
        end
        if headers["User-Agent"] then
            request = request .. "User-Agent: " .. headers["User-Agent"] .. "\r\n"
        end
    end
    
    request = request .. "\r\n"
    return request
end

function M.WsClientAsync:_log(level, message)
    if not self.logger or not self.logger[level] then
        return
    end
    self.logger[level](message)
end

--------------------------------------------------------------------------------
-- Event Router Access
--------------------------------------------------------------------------------

function M.WsClientAsync:hasReceivedSnapshot()
    return self.receivedSnapshot
end

function M.WsClientAsync:setOnMessage(handler)
    self.onMessage = handler
end

function M.WsClientAsync:setOnOpen(handler)
    self.onOpen = handler
end

function M.WsClientAsync:setOnClose(handler)
    self.onClose = handler
end

function M.WsClientAsync:setOnError(handler)
    self.onError = handler
end

return M
