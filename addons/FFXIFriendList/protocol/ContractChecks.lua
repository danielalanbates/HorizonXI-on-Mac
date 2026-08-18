local Endpoints = require('protocol.Endpoints')

local M = {}

local debugMode = false
local reportedErrors = {}

function M.setDebugMode(enabled)
    debugMode = enabled or false
end

function M.isDebugMode()
    return debugMode
end

local function getLogger()
    local app = _G.FFXIFriendListApp
    if app and app.deps and app.deps.logger then
        return app.deps.logger
    end
    return nil
end

local function logOnce(key, message)
    if not debugMode then
        return
    end
    
    if reportedErrors[key] then
        return
    end
    
    reportedErrors[key] = true
    
    local logger = getLogger()
    if logger and logger.warn then
        logger.warn("[ContractCheck] " .. message)
    end
end

function M.assertFields(endpointName, obj, requiredFields)
    if not debugMode then
        return true
    end
    
    if type(obj) ~= "table" then
        logOnce(endpointName .. "_not_table", endpointName .. ": Expected table, got " .. type(obj))
        return false
    end
    
    local allValid = true
    for _, field in ipairs(requiredFields) do
        if obj[field] == nil then
            logOnce(endpointName .. "_missing_" .. field, endpointName .. ": Missing required field '" .. field .. "'")
            allValid = false
        end
    end
    
    return allValid
end

function M.assertType(endpointName, fieldName, value, expectedType)
    if not debugMode then
        return true
    end
    
    local actualType = type(value)
    
    if expectedType == "number" and actualType == "string" then
        if tonumber(value) ~= nil then
            return true
        end
    end
    
    if actualType ~= expectedType then
        logOnce(
            endpointName .. "_type_" .. fieldName,
            endpointName .. ": Field '" .. fieldName .. "' expected " .. expectedType .. ", got " .. actualType
        )
        return false
    end
    
    return true
end

function M.assertArray(endpointName, fieldName, arr)
    if not debugMode then
        return true
    end
    
    if type(arr) ~= "table" then
        logOnce(
            endpointName .. "_array_" .. fieldName,
            endpointName .. ": Field '" .. fieldName .. "' expected array, got " .. type(arr)
        )
        return false
    end
    
    if arr[1] == nil and next(arr) ~= nil then
        logOnce(
            endpointName .. "_array_" .. fieldName .. "_not_indexed",
            endpointName .. ": Field '" .. fieldName .. "' appears to be object, not array"
        )
        return false
    end
    
    return true
end

function M.assertOptionalType(endpointName, fieldName, value, expectedType)
    if not debugMode then
        return true
    end
    
    if value == nil then
        return true
    end
    
    return M.assertType(endpointName, fieldName, value, expectedType)
end

function M.assertEnum(endpointName, fieldName, value, allowedValues)
    if not debugMode then
        return true
    end
    
    if value == nil then
        return true
    end
    
    for _, allowed in ipairs(allowedValues) do
        if value == allowed then
            return true
        end
    end
    
    logOnce(
        endpointName .. "_enum_" .. fieldName,
        endpointName .. ": Field '" .. fieldName .. "' value '" .. tostring(value) .. "' not in allowed values"
    )
    return false
end

function M.validateAuthEnsure(response)
    local name = "AUTH_ENSURE"
    M.assertFields(name, response, {"accountId", "characterId", "apiKey", "activeCharacterName"})
    M.assertType(name, "accountId", response.accountId, "number")
    M.assertType(name, "characterId", response.characterId, "number")
    M.assertType(name, "apiKey", response.apiKey, "string")
    M.assertType(name, "activeCharacterName", response.activeCharacterName, "string")
    M.assertOptionalType(name, "wasCreated", response.wasCreated, "boolean")
end

function M.validateHeartbeat(response)
    local name = "HEARTBEAT"
    M.assertFields(name, response, {"success"})
    M.assertType(name, "success", response.success, "boolean")
    M.assertOptionalType(name, "nextHeartbeatMs", response.nextHeartbeatMs, "number")
    if response.events then
        M.assertArray(name, "events", response.events)
    end
end

function M.validateFriendsList(response)
    local name = "FRIENDS_LIST"
    M.assertFields(name, response, {"friends"})
    M.assertArray(name, "friends", response.friends)
    
    if response.friends and #response.friends > 0 then
        local firstFriend = response.friends[1]
        M.assertFields(name .. ".friend", firstFriend, {"friendAccountId"})
    end
end

function M.validateFriendRequests(response)
    local name = "FRIEND_REQUESTS"
    M.assertFields(name, response, {"incoming", "outgoing"})
    M.assertArray(name, "incoming", response.incoming)
    M.assertArray(name, "outgoing", response.outgoing)
end

function M.validatePreferences(response)
    local name = "PREFERENCES"
    M.assertFields(name, response, {"preferences"})
    M.assertType(name, "preferences", response.preferences, "table")
end

function M.validateNotesList(response)
    local name = "NOTES_LIST"
    M.assertFields(name, response, {"notes"})
    M.assertArray(name, "notes", response.notes)
end

function M.validateCharactersList(response)
    local name = "CHARACTERS_LIST"
    M.assertFields(name, response, {"characters"})
    M.assertArray(name, "characters", response.characters)
end

function M.validateServerList(response)
    local name = "SERVER_LIST"
    M.assertFields(name, response, {"servers"})
    M.assertArray(name, "servers", response.servers)
end

function M.validateResponse(responseType, decodedPayload)
    if not debugMode then
        return
    end
    
    if not decodedPayload then
        return
    end
    
    if responseType == "AuthEnsureResponse" then
        M.validateAuthEnsure(decodedPayload)
    elseif responseType == "HeartbeatResponse" then
        M.validateHeartbeat(decodedPayload)
    elseif responseType == "FriendsListResponse" then
        M.validateFriendsList(decodedPayload)
    elseif responseType == "FriendRequestsResponse" then
        M.validateFriendRequests(decodedPayload)
    elseif responseType == "PreferencesResponse" or responseType == "PreferencesUpdateResponse" then
        M.validatePreferences(decodedPayload)
    elseif responseType == "NotesListResponse" then
        M.validateNotesList(decodedPayload)
    elseif responseType == "CharactersListResponse" then
        M.validateCharactersList(decodedPayload)
    elseif responseType == "ServerList" then
        M.validateServerList(decodedPayload)
    end
end

function M.clearReportedErrors()
    reportedErrors = {}
end

return M

