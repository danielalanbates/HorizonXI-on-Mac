-- MessageTypes.lua
-- Request and Response type definitions and string conversions

-- RequestType enum (as table with string keys)
local RequestType = {
    GetFriendList = "GetFriendList",
    SetFriendList = "SetFriendList",
    GetStatus = "GetStatus",
    UpdatePresence = "UpdatePresence",
    UpdateMyStatus = "UpdateMyStatus",
    SendFriendRequest = "SendFriendRequest",
    AcceptFriendRequest = "AcceptFriendRequest",
    RejectFriendRequest = "RejectFriendRequest",
    CancelFriendRequest = "CancelFriendRequest",
    GetFriendRequests = "GetFriendRequests",
    GetHeartbeat = "GetHeartbeat",
    GetPreferences = "GetPreferences",
    SetPreferences = "SetPreferences",
    SendMail = "SendMail",
    GetMailInbox = "GetMailInbox",
    GetMailInboxMeta = "GetMailInboxMeta",
    GetMailAll = "GetMailAll",
    GetMailAllMeta = "GetMailAllMeta",
    GetMailBatch = "GetMailBatch",
    GetMailUnreadCount = "GetMailUnreadCount",
    MarkMailRead = "MarkMailRead",
    DeleteMail = "DeleteMail",
    GetNotes = "GetNotes",
    GetNote = "GetNote",
    PutNote = "PutNote",
    DeleteNote = "DeleteNote",
    SetActiveCharacter = "SetActiveCharacter",
    SubmitFeedback = "SubmitFeedback",
    SubmitIssue = "SubmitIssue"
}

-- ResponseType enum (as table with string keys)
-- Matches server response type names from audit
local ResponseType = {
    FriendsListResponse = "FriendsListResponse",
    FriendRequestsResponse = "FriendRequestsResponse",
    SendFriendRequestResponse = "SendFriendRequestResponse",
    AcceptFriendRequestResponse = "AcceptFriendRequestResponse",
    RejectFriendRequestResponse = "RejectFriendRequestResponse",
    CancelFriendRequestResponse = "CancelFriendRequestResponse",
    AddFriendResponse = "AddFriendResponse",
    RemoveFriendResponse = "RemoveFriendResponse",
    AltVisibilityResponse = "AltVisibilityResponse",
    SyncFriendsResponse = "SyncFriendsResponse",
    HeartbeatResponse = "HeartbeatResponse",
    PreferencesResponse = "PreferencesResponse",
    PreferencesUpdateResponse = "PreferencesUpdateResponse",
    MailListResponse = "MailListResponse",
    UnreadCountResponse = "UnreadCountResponse",
    MailMessageResponse = "MailMessageResponse",
    MailSentResponse = "MailSentResponse",
    NotesListResponse = "NotesListResponse",
    NoteResponse = "NoteResponse",
    NoteUpdateResponse = "NoteUpdateResponse",
    CharactersListResponse = "CharactersListResponse",
    SetActiveCharacterResponse = "SetActiveCharacterResponse",
    StateUpdateResponse = "StateUpdateResponse",
    PrivacyUpdateResponse = "PrivacyUpdateResponse",
    AuthEnsureResponse = "AuthEnsureResponse",
    MeResponse = "MeResponse",
    AddCharacterResponse = "AddCharacterResponse",
    FeedbackResponse = "FeedbackResponse",
    IssueResponse = "IssueResponse",
    ServerList = "ServerList",
    BlockAccountResponse = "BlockAccountResponse",
    UnblockAccountResponse = "UnblockAccountResponse",
    BlockedAccountsResponse = "BlockedAccountsResponse",
    Error = "Error"
}

local function requestTypeToString(type)
    return type or "Unknown"
end

local function stringToRequestType(str)
    for key, value in pairs(RequestType) do
        if value == str then
            return value
        end
    end
    return nil
end

local function responseTypeToString(type)
    return type or "Unknown"
end

local function stringToResponseType(str)
    -- Direct match with ResponseType enum
    for key, value in pairs(ResponseType) do
        if value == str then
            return value
        end
    end
    
    return nil
end

-- Module exports
local M = {}

M.RequestType = RequestType
M.ResponseType = ResponseType
M.requestTypeToString = requestTypeToString
M.stringToRequestType = stringToRequestType
M.responseTypeToString = responseTypeToString
M.stringToResponseType = stringToResponseType

return M

