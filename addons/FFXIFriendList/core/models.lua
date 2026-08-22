local M = {}

M.Presence = {}
M.Presence.__index = M.Presence

function M.Presence.new()
    local self = setmetatable({}, M.Presence)
    self.characterName = ""
    self.job = ""
    self.rank = ""
    self.nation = 0
    self.zone = ""
    self.isAnonymous = false
    self.timestamp = 0
    return self
end

function M.Presence:hasChanged(other)
    return self.characterName ~= other.characterName or
           self.job ~= other.job or
           self.rank ~= other.rank or
           self.nation ~= other.nation or
           self.zone ~= other.zone or
           self.isAnonymous ~= other.isAnonymous
end

function M.Presence:isValid()
    return self.characterName ~= "" and self.characterName ~= nil
end

M.FriendViewSettings = {}
M.FriendViewSettings.__index = M.FriendViewSettings

function M.FriendViewSettings.new()
    local self = setmetatable({}, M.FriendViewSettings)
    self.showJob = true
    self.showZone = false
    self.showNationRank = false
    self.showLastSeen = false
    return self
end

function M.FriendViewSettings:__eq(other)
    return self.showJob == other.showJob and
           self.showZone == other.showZone and
           self.showNationRank == other.showNationRank and
           self.showLastSeen == other.showLastSeen
end

M.HoverTooltipSettings = {}
M.HoverTooltipSettings.__index = M.HoverTooltipSettings

function M.HoverTooltipSettings.new()
    local self = setmetatable({}, M.HoverTooltipSettings)
    self.showJob = true
    self.showZone = true
    self.showNationRank = true
    self.showLastSeen = false
    self.showFriendedAs = true
    self.showRealm = false
    return self
end

function M.HoverTooltipSettings:__eq(other)
    return self.showJob == other.showJob and
           self.showZone == other.showZone and
           self.showNationRank == other.showNationRank and
           self.showLastSeen == other.showLastSeen and
           self.showFriendedAs == other.showFriendedAs and
           self.showRealm == other.showRealm
end

M.Color = {}
M.Color.__index = M.Color

function M.Color.new(r, g, b, a)
    local self = setmetatable({}, M.Color)
    self.r = r or 0.0
    self.g = g or 0.0
    self.b = b or 0.0
    self.a = a or 1.0
    return self
end

function M.Color:__eq(other)
    return self.r == other.r and
           self.g == other.g and
           self.b == other.b and
           self.a == other.a
end

M.Preferences = {}
M.Preferences.__index = M.Preferences

function M.Preferences.new()
    local self = setmetatable({}, M.Preferences)
    self.shareFriendsAcrossAlts = true
    self.mainFriendView = M.FriendViewSettings.new()
    self.mainHoverTooltip = M.HoverTooltipSettings.new()
    self.quickOnlineHoverTooltip = M.HoverTooltipSettings.new()
    self.debugMode = false
    self.shareJobWhenAnonymous = false
    self.showOnlineStatus = true
    self.shareLocation = true
    self.presenceStatus = "online"
    self.notificationDuration = 8.0
    -- Default notification position
    self.notificationPositionX = 10.0
    self.notificationPositionY = 15.0
    self.customCloseKeyCode = 0
    self.controllerCloseButton = 0x2000
    self.windowsLocked = false
    self.windowsPositionLocked = false
    self.useIconsForTabs = true
    self.tabIconTint = nil
    -- Individual tab icon colors (nil = use tabIconTint or default white)
    self.tabIconColors = {
        friends = nil,
        requests = nil,
        view = nil,
        privacy = nil,
        tags = nil,
        notifications = nil,
        themes = nil,
        help = nil
    }
    -- UI icon colors (lock, refresh, collapse, expand, discord, github, heart)
    self.uiIconColors = {
        lock = nil,
        unlock = nil,
        refresh = nil,
        collapse = nil,
        expand = nil,
        discord = nil,
        github = nil,
        heart = nil
    }
    self.notificationSoundsEnabled = true
    self.soundOnFriendOnline = true
    self.soundOnFriendRequest = true
    self.notificationSoundVolume = 0.6
    -- Notification background color (nil = use theme, otherwise {r, g, b, a})
    self.notificationBgColor = nil
    self.notificationShowTestPreview = false
    self.controllerLayout = 'xinput'
    self.flistBindButton = ''
    self.closeBindButton = ''
    self.flBindButton = ''
    -- Notification mute settings
    self.dontSendNotificationsGlobal = false
    self.mutedFriends = {}  -- Table keyed by friendAccountId
    self.muteTestFriendOnline = false
    self.muteTestFriendRequest = false
    return self
end

function M.Preferences:__eq(other)
    return self.shareFriendsAcrossAlts == other.shareFriendsAcrossAlts and
           self.mainFriendView == other.mainFriendView and
           self.mainHoverTooltip == other.mainHoverTooltip and
           self.quickOnlineHoverTooltip == other.quickOnlineHoverTooltip and
           self.debugMode == other.debugMode and
           self.mailCacheEnabled == other.mailCacheEnabled and
           self.maxCachedMessagesPerMailbox == other.maxCachedMessagesPerMailbox and
           self.overwriteNotesOnUpload == other.overwriteNotesOnUpload and
           self.overwriteNotesOnDownload == other.overwriteNotesOnDownload and
           self.shareJobWhenAnonymous == other.shareJobWhenAnonymous and
           self.showOnlineStatus == other.showOnlineStatus and
           self.shareLocation == other.shareLocation and
           self.notificationDuration == other.notificationDuration and
           self.notificationPositionX == other.notificationPositionX and
           self.notificationPositionY == other.notificationPositionY and
           self.customCloseKeyCode == other.customCloseKeyCode and
           self.controllerCloseButton == other.controllerCloseButton and
           self.windowsLocked == other.windowsLocked and
           self.notificationSoundsEnabled == other.notificationSoundsEnabled and
           self.soundOnFriendOnline == other.soundOnFriendOnline and
           self.soundOnFriendRequest == other.soundOnFriendRequest and
           self.notificationSoundVolume == other.notificationSoundVolume and
           self.controllerLayout == other.controllerLayout and
           self.flistBindButton == other.flistBindButton and
           self.closeBindButton == other.closeBindButton and
           self.flBindButton == other.flBindButton
end

M.BuiltInTheme = {
    Default = -2,
    FFXIClassic = 0,
    ModernDark = 1,
    GreenNature = 2,
    PurpleMystic = 3,
    Ashita = 4
}

-- Maximum index for built-in themes (update this when adding new themes)
M.MAX_BUILTIN_THEME_INDEX = 4

-- Built-in theme names in order (index 0 to MAX_BUILTIN_THEME_INDEX)
M.BUILTIN_THEME_NAMES = {"Classic", "Modern Dark", "Green Nature", "Purple Mystic", "Ashita"}

M.CustomTheme = {}
M.CustomTheme.__index = M.CustomTheme

function M.CustomTheme.new()
    local self = setmetatable({}, M.CustomTheme)
    self.name = ""
    self.windowBgColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.childBgColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.frameBgColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.frameBgHovered = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.frameBgActive = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.titleBg = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.titleBgActive = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.titleBgCollapsed = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.buttonColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.buttonHoverColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.buttonActiveColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.separatorColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.separatorHovered = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.separatorActive = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.scrollbarBg = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.scrollbarGrab = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.scrollbarGrabHovered = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.scrollbarGrabActive = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.checkMark = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.sliderGrab = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.sliderGrabActive = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.header = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.headerHovered = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.headerActive = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.textColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.textDisabled = M.Color.new(0.0, 0.0, 0.0, 1.0)
    self.tableBgColor = M.Color.new(0.0, 0.0, 0.0, 1.0)
    return self
end

function M.getBuiltInThemeName(theme)
    if theme == M.BuiltInTheme.Default then
        return "Default (No Theme)"
    elseif theme == M.BuiltInTheme.FFXIClassic then
        return "Classic"
    elseif theme == M.BuiltInTheme.ModernDark then
        return "Modern Dark"
    elseif theme == M.BuiltInTheme.GreenNature then
        return "Green Nature"
    elseif theme == M.BuiltInTheme.PurpleMystic then
        return "Purple Mystic"
    elseif theme == M.BuiltInTheme.Ashita then
        return "Ashita"
    else
        return "Unknown"
    end
end

M.MailFolder = {
    Inbox = 0,
    Sent = 1
}

M.MailMessage = {}
M.MailMessage.__index = M.MailMessage

function M.MailMessage.new()
    local self = setmetatable({}, M.MailMessage)
    self.messageId = ""
    self.fromUserId = ""
    self.toUserId = ""
    self.subject = ""
    self.body = ""
    self.createdAt = 0
    self.readAt = 0
    self.isRead = false
    return self
end

function M.MailMessage:isUnread()
    return not self.isRead
end

function M.MailMessage:__eq(other)
    return self.messageId == other.messageId
end

return M

