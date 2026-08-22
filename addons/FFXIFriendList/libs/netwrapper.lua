--[[
* libs/netwrapper.lua
* Network wrapper for app features
* Provides request() function that matches app feature expectations
* Uses libs/net.lua internally
]]--

local net = require("libs.net")
local HttpHeaders = require("protocol.Encoding.HttpHeaders")

local M = {}

-- Create network wrapper instance
function M.new(sessionManager, realmDetector, connection)
    local self = {
        session = sessionManager,
        realmDetector = realmDetector,
        connection = connection  -- connection feature for getHeaders/getBaseUrl
    }
    
    return self
end

-- Request function (matches app feature API)
-- options: { url, method?, headers?, body, callback }
-- If headers are provided, use them; otherwise build from connection feature
function M.request(options)
    if not options or not options.url then
        return nil
    end
    
    local headers = options.headers
    
    -- If headers not provided, build them from connection feature
    if not headers then
        headers = {}
        if not headers["Content-Type"] then
            headers["Content-Type"] = "application/json"
        end
        
        -- Add protocol version header
        local ProtocolVersion = require("protocol.ProtocolVersion")
        headers["X-Protocol-Version"] = ProtocolVersion.PROTOCOL_VERSION
        
        -- Add session/realm headers if available
        if self.session and self.session.getSessionId then
            local sessionId = self.session:getSessionId()
            if sessionId and sessionId ~= "" then
                headers["X-Session-Id"] = sessionId
            end
        end
        
        if self.realmDetector and self.realmDetector.getRealmId then
            local realmId = self.realmDetector:getRealmId()
            if realmId and realmId ~= "" then
                headers["X-Realm-Id"] = realmId
            end
        end
        
        -- If connection feature available, use its getHeaders method
        if self.connection and self.connection.getHeaders then
            local characterName = ""  -- TODO: Get from session
            local connHeaders = self.connection:getHeaders(characterName)
            -- Merge connection headers (they take precedence)
            for k, v in pairs(connHeaders) do
                headers[k] = v
            end
        end
    end
    
    -- Call libs/net.request
    return net.request({
        url = options.url,
        method = options.method or "POST",
        headers = headers,
        body = options.body,
        callback = options.callback
    })
end

-- Create network wrapper (factory function)
function M.create(sessionManager, realmDetector, connection)
    local wrapper = {
        session = sessionManager,
        realmDetector = realmDetector,
        connection = connection
    }
    
    wrapper.request = function(options)
        if not options or not options.url then
            return nil
        end
        
        local headers = options.headers
        
        -- If headers not provided, build them
        if not headers then
            headers = {}
            if not headers["Content-Type"] then
                headers["Content-Type"] = "application/json"
            end
            
            local ProtocolVersion = require("protocol.ProtocolVersion")
            headers["X-Protocol-Version"] = ProtocolVersion.PROTOCOL_VERSION
            
            if wrapper.session and wrapper.session.getSessionId then
                local sessionId = wrapper.session:getSessionId()
                if sessionId and sessionId ~= "" then
                    headers["X-Session-Id"] = sessionId
                end
            end
            
            if wrapper.realmDetector and wrapper.realmDetector.getRealmId then
                local realmId = wrapper.realmDetector:getRealmId()
                if realmId and realmId ~= "" then
                    headers["X-Realm-Id"] = realmId
                end
            end
            
            -- If connection feature available, use its getHeaders method
            if wrapper.connection and wrapper.connection.getHeaders then
                local characterName = ""  -- TODO: Get from session
                local connHeaders = wrapper.connection:getHeaders(characterName)
                for k, v in pairs(connHeaders) do
                    headers[k] = v
                end
            end
        end
        
        return net.request({
            url = options.url,
            method = options.method or "POST",
            headers = headers,
            body = options.body,
            callback = options.callback
        })
    end
    
    return wrapper
end

return M

