local TimingConstants = require("core.TimingConstants")
local UIConstants = require("core.UIConstants")

local M = {}

M.ToastType = {
    FriendOnline = "FriendOnline",
    FriendOffline = "FriendOffline",
    FriendRequestReceived = "FriendRequestReceived",
    FriendRequestAccepted = "FriendRequestAccepted",
    FriendRequestRejected = "FriendRequestRejected",
    Error = "Error",
    Info = "Info",
    Warning = "Warning",
    Success = "Success"
}

M.ToastState = {
    ENTERING = "ENTERING",
    VISIBLE = "VISIBLE",
    EXITING = "EXITING",
    COMPLETE = "COMPLETE"
}

M.Toast = {}
M.Toast.__index = M.Toast

local globalToastCounter = 0

function M.Toast.new(type, title, message, createdAt, duration)
    globalToastCounter = globalToastCounter + 1
    local self = setmetatable({}, M.Toast)
    self.id = globalToastCounter
    self.type = type or M.ToastType.Info
    self.title = title or ""
    self.message = message or ""
    self.createdAt = createdAt or 0
    self.duration = duration or TimingConstants.NOTIFICATION_DEFAULT_DURATION_MS
    self.state = M.ToastState.ENTERING
    self.alpha = 0.0
    self.offsetX = 0.0
    self.dismissed = false
    return self
end

M.CharacterChanged = {}
M.CharacterChanged.__index = M.CharacterChanged

function M.CharacterChanged.new(newCharacterName, previousCharacterName, timestamp)
    local self = setmetatable({}, M.CharacterChanged)
    self.newCharacterName = newCharacterName or ""
    self.previousCharacterName = previousCharacterName or ""
    self.timestamp = timestamp or 0
    return self
end

M.ZoneChanged = {}
M.ZoneChanged.__index = M.ZoneChanged

function M.ZoneChanged.new(zoneId, zoneName, timestamp)
    local self = setmetatable({}, M.ZoneChanged)
    self.zoneId = zoneId or 0
    self.zoneName = zoneName or ""
    self.timestamp = timestamp or 0
    return self
end

M.TITLE_ERROR = "Error"
M.TITLE_FRIEND_REQUEST = "Friend Request"
M.TITLE_FRIEND_REMOVED = "Friend Removed"
M.TITLE_FRIEND_VISIBILITY = "Friend Visibility"
M.TITLE_FEEDBACK_SUBMITTED = "Feedback Submitted"
M.TITLE_ISSUE_REPORTED = "Issue Reported"
M.TITLE_KEY_CAPTURE = "Key Capture"

M.MESSAGE_FRIEND_REQUEST_REJECTED = "Friend request rejected"
M.MESSAGE_FRIEND_REQUEST_CANCELED = "Friend request canceled"
M.MESSAGE_FRIEND_REMOVED = "Friend {0} removed"
M.MESSAGE_FRIEND_REMOVED_FROM_VIEW = "Friend {0} removed from this character's view"
M.MESSAGE_VISIBILITY_GRANTED = "Visibility granted for {0}"
M.MESSAGE_VISIBILITY_REQUEST_SENT = "Visibility request sent to {0}"
M.MESSAGE_VISIBILITY_UPDATED = "Visibility updated for {0}"
M.MESSAGE_VISIBILITY_REMOVED = "Visibility removed for {0}"
M.MESSAGE_VISIBILITY_GRANTED_WITH_PERIOD = "Visibility granted for {0}."
M.MESSAGE_FAILED_TO_SEND_REQUEST = "Failed to send request: {0}"
M.MESSAGE_FAILED_TO_SEND_FRIEND_REQUEST = "Failed to send friend request to {0}: {1}"
M.MESSAGE_FAILED_TO_ACCEPT_REQUEST = "Failed to accept request: {0}"
M.MESSAGE_FAILED_TO_REJECT_REQUEST = "Failed to reject request: {0}"
M.MESSAGE_FAILED_TO_CANCEL_REQUEST = "Failed to cancel request: {0}"
M.MESSAGE_FAILED_TO_REMOVE_FRIEND = "Failed to remove friend: {0}"
M.MESSAGE_FAILED_TO_REMOVE_FRIEND_VISIBILITY = "Failed to remove friend visibility: {0}"
M.MESSAGE_FAILED_TO_UPDATE_VISIBILITY = "Failed to update visibility: {0}"
M.MESSAGE_FAILED_TO_SUBMIT_FEEDBACK = "Failed to submit feedback: {0}"
M.MESSAGE_FAILED_TO_REPORT_ISSUE = "Failed to report issue: {0}"
M.MESSAGE_CHARACTER_NAME_REQUIRED_FEEDBACK = "Character name required to submit feedback"
M.MESSAGE_CHARACTER_NAME_REQUIRED_ISSUE = "Character name required to report issue"
M.MESSAGE_INVALID_FEEDBACK_DATA = "Invalid feedback data format"
M.MESSAGE_INVALID_ISSUE_DATA = "Invalid issue data format"
M.MESSAGE_FAILED_TO_PARSE_PREFERENCE = "Failed to parse preference update"
M.MESSAGE_FEEDBACK_SUBMITTED = "Feedback submitted! ID: {0}"
M.MESSAGE_ISSUE_REPORTED = "Issue reported! ID: {0}"
M.MESSAGE_PRESS_ANY_KEY = "Press any key to set custom close key..."
M.DEFAULT_NOTIFICATION_POSITION_X = UIConstants.NOTIFICATION_POSITION[1]
M.DEFAULT_NOTIFICATION_POSITION_Y = UIConstants.NOTIFICATION_POSITION[2]

M.Notifications = {}
M.Notifications.__index = M.Notifications

function M.Notifications.new(deps)
    local self = setmetatable({}, M.Notifications)
    self.deps = deps or {}
    
    self.queue = {}
    
    return self
end

function M.Notifications:getState()
    return {
        pendingCount = #self.queue,
        toasts = self.queue
    }
end

local function getTime(self)
    if self.deps.time then
        return self.deps.time()
    end
    return os.time() * 1000
end

local function dismissExistingTestToasts(self, toastType)
    if not self.queue then
        return
    end
    for _, toast in ipairs(self.queue) do
        if toast.type == toastType and toast.isTest then
            toast.dismissed = true
            toast.state = M.ToastState.COMPLETE
        end
    end
    self:cleanup()
end

local function pushTestToast(self, type, payload)
    payload = payload or {}
    self:cleanup()
    local toast = M.Toast.new(type, payload.title, payload.message, getTime(self), payload.duration)
    toast.isOnline = payload.isOnline
    toast.characterName = payload.characterName
    toast.isTest = true
    table.insert(self.queue, toast)
end

function M.Notifications:push(type, payload)
    payload = payload or {}
    local title = payload.title or ""
    local message = payload.message or ""
    local dedupeKey = payload.dedupeKey
    
    -- Check if this notification type is enabled
    local prefs = nil
    if self.deps and self.deps.preferences and self.deps.preferences.getPrefs then
        prefs = self.deps.preferences:getPrefs()
    end
    
    if prefs then
        if type == M.ToastType.FriendOnline and prefs.notificationShowFriendOnline == false then
            return
        end
        if type == M.ToastType.FriendOffline and prefs.notificationShowFriendOffline == false then
            return
        end
        if type == M.ToastType.FriendRequestReceived and prefs.notificationShowFriendRequest == false then
            return
        end
        if type == M.ToastType.FriendRequestAccepted and prefs.notificationShowRequestAccepted == false then
            return
        end
        if type == M.ToastType.FriendRequestRejected and prefs.notificationShowRequestRejected == false then
            return
        end
    end
    
    -- Clean up dismissed/completed toasts before checking for duplicates
    self:cleanup()
    
    if dedupeKey then
        for _, toast in ipairs(self.queue) do
            if toast.dedupeKey == dedupeKey and not toast.dismissed then
                return
            end
        end
    end
    
    local toast = M.Toast.new(type, title, message, getTime(self), payload.duration)
    toast.dedupeKey = dedupeKey
    
    -- Copy additional payload fields for display (e.g., isOnline for status icon)
    if payload.isOnline ~= nil then
        toast.isOnline = payload.isOnline
    end
    if payload.characterName then
        toast.characterName = payload.characterName
    end
    
    table.insert(self.queue, toast)
end

function M.Notifications:showTestNotification()
    local prefs = nil
    if self.deps and self.deps.preferences and self.deps.preferences.getPrefs then
        prefs = self.deps.preferences:getPrefs()
    end
    
    local duration = TimingConstants.NOTIFICATION_LONG_DURATION_MS
    if prefs and prefs.notificationDuration ~= nil then
        local prefDuration = tonumber(prefs.notificationDuration)
        if prefDuration and prefDuration > 0 then
            duration = prefDuration * 1000
        end
    end
    
    self:push(M.ToastType.FriendOnline, {
        title = "Test Notification",
        message = "This is a test notification to verify display.",
        duration = duration
    })
end

-- Show a test friend-online notification (respects muteTestFriendOnline preference)
function M.Notifications:showTestFriendOnline(friendName)
    dismissExistingTestToasts(self, M.ToastType.FriendOnline)

    local prefs = nil
    if self.deps and self.deps.preferences and self.deps.preferences.getPrefs then
        prefs = self.deps.preferences:getPrefs()
    end
    local name = friendName and friendName ~= "" and friendName or "TestFriend"
    local duration = TimingConstants.NOTIFICATION_DEFAULT_DURATION_MS
    if prefs and prefs.notificationDuration then
        local prefDuration = tonumber(prefs.notificationDuration)
        if prefDuration and prefDuration > 0 then
            duration = prefDuration * 1000
        end
    end
    pushTestToast(self, M.ToastType.FriendOnline, {
        title = "Friend Online",
        message = name .. " is now online",
        duration = duration,
        characterName = name,
        isOnline = true
    })
end

-- Show a test friend-request notification (respects muteTestFriendRequest preference)
function M.Notifications:showTestFriendRequest(friendName)
    dismissExistingTestToasts(self, M.ToastType.FriendRequestReceived)

    local prefs = nil
    if self.deps and self.deps.preferences and self.deps.preferences.getPrefs then
        prefs = self.deps.preferences:getPrefs()
    end

    local name = friendName and friendName ~= "" and friendName or "TestFriend"
    local duration = TimingConstants.NOTIFICATION_DEFAULT_DURATION_MS
    if prefs and prefs.notificationDuration then
        local prefDuration = tonumber(prefs.notificationDuration)
        if prefDuration and prefDuration > 0 then
            duration = prefDuration * 1000
        end
    end

    pushTestToast(self, M.ToastType.FriendRequestReceived, {
        title = "Friend Request",
        message = name .. " sent you a friend request",
        duration = duration,
        characterName = name
    })
end

-- Show 5 unique test notifications 0.5 seconds apart for testing
function M.Notifications:showTestMultipleNotifications()
    local prefs = nil
    if self.deps and self.deps.preferences and self.deps.preferences.getPrefs then
        prefs = self.deps.preferences:getPrefs()
    end

    local duration = TimingConstants.NOTIFICATION_DEFAULT_DURATION_MS
    if prefs and prefs.notificationDuration then
        local prefDuration = tonumber(prefs.notificationDuration)
        if prefDuration and prefDuration > 0 then
            duration = prefDuration * 1000
        end
    end

    local testMessages = {
        {type = M.ToastType.FriendOnline, title = "Friend Online", message = "Warrior is now online", isOnline = true, characterName = "Warrior"},
        {type = M.ToastType.FriendOffline, title = "Friend Offline", message = "Mage went offline", isOnline = false, characterName = "Mage"},
        {type = M.ToastType.FriendRequestReceived, title = "Friend Request", message = "Healer sent you a friend request", characterName = "Healer"},
        {type = M.ToastType.FriendRequestAccepted, title = "Request Accepted", message = "Ranger accepted your friend request", isOnline = true, characterName = "Ranger"},
        {type = M.ToastType.FriendRequestRejected, title = "Request Declined", message = "Thief declined your friend request", characterName = "Thief"}
    }

    -- Use Ashita's scheduler to queue notifications
    for i, msg in ipairs(testMessages) do
        local delay = (i - 1) * 0.5
        ashita.tasks.once(delay, function()
            pushTestToast(self, msg.type, {
                title = msg.title,
                message = msg.message,
                duration = duration,
                isOnline = msg.isOnline,
                characterName = msg.characterName
            })
        end)
    end
end

-- Remove dismissed/completed toasts from the queue to prevent unbounded growth
function M.Notifications:cleanup()
    local newQueue = {}
    for _, toast in ipairs(self.queue) do
        if not toast.dismissed then
            table.insert(newQueue, toast)
        end
    end
    self.queue = newQueue
end

function M.Notifications:drain()
    local result = {}
    for i = #self.queue, 1, -1 do
        if not self.queue[i].dismissed then
            table.insert(result, 1, self.queue[i])
            self.queue[i].dismissed = true
        end
    end
    
    local newQueue = {}
    for _, toast in ipairs(self.queue) do
        if not toast.dismissed then
            table.insert(newQueue, toast)
        end
    end
    self.queue = newQueue
    
    return result
end

return M
