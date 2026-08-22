-- ServerProfileFetcher.lua
-- Fetches server profiles from the API at startup
--
-- This is a one-time bootstrap operation to get the list of supported servers.
-- The profiles include hostPatterns used for auto-detection.
--
-- Usage:
--   local fetcher = ServerProfileFetcher.new(httpClient, logger)
--   fetcher:fetch(function(success, profiles)
--       if success then ServerProfiles.setProfiles(profiles) end
--   end)

local Endpoints = require("protocol.Endpoints")
local ServerConfig = require("core.ServerConfig")

local M = {}
M.ServerProfileFetcher = {}
M.ServerProfileFetcher.__index = M.ServerProfileFetcher

-- State constants
M.State = {
    IDLE = "idle",
    FETCHING = "fetching",
    SUCCESS = "success",
    FAILED = "failed"
}

function M.ServerProfileFetcher.new(httpRequest, logger)
    local self = setmetatable({}, M.ServerProfileFetcher)
    
    -- httpRequest: function(options) matching libs/net.request signature
    self.httpRequest = httpRequest
    self.logger = logger or {
        debug = function() end,
        info = function() end,
        warn = function() end,
        error = function() end
    }
    
    -- State
    self.state = M.State.IDLE
    self.lastFetchTime = 0
    self.lastError = nil
    self.profiles = nil
    
    return self
end

-- Fetch server profiles from API
-- @param callback function(success, profiles, error)
function M.ServerProfileFetcher:fetch(callback)
    if self.state == M.State.FETCHING then
        self:_log("debug", "Fetch already in progress, ignoring")
        return
    end
    
    self.state = M.State.FETCHING
    self:_log("info", "Fetching server profiles from API...")
    
    local url = ServerConfig.DEFAULT_SERVER_URL .. Endpoints.SERVERS
    
    local requestOpts = {
        url = url,
        method = "GET",
        headers = {
            ["Accept"] = "application/json",
            ["Content-Type"] = "application/json"
        },
        callback = function(success, response, statusOrError)
            self:_handleResponse(success, response, statusOrError, callback)
        end
    }
    
    local ok, err = pcall(function()
        self.httpRequest(requestOpts)
    end)
    
    if not ok then
        self.state = M.State.FAILED
        self.lastError = "Request failed: " .. tostring(err)
        self:_log("error", self.lastError)
        if callback then
            callback(false, nil, self.lastError)
        end
    end
end

-- Handle API response
function M.ServerProfileFetcher:_handleResponse(success, response, statusOrError, callback)
    self.lastFetchTime = os.time()
    
    if not success then
        self.state = M.State.FAILED
        self.lastError = "HTTP request failed: " .. tostring(statusOrError)
        self:_log("warn", self.lastError)
        if callback then
            callback(false, nil, self.lastError)
        end
        return
    end
    
    -- Parse JSON response
    local decoded, parseErr = self:_parseJson(response)
    if not decoded then
        self.state = M.State.FAILED
        self.lastError = "JSON parse error: " .. tostring(parseErr)
        self:_log("warn", self.lastError)
        if callback then
            callback(false, nil, self.lastError)
        end
        return
    end
    
    -- Extract servers array from response envelope
    -- Expected: { success: true, data: { servers: [...] } }
    local servers = nil
    if decoded.data and decoded.data.servers then
        servers = decoded.data.servers
    elseif decoded.servers then
        -- Direct response (legacy format)
        servers = decoded.servers
    end
    
    if not servers or type(servers) ~= "table" or #servers == 0 then
        self.state = M.State.FAILED
        self.lastError = "No servers in response"
        self:_log("warn", self.lastError)
        if callback then
            callback(false, nil, self.lastError)
        end
        return
    end
    
    -- Validate and normalize profiles
    local profiles = {}
    for _, server in ipairs(servers) do
        if server.id and server.name then
            table.insert(profiles, {
                id = server.id,
                name = server.name,
                hostPatterns = server.hostPatterns or {},
                region = server.region,
                status = server.status
            })
        end
    end
    
    if #profiles == 0 then
        self.state = M.State.FAILED
        self.lastError = "No valid server profiles in response"
        self:_log("warn", self.lastError)
        if callback then
            callback(false, nil, self.lastError)
        end
        return
    end
    
    self.state = M.State.SUCCESS
    self.profiles = profiles
    self.lastError = nil
    self:_log("info", "Fetched " .. #profiles .. " server profiles from API")
    
    if callback then
        callback(true, profiles, nil)
    end
end

-- Parse JSON string
function M.ServerProfileFetcher:_parseJson(jsonStr)
    if not jsonStr or jsonStr == "" then
        return nil, "Empty response"
    end
    
    -- Try to load cjson or fallback to simple parsing
    local ok, cjson = pcall(require, "cjson")
    if ok and cjson then
        local decodeOk, result = pcall(cjson.decode, jsonStr)
        if decodeOk then
            return result, nil
        else
            return nil, tostring(result)
        end
    end
    
    -- Try protocol Json module
    -- Note: Json.decode returns (success, result) tuple
    local jsonOk, Json = pcall(require, "protocol.Json")
    if jsonOk and Json and Json.decode then
        local success, result = Json.decode(jsonStr)
        if success then
            return result, nil
        else
            return nil, tostring(result)
        end
    end
    
    return nil, "No JSON parser available"
end

-- Get diagnostics info
function M.ServerProfileFetcher:getDiagnostics()
    return {
        state = self.state,
        lastFetchTime = self.lastFetchTime,
        lastError = self.lastError,
        profileCount = self.profiles and #self.profiles or 0
    }
end

-- Logging helper
function M.ServerProfileFetcher:_log(level, message)
    if self.logger and self.logger[level] then
        self.logger[level](self.logger, "[ServerProfileFetcher] " .. message)
    end
end

return M
