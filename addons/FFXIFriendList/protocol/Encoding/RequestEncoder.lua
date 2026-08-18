-- RequestEncoder.lua
-- Request message encoding

local ProtocolVersion = require("protocol.ProtocolVersion")
local MessageTypes = require("protocol.MessageTypes")
local Json = require("protocol.Json")

local M = {}

-- Normalize character/realm fields for HTTP payloads
local function normalizeCharacterName(name)
    if not name then return "" end
    local trimmed = tostring(name):match("^%s*(.-)%s*$") or ""
    return string.lower(trimmed)
end

local function normalizeRealmId(realmId)
    if not realmId then return "unknown" end
    local trimmed = tostring(realmId):match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return "unknown" end
    return string.lower(trimmed)
end

-- Encode a RequestMessage
function M.encode(request)
    local requestTable = {
        protocolVersion = request.protocolVersion,
        type = MessageTypes.requestTypeToString(request.type)
    }
    
    if request.payload then
        if type(request.payload) == "string" then
            requestTable.payload = request.payload
        else
            requestTable.payload = Json.encode(request.payload)
        end
    end
    
    return Json.encode(requestTable)
end

-- Encode GetFriendList request
function M.encodeGetFriendList()
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetFriendList,
        payload = "{}"
    }
    return M.encode(request)
end

-- Encode SetFriendList request
function M.encodeSetFriendList(friends)
    local statuses = {}
    for i = 1, #friends do
        local f = friends[i]
        local friendObj = {
            name = f.name
        }
        if f.friendedAs and f.friendedAs ~= "" and f.friendedAs ~= f.name then
            friendObj.friendedAs = f.friendedAs
        end
        if f.linkedCharacters and #f.linkedCharacters > 0 then
            friendObj.linkedCharacters = f.linkedCharacters
        end
        table.insert(statuses, friendObj)
    end
    
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.SetFriendList,
        payload = Json.encode({statuses = statuses})
    }
    return M.encode(request)
end

-- Encode GetStatus request
function M.encodeGetStatus(characterName)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetStatus,
        payload = Json.encode({characterName = characterName})
    }
    return M.encode(request)
end

-- Encode UpdatePresence request
function M.encodeUpdatePresence(presence)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.UpdatePresence,
        payload = Json.encode({
            characterName = presence.characterName,
            job = presence.job,
            rank = presence.rank,
            nation = presence.nation,
            zone = presence.zone,
            isAnonymous = presence.isAnonymous,
            timestamp = presence.timestamp
        })
    }
    return M.encode(request)
end

-- Encode UpdateMyStatus request
function M.encodeUpdateMyStatus(showOnlineStatus, shareLocation, isAnonymous, shareJobWhenAnonymous)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.UpdateMyStatus,
        payload = Json.encode({
            showOnlineStatus = showOnlineStatus,
            shareLocation = shareLocation,
            isAnonymous = isAnonymous,
            shareJobWhenAnonymous = shareJobWhenAnonymous
        })
    }
    return M.encode(request)
end

-- Encode SendFriendRequest request
function M.encodeSendFriendRequest(toUserId)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.SendFriendRequest,
        payload = Json.encode({toUserId = toUserId})
    }
    return M.encode(request)
end

-- Encode AcceptFriendRequest request
function M.encodeAcceptFriendRequest(requestId)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.AcceptFriendRequest,
        payload = Json.encode({requestId = requestId})
    }
    return M.encode(request)
end

-- Encode RejectFriendRequest request
function M.encodeRejectFriendRequest(requestId)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.RejectFriendRequest,
        payload = Json.encode({requestId = requestId})
    }
    return M.encode(request)
end

-- Encode CancelFriendRequest request
function M.encodeCancelFriendRequest(requestId)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.CancelFriendRequest,
        payload = Json.encode({requestId = requestId})
    }
    return M.encode(request)
end

-- Encode RemoveFriend request
function M.encodeRemoveFriend(friendName)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.RemoveFriend or "RemoveFriend",  -- May not be in enum
        payload = Json.encode({friendName = friendName})
    }
    return M.encode(request)
end

-- Encode GetFriendRequests request
function M.encodeGetFriendRequests(characterName)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetFriendRequests,
        payload = Json.encode({characterName = characterName})
    }
    return M.encode(request)
end

-- Encode GetHeartbeat request
function M.encodeGetHeartbeat(characterName, lastEventTimestamp, lastRequestEventTimestamp, pluginVersion)
    local payload = {
        characterName = characterName,
        lastEventTimestamp = lastEventTimestamp,
        lastRequestEventTimestamp = lastRequestEventTimestamp
    }
    if pluginVersion and pluginVersion ~= "" then
        payload.clientVersion = pluginVersion
    end
    
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetHeartbeat,
        payload = Json.encode(payload)
    }
    return M.encode(request)
end

-- Encode GetPreferences request
function M.encodeGetPreferences()
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetPreferences,
        payload = "{}"
    }
    return M.encode(request)
end

-- Encode SetPreferences request
function M.encodeSetPreferences(prefs)
    local mainView = (prefs.mainFriendView and type(prefs.mainFriendView) == "table") and prefs.mainFriendView or {}
    
    local payload = {
        shareFriendsAcrossAlts = prefs.shareFriendsAcrossAlts,
        showJobColumn = mainView.showJob or true,
        showZoneColumn = mainView.showZone or false,
        showNationColumn = mainView.showNationRank or false,
        showRankColumn = mainView.showNationRank or false,
        showLastSeenColumn = mainView.showLastSeen or false
    }
    
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.SetPreferences,
        payload = Json.encode(payload)
    }
    return M.encode(request)
end

-- Encode SendMail request
function M.encodeSendMail(toUserId, subject, body)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.SendMail,
        payload = Json.encode({
            toUserId = toUserId,
            subject = subject,
            body = body
        })
    }
    return M.encode(request)
end

-- Encode GetMailInbox request
function M.encodeGetMailInbox(limit, offset)
    limit = limit or 50
    offset = offset or 0
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetMailInbox,
        payload = Json.encode({
            limit = limit,
            offset = offset
        })
    }
    return M.encode(request)
end

-- Encode GetMailInboxMeta request (returns empty, uses query parameter)
function M.encodeGetMailInboxMeta(limit, offset)
    return ""
end

-- Encode GetMailAll request
function M.encodeGetMailAll(folder, limit, offset, since)
    limit = limit or 100
    offset = offset or 0
    since = since or 0
    local payload = {
        folder = folder,
        limit = limit,
        offset = offset
    }
    if since > 0 then
        payload.since = since
    end
    
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetMailAll,
        payload = Json.encode(payload)
    }
    return M.encode(request)
end

-- Encode GetMailAllMeta request (returns empty, uses query parameter)
function M.encodeGetMailAllMeta(folder, limit, offset, since)
    return ""
end

-- Encode GetMailBatch request
function M.encodeGetMailBatch(mailbox, messageIds)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetMailBatch,
        payload = Json.encode({
            mailbox = mailbox,
            ids = messageIds
        })
    }
    return M.encode(request)
end

-- Encode GetMailUnreadCount request
function M.encodeGetMailUnreadCount()
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetMailUnreadCount,
        payload = "{}"
    }
    return M.encode(request)
end

-- Encode MarkMailRead request
function M.encodeMarkMailRead(messageId)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.MarkMailRead,
        payload = Json.encode({messageId = messageId})
    }
    return M.encode(request)
end

-- Encode DeleteMail request
function M.encodeDeleteMail(messageId)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.DeleteMail,
        payload = Json.encode({messageId = messageId})
    }
    return M.encode(request)
end

-- Encode GetNotes request
function M.encodeGetNotes()
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetNotes,
        payload = "{}"
    }
    return M.encode(request)
end

-- Encode GetNote request
function M.encodeGetNote(friendName)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.GetNote,
        payload = Json.encode({friendName = friendName})
    }
    return M.encode(request)
end

-- Encode PutNote request
function M.encodePutNote(friendName, noteText)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.PutNote,
        payload = Json.encode({
            friendName = friendName,
            note = noteText
        })
    }
    return M.encode(request)
end

-- Encode DeleteNote request
function M.encodeDeleteNote(friendName)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.DeleteNote,
        payload = Json.encode({friendName = friendName})
    }
    return M.encode(request)
end

-- Encode SubmitFeedback request
function M.encodeSubmitFeedback(subject, message)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.SubmitFeedback,
        payload = Json.encode({
            subject = subject,
            message = message
        })
    }
    return M.encode(request)
end

-- Encode SubmitIssue request
function M.encodeSubmitIssue(subject, message)
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = MessageTypes.RequestType.SubmitIssue,
        payload = Json.encode({
            subject = subject,
            message = message
        })
    }
    return M.encode(request)
end

-- Encode GetServerList request (public, no auth)
function M.encodeGetServerList()
    local request = {
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = "GetServerList",  -- Note: May not be in RequestType enum, using string
        payload = "{}"
    }
    return M.encode(request)
end

-- ============================================================================
-- New Server Endpoints (friendlist-server)
-- ============================================================================

-- Encode Register request (for /api/auth/register endpoint)
-- Creates a new account with the given character (no auth required)
-- Body: {"characterName": "...", "realmId": "..."}
function M.encodeRegister(characterName, realmId)
    local body = {
        characterName = characterName,
        realmId = realmId or "unknown"
    }
    return Json.encode(body)
end

-- Encode AddCharacter request (for /api/auth/add-character endpoint)
-- Adds a character to the authenticated account
-- Body: {"name": "...", "realmId": "..."}
function M.encodeAddCharacter(characterName, realmId)
    local body = {
        name = characterName,
        realmId = realmId or "unknown"
    }
    return Json.encode(body)
end

-- Encode SetActiveCharacter request (for /api/auth/set-active endpoint)
-- Sets the active character for the account
-- Body: {"characterId": "uuid"}
function M.encodeSetActiveCharacter(characterId)
    local body = {
        characterId = characterId
    }
    return Json.encode(body)
end

-- Encode SendFriendRequest for new server (for /api/friends/request endpoint)
-- Body: {"characterName": "...", "realmId": "..."}
function M.encodeNewSendFriendRequest(characterName, realmId)
    local body = {
        characterName = normalizeCharacterName(characterName),
        realmId = normalizeRealmId(realmId)
    }
    return Json.encode(body)
end

-- Encode Block request (for /api/block endpoint)
-- Body: {"characterName": "...", "realmId": "..."}
function M.encodeBlock(characterName, realmId)
    local body = {
        characterName = normalizeCharacterName(characterName),
        realmId = normalizeRealmId(realmId)
    }
    return Json.encode(body)
end

-- Encode PresenceUpdate request (for /api/presence/update endpoint)
-- Body: { job?, subJob?, jobLevel?, subJobLevel?, zone?, nation?, rank?, isAnonymous? }
-- Server expects:
--   job: string (e.g., "WHM", "SMN") - main job only
--   subJob: string (e.g., "BLM", "WHM") - sub job only  
--   jobLevel: number (1-99)
--   subJobLevel: number (0-49)
--   nation: string (e.g., "San d'Oria", "Bastok", "Windurst")
--   rank: number (1-10)
function M.encodePresenceUpdate(presence)
    local body = {}
    
    -- Only send job info if we have valid levels (>= 1)
    local hasValidJob = (presence.mainJobLevel and presence.mainJobLevel > 0) or (presence.jobLevel and presence.jobLevel > 0)
    
    if hasValidJob then
        -- Use mainJob numeric ID if available, otherwise extract from job string
        if presence.mainJob then
            -- Convert numeric job ID to abbreviation
            local jobNames = {
                "NON", "WAR", "MNK", "WHM", "BLM", "RDM", "THF", "PLD", "DRK", "BST",
                "BRD", "RNG", "SAM", "NIN", "DRG", "SMN", "BLU", "COR", "PUP", "DNC",
                "SCH", "GEO", "RUN"
            }
            body.job = jobNames[presence.mainJob + 1] or "NON"
        elseif presence.job and presence.job ~= "" then
            -- Fallback: extract from formatted string
            local jobAbbr = presence.job:match("^(%u+)") or ""
            if jobAbbr ~= "" then
                body.job = jobAbbr
            end
        end
        
        -- Send job levels
        if presence.mainJobLevel and presence.mainJobLevel > 0 then
            body.jobLevel = presence.mainJobLevel
        elseif presence.jobLevel and presence.jobLevel > 0 then
            body.jobLevel = presence.jobLevel
        end
        
        -- SubJob and level
        if presence.subJob then body.subJob = presence.subJob end
        if presence.subJobLevel and presence.subJobLevel > 0 then
            body.subJobLevel = presence.subJobLevel
        end
    end
    
    if presence.zone then body.zone = presence.zone end
    
    -- Nation: convert number to string
    -- 0 = San d'Oria, 1 = Bastok, 2 = Windurst
    if presence.nation ~= nil then
        local nationNames = {
            [0] = "San d'Oria",
            [1] = "Bastok",
            [2] = "Windurst"
        }
        if type(presence.nation) == "number" then
            body.nation = nationNames[presence.nation] or "Unknown"
        else
            body.nation = tostring(presence.nation)
        end
    end
    
    -- Rank: extract number from "Rank X" string
    if presence.rank ~= nil then
        if type(presence.rank) == "string" then
            local rankNum = presence.rank:match("(%d+)")
            body.rank = tonumber(rankNum) or 1
        elseif type(presence.rank) == "number" then
            body.rank = presence.rank
        end
    end
    
    if presence.isAnonymous ~= nil then body.isAnonymous = presence.isAnonymous end
    return Json.encode(body)
end

-- Encode Heartbeat request (for /api/presence/heartbeat endpoint)
-- Body: { timestamp?: string, characterId?: string }
function M.encodeHeartbeat(timestamp, characterId)
    local body = {}
    if timestamp then body.timestamp = timestamp end
    if characterId then body.characterId = characterId end
    return Json.encode(body)
end

-- Encode UpdatePreferences request (for PATCH /api/preferences endpoint)
-- Body: { presenceStatus?, shareLocation?, shareJobWhenAnonymous? }
function M.encodeUpdatePreferences(prefs)
    local body = {}
    if prefs.presenceStatus then body.presenceStatus = prefs.presenceStatus end
    if prefs.shareLocation ~= nil then body.shareLocation = prefs.shareLocation end
    if prefs.shareJobWhenAnonymous ~= nil then body.shareJobWhenAnonymous = prefs.shareJobWhenAnonymous end
    return Json.encode(body)
end

return M

