local M = {}

M.NotificationSoundType = {
    FriendOnline = 1,
    FriendRequest = 2,
    Unknown = 3
}

M.COOLDOWN_FRIEND_ONLINE_MS = 10000
M.COOLDOWN_FRIEND_REQUEST_MS = 5000

M.NotificationSoundPolicy = {}
M.NotificationSoundPolicy.__index = M.NotificationSoundPolicy

function M.NotificationSoundPolicy.new()
    local self = setmetatable({}, M.NotificationSoundPolicy)
    self.soundStates = {}
    self.soundStates[M.NotificationSoundType.FriendOnline] = {
        lastPlayTimeMs = 0,
        suppressedCount = 0
    }
    self.soundStates[M.NotificationSoundType.FriendRequest] = {
        lastPlayTimeMs = 0,
        suppressedCount = 0
    }
    return self
end

function M.NotificationSoundPolicy:getCooldownMs(type)
    if type == M.NotificationSoundType.FriendOnline then
        return M.COOLDOWN_FRIEND_ONLINE_MS
    elseif type == M.NotificationSoundType.FriendRequest then
        return M.COOLDOWN_FRIEND_REQUEST_MS
    else
        return 0
    end
end

function M.NotificationSoundPolicy:shouldPlay(type, currentTimeMs)
    local state = self.soundStates[type]
    if not state then
        return false
    end
    
    local cooldown = self:getCooldownMs(type)
    
    if state.lastPlayTimeMs == 0 or currentTimeMs - state.lastPlayTimeMs >= cooldown then
        state.lastPlayTimeMs = currentTimeMs
        return true
    end
    
    state.suppressedCount = (state.suppressedCount or 0) + 1
    return false
end

function M.NotificationSoundPolicy:reset()
    for _, state in pairs(self.soundStates) do
        state.lastPlayTimeMs = 0
        state.suppressedCount = 0
    end
end

function M.NotificationSoundPolicy:getSuppressedCount(type)
    local state = self.soundStates[type]
    if state then
        return state.suppressedCount or 0
    end
    return 0
end

return M

