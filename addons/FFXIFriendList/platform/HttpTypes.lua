-- HttpTypes.lua
-- HTTP-related types (shared between platform and app layers)

local M = {}

-- HttpResponse structure
M.HttpResponse = {}
M.HttpResponse.__index = M.HttpResponse

function M.HttpResponse.new(statusCode, body, error)
    local self = setmetatable({}, M.HttpResponse)
    self.statusCode = statusCode or 0
    self.body = body or ""
    self.error = error or ""
    return self
end

function M.HttpResponse:isSuccess()
    return self.statusCode >= 200 and self.statusCode < 300 and self.error == ""
end

return M

