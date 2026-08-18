-- HttpHeaders.lua
-- HTTP header construction

local ProtocolVersion = require("protocol.ProtocolVersion")

local M = {}

-- Header constants (new server format)
M.HEADER_AUTHORIZATION = "Authorization"
M.HEADER_CHARACTER_NAME = "X-Character-Name"
M.HEADER_REALM_ID = "X-Realm-Id"
M.HEADER_PROTOCOL_VERSION = "X-Protocol-Version"
M.HEADER_SESSION_ID = "X-Session-Id"
M.HEADER_CONTENT_TYPE = "Content-Type"
M.HEADER_USER_AGENT = "User-Agent"

-- RequestContext table constructor
function M.RequestContext(apiKey, characterName, realmId, sessionId, contentType, addonVersion)
    return {
        apiKey = apiKey or "",
        characterName = characterName or "",
        realmId = realmId or "",
        sessionId = sessionId or "",
        contentType = contentType or "application/json",
        addonVersion = addonVersion or ""
    }
end

-- Build header list from request context
function M.buildHeaderList(ctx)
    local headers = {}
    
    if ctx.contentType and ctx.contentType ~= "" then
        table.insert(headers, {M.HEADER_CONTENT_TYPE, ctx.contentType})
    end
    
    -- New auth format: Authorization: Bearer <apiKey>
    if ctx.apiKey and ctx.apiKey ~= "" then
        table.insert(headers, {M.HEADER_AUTHORIZATION, "Bearer " .. ctx.apiKey})
    end
    
    -- Character name as X-Character-Name header
    if ctx.characterName and ctx.characterName ~= "" then
        table.insert(headers, {M.HEADER_CHARACTER_NAME, ctx.characterName})
    end
    
    if ctx.realmId and ctx.realmId ~= "" then
        table.insert(headers, {M.HEADER_REALM_ID, ctx.realmId})
    end
    
    table.insert(headers, {M.HEADER_PROTOCOL_VERSION, ProtocolVersion.PROTOCOL_VERSION})
    
    if ctx.sessionId and ctx.sessionId ~= "" then
        table.insert(headers, {M.HEADER_SESSION_ID, ctx.sessionId})
    end
    
    -- Add User-Agent if version info available
    if ctx.addonVersion and ctx.addonVersion ~= "" then
        table.insert(headers, {M.HEADER_USER_AGENT, "FFXIFriendList/" .. ctx.addonVersion})
    end
    
    return headers
end

-- Serialize headers for HTTP (WinHttp format: "Header: Value\r\n")
function M.serializeForWinHttp(headers)
    local parts = {}
    for i = 1, #headers do
        table.insert(parts, headers[i][1] .. ": " .. headers[i][2] .. "\r\n")
    end
    return table.concat(parts, "")
end

-- Build headers string from request context
function M.build(ctx)
    return M.serializeForWinHttp(M.buildHeaderList(ctx))
end

-- Check if headers have required fields
function M.hasRequiredHeaders(headers)
    local hasContentType = false
    local hasProtocolVersion = false
    
    for i = 1, #headers do
        if headers[i][1] == M.HEADER_CONTENT_TYPE then
            hasContentType = true
        end
        if headers[i][1] == M.HEADER_PROTOCOL_VERSION then
            hasProtocolVersion = true
        end
    end
    
    return hasContentType and hasProtocolVersion
end

return M

