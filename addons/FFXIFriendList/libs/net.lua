local http = nil
local httpLoadError = nil
local NetworkConstants = require("core.NetworkConstants")
local TimingConstants = require("core.TimingConstants")

http = require("libs.nonBlockingRequests.nonBlockingRequests")

local M = {}

local requestQueue = {}
local nextRequestId = 1
local maxInFlight = NetworkConstants.MAX_IN_FLIGHT_REQUESTS

local requestIdMap = {}

local function getInFlightCount()
    if not http then
        return 0
    end
    return http.getActiveCount()
end

function M.request(options)
    if not http then
        if options and options.callback then
            options.callback(false, "", "HTTP library not loaded: " .. (httpLoadError or "SSL library failed"))
        end
        return nil
    end
    
    if not options or not options.url then
        return nil
    end
    
    if getInFlightCount() >= maxInFlight then
        local oldestId = nil
        local oldestTime = math.huge
        for id, req in pairs(requestQueue) do
            if req.status == 'pending' and req.timestamp < oldestTime then
                oldestTime = req.timestamp
                oldestId = id
            end
        end
        if oldestId then
            if requestIdMap[oldestId] and http.cancel then
                http.cancel(requestIdMap[oldestId])
            end
            requestQueue[oldestId] = nil
            requestIdMap[oldestId] = nil
        end
    end
    
    local requestId = nextRequestId
    nextRequestId = nextRequestId + 1
    
    local timeMs = 0
    if _G.FFXIFriendListApp and _G.FFXIFriendListApp.deps and _G.FFXIFriendListApp.deps.time then
        timeMs = _G.FFXIFriendListApp.deps.time()
    else
        timeMs = os.time() * 1000
    end
    
    local method = options.method
    if not method or method == "" then
        method = "POST"
    end
    
    local req = {
        id = requestId,
        url = options.url,
        method = method,
        headers = options.headers or {},
        body = options.body or "",
        callback = options.callback,
        status = 'pending',
        timestamp = os.clock(),
        enqueueTimeMs = timeMs,
        sendTimeMs = nil,
        completeTimeMs = nil
    }
    
    requestQueue[requestId] = req
    
    local headers = req.headers
    
    local app = _G.FFXIFriendListApp
    local logger = app and app.deps and app.deps.logger
    
    local wrappedCallback = function(body, err, status)
        req.status = 'completed'
        
        local app = _G.FFXIFriendListApp
        local logger = app and app.deps and app.deps.logger
        local completeTimeMs = 0
        if app and app.deps and app.deps.time then
            completeTimeMs = app.deps.time()
        else
            completeTimeMs = os.time() * 1000
        end
        req.completeTimeMs = completeTimeMs
        
        if logger and logger.warn then
            if not (status and status >= 200 and status < 300) then
                local totalTime = completeTimeMs - req.enqueueTimeMs
                local errorStr = err or "Unknown error"
                if type(errorStr) == "table" then
                    errorStr = "Request error"
                end
                logger.warn(string.format("[Net] [%d] Failed: %s %s -> %d (%s) (total: %dms)", 
                    completeTimeMs, req.method, req.url, status or 0, tostring(errorStr), totalTime))
            end
        end
        
        if req.callback then
            local errorStr = ""
            if err then
                if type(err) == "table" then
                    errorStr = "Request error"
                else
                    errorStr = tostring(err)
                end
            end
            
            local success = (body ~= nil) and (errorStr == "") and (status and status >= 200 and status < 300)
            local response = body or ""
            
            if not success then
                if errorStr == "" and status then
                    errorStr = "HTTP " .. tostring(status)
                elseif status and status ~= 0 then
                    errorStr = "HTTP " .. tostring(status) .. (errorStr ~= "" and (": " .. errorStr) or "")
                elseif errorStr == "" then
                    errorStr = "Request failed"
                end
            end
            
            -- Pass status as 4th argument for callers that need it (e.g., diagnostics)
            req.callback(success, response, errorStr, status)
        end
        
        requestQueue[requestId] = nil
        requestIdMap[requestId] = nil
    end
    
    local moduleRequestId = nil
    if req.method == "GET" then
        moduleRequestId = http.get(req.url, headers, wrappedCallback)
    elseif req.method == "POST" then
        moduleRequestId = http.post(req.url, req.body, headers, wrappedCallback)
    elseif req.method == "PATCH" then
        moduleRequestId = http.patch(req.url, req.body, headers, wrappedCallback)
    elseif req.method == "DELETE" then
        moduleRequestId = http.delete(req.url, headers, wrappedCallback)
    else
        req.status = 'error'
        if req.callback then
            req.callback(false, "", "Unsupported HTTP method: " .. req.method)
        end
        requestQueue[requestId] = nil
        return nil
    end
    
    if moduleRequestId then
        req.status = 'processing'
        requestIdMap[requestId] = moduleRequestId
        local sendTimeMs = 0
        if app and app.deps and app.deps.time then
            sendTimeMs = app.deps.time()
        else
            sendTimeMs = os.time() * 1000
        end
        req.sendTimeMs = sendTimeMs
    else
        req.status = 'error'
        if req.callback then
            req.callback(false, "", "Failed to submit request")
        end
        requestQueue[requestId] = nil
        return nil
    end
    
    return requestId
end

function M.poll()
    if not http then
        return
    end
    if http.processAll then
        for i = 1, NetworkConstants.POLL_CALLS_PER_FRAME do
            http.processAll()
        end
    end
end

function M.cleanup()
    if not http then
        return
    end
    local now = os.clock()
    for id, req in pairs(requestQueue) do
        if (now - req.timestamp > TimingConstants.REQUEST_CLEANUP_TIMEOUT_SECONDS) or (req.status == 'error') then
            if requestIdMap[id] and http.cancel then
                http.cancel(requestIdMap[id])
            end
            requestQueue[id] = nil
            requestIdMap[id] = nil
        end
    end
end

function M.getInFlightCount()
    return getInFlightCount()
end

function M.cancel(requestId)
    if not http then
        return
    end
    if requestIdMap[requestId] and http.cancel then
        http.cancel(requestIdMap[requestId])
    end
    requestQueue[requestId] = nil
    requestIdMap[requestId] = nil
end

return M
