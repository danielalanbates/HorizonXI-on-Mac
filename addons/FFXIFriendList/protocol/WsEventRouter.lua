-- WsEventRouter.lua
-- Routes WebSocket events by type to registered handlers

local WsEnvelope = require("protocol.WsEnvelope")

local M = {}

M.WsEventRouter = {}
M.WsEventRouter.__index = M.WsEventRouter

-- Create a new event router
-- deps: { logger }
function M.WsEventRouter.new(deps)
    local self = setmetatable({}, M.WsEventRouter)
    self.deps = deps or {}
    self.logger = deps.logger
    
    -- Event handlers table: eventType -> handler function
    self.handlers = {}
    
    -- Default handler for unknown events
    self.defaultHandler = nil
    
    return self
end

-- Register a handler for a specific event type
-- handler: function(payload, eventType, seq, timestamp)
function M.WsEventRouter:registerHandler(eventType, handler)
    if type(handler) ~= "function" then
        if self.logger and self.logger.warn then
            self.logger.warn("[WsEventRouter] Handler for " .. tostring(eventType) .. " is not a function")
        end
        return
    end
    self.handlers[eventType] = handler
end

-- Set a default handler for unknown event types
function M.WsEventRouter:setDefaultHandler(handler)
    self.defaultHandler = handler
end

-- Route a raw WebSocket message
-- Returns: success, error message
function M.WsEventRouter:route(rawMessage)
    -- Decode the envelope
    local ok, event, errorMsg = WsEnvelope.decode(rawMessage)
    if not ok then
        if self.logger and self.logger.warn then
            self.logger.warn("[WsEventRouter] Failed to decode: " .. tostring(errorMsg))
        end
        return false, errorMsg
    end
    
    -- Find handler for this event type
    local handler = self.handlers[event.type]
    
    if not handler then
        -- Try default handler
        if self.defaultHandler then
            handler = self.defaultHandler
        else
            return true  -- Not an error, just unhandled
        end
    end
    
    -- Dispatch to handler with payload, eventType, seq, timestamp
    local handlerOk, handlerErr = pcall(function()
        handler(event.payload, event.type, event.seq, event.timestamp)
    end)
    
    if not handlerOk then
        if self.logger and self.logger.error then
            self.logger.error("[WsEventRouter] Handler error for " .. event.type .. ": " .. tostring(handlerErr))
        end
        return false, handlerErr
    end
    
    return true
end

-- Summarize payload for logging (avoid logging sensitive data)
function M.WsEventRouter:_summarizePayload(payload)
    if not payload or type(payload) ~= "table" then
        return "{}"
    end
    
    local keys = {}
    for k, _ in pairs(payload) do
        table.insert(keys, k)
    end
    
    if #keys == 0 then
        return "{}"
    end
    
    return "{ " .. table.concat(keys, ", ") .. " }"
end

return M
