-- Envelope.lua
-- HTTP response envelope decoding for new server format
-- Server returns: { success: bool, data: T, timestamp: string }
-- Error returns: { success: false, error: { code: string, message: string }, timestamp: string }

local Json = require("protocol.Json")

local M = {}

M.DecodeError = {
    InvalidJson = "InvalidJson",
    MissingSuccess = "MissingSuccess",
    ServerError = "ServerError"
}

-- Decode HTTP response from new server
-- Returns: success, result (or error code, error message)
function M.decode(jsonString)
    if not jsonString or jsonString == "" then
        return false, M.DecodeError.InvalidJson, "Empty response"
    end
    
    local ok, data = Json.decode(jsonString)
    if not ok then
        local errorMsg = data
        if type(errorMsg) == "table" then
            errorMsg = "Invalid JSON"
        else
            errorMsg = tostring(errorMsg or "Invalid JSON")
        end
        return false, M.DecodeError.InvalidJson, errorMsg
    end
    
    if type(data) ~= "table" then
        return false, M.DecodeError.InvalidJson, "Response is not an object"
    end
    
    -- Check for success field (required by new server contract)
    if data.success == nil then
        return false, M.DecodeError.MissingSuccess, "Missing success field"
    end
    
    -- Handle error response
    if data.success == false then
        local errorInfo = data.error or {}
        local code = errorInfo.code or "UNKNOWN_ERROR"
        local message = errorInfo.message or "Unknown server error"
        return false, M.DecodeError.ServerError, message, code
    end
    
    -- Success response - extract data
    local result = {
        success = true,
        data = data.data or {},
        timestamp = data.timestamp or ""
    }
    
    return true, result
end

-- Decode and extract just the data payload
-- Convenience method for endpoints that don't need envelope metadata
function M.decodeData(jsonString)
    local ok, result, errorMessage, errorCode = M.decode(jsonString)
    if not ok then
        return false, errorMessage, errorCode
    end
    return true, result.data
end

return M
