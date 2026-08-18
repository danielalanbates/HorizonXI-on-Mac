local Models = require("core.models")
local Envelope = require("protocol.Envelope")
local Endpoints = require("protocol.Endpoints")
local UIConstants = require("core.UIConstants")
local Settings = require("libs.settings")

local M = {}

M.Preferences = {}
M.Preferences.__index = M.Preferences

function M.Preferences.new(deps)
    local self = setmetatable({}, M.Preferences)
    self.deps = deps or {}
    
    self.prefs = Models.Preferences.new()
    self.lastUpdatedAt = nil
    
    return self
end

function M.Preferences:getState()
    return {
        prefs = self.prefs,
        lastUpdatedAt = self.lastUpdatedAt
    }
end

local function getTime(self)
    if self.deps.time then
        return self.deps.time()
    end
    return os.time() * 1000
end

-- Helper to safely get a value with a default
local function getVal(val, defaultVal)
    if val == nil then return defaultVal end
    return val
end

function M.Preferences:load()
    -- Use Settings module (Lua table persistence - preserves types)
    local data = Settings.get("data")
    if not data or type(data) ~= "table" then
        return false
    end
    
    local prefs = data.preferences
    if not prefs or type(prefs) ~= "table" then
        return false
    end
    
    -- Load from settings (types are preserved as Lua tables)
    self.prefs.shareFriendsAcrossAlts = getVal(prefs.shareFriendsAcrossAlts, true)
    self.prefs.mainFriendView.showJob = getVal(prefs.mainShowJob, true)
    self.prefs.mainFriendView.showZone = getVal(prefs.mainShowZone, false)
    self.prefs.mainFriendView.showNationRank = getVal(prefs.mainShowNationRank, false)
    self.prefs.mainFriendView.showLastSeen = getVal(prefs.mainShowLastSeen, false)
    self.prefs.mainHoverTooltip.showJob = getVal(prefs.mainHoverShowJob, true)
    self.prefs.mainHoverTooltip.showZone = getVal(prefs.mainHoverShowZone, true)
    self.prefs.mainHoverTooltip.showNationRank = getVal(prefs.mainHoverShowNationRank, true)
    self.prefs.mainHoverTooltip.showLastSeen = getVal(prefs.mainHoverShowLastSeen, false)
    self.prefs.mainHoverTooltip.showFriendedAs = getVal(prefs.mainHoverShowFriendedAs, true)
    self.prefs.mainHoverTooltip.showRealm = getVal(prefs.mainHoverShowRealm, false)
    self.prefs.quickOnlineHoverTooltip.showJob = getVal(prefs.quickHoverShowJob, true)
    self.prefs.quickOnlineHoverTooltip.showZone = getVal(prefs.quickHoverShowZone, true)
    self.prefs.quickOnlineHoverTooltip.showNationRank = getVal(prefs.quickHoverShowNationRank, true)
    self.prefs.quickOnlineHoverTooltip.showLastSeen = getVal(prefs.quickHoverShowLastSeen, false)
    self.prefs.quickOnlineHoverTooltip.showFriendedAs = getVal(prefs.quickHoverShowFriendedAs, true)
    self.prefs.quickOnlineHoverTooltip.showRealm = getVal(prefs.quickHoverShowRealm, false)
    self.prefs.debugMode = getVal(prefs.debugMode, false)
    self.prefs.shareJobWhenAnonymous = getVal(prefs.shareJobWhenAnonymous, false)
    self.prefs.showOnlineStatus = getVal(prefs.showOnlineStatus, true)
    self.prefs.shareLocation = getVal(prefs.shareLocation, true)
    self.prefs.presenceStatus = getVal(prefs.presenceStatus, "online")
    self.prefs.notificationDuration = getVal(prefs.notificationDuration, 8.0)
    local DEFAULT_POS_X = UIConstants.NOTIFICATION_POSITION[1]
    local DEFAULT_POS_Y = UIConstants.NOTIFICATION_POSITION[2]
    local posX = prefs.notificationPositionX
    local posY = prefs.notificationPositionY
    self.prefs.notificationPositionX = (posX == nil or posX < 0) and DEFAULT_POS_X or posX
    self.prefs.notificationPositionY = (posY == nil or posY < 0) and DEFAULT_POS_Y or posY
    self.prefs.customCloseKeyCode = getVal(prefs.customCloseKeyCode, 0)
    self.prefs.controllerCloseButton = getVal(prefs.controllerCloseButton, UIConstants.CONTROLLER_CLOSE_BUTTON)
    self.prefs.windowsLocked = getVal(prefs.windowsLocked, false)
    self.prefs.windowsPositionLocked = getVal(prefs.windowsPositionLocked, false)
    self.prefs.useIconsForTabs = getVal(prefs.useIconsForTabs, true)
    -- Tab icon tint color (nil = use default white)
    if prefs.tabIconTint and type(prefs.tabIconTint) == "table" then
        self.prefs.tabIconTint = {
            r = prefs.tabIconTint.r or 1.0,
            g = prefs.tabIconTint.g or 1.0,
            b = prefs.tabIconTint.b or 1.0,
            a = prefs.tabIconTint.a or 1.0
        }
    else
        self.prefs.tabIconTint = nil
    end
    -- Individual tab icon colors
    if prefs.tabIconColors and type(prefs.tabIconColors) == "table" then
        for key, colorData in pairs(prefs.tabIconColors) do
            if colorData and type(colorData) == "table" then
                self.prefs.tabIconColors[key] = {
                    r = colorData.r or 1.0,
                    g = colorData.g or 1.0,
                    b = colorData.b or 1.0,
                    a = colorData.a or 1.0
                }
            end
        end
    end
    -- UI icon colors
    if prefs.uiIconColors and type(prefs.uiIconColors) == "table" then
        for key, colorData in pairs(prefs.uiIconColors) do
            if colorData and type(colorData) == "table" then
                self.prefs.uiIconColors[key] = {
                    r = colorData.r or 1.0,
                    g = colorData.g or 1.0,
                    b = colorData.b or 1.0,
                    a = colorData.a or 1.0
                }
            end
        end
    end
    self.prefs.notificationSoundsEnabled = getVal(prefs.notificationSoundsEnabled, true)
    self.prefs.soundOnFriendOnline = getVal(prefs.soundOnFriendOnline, true)
    self.prefs.soundOnFriendRequest = getVal(prefs.soundOnFriendRequest, true)
    self.prefs.notificationSoundVolume = getVal(prefs.notificationSoundVolume, 0.6)
    self.prefs.notificationShowTestPreview = getVal(prefs.notificationShowTestPreview, false)
    self.prefs.muteTestFriendOnline = getVal(prefs.muteTestFriendOnline, false)
    self.prefs.muteTestFriendRequest = getVal(prefs.muteTestFriendRequest, false)
    -- Notification background color (nil = use theme, otherwise {r, g, b, a})
    if prefs.notificationBgColor and type(prefs.notificationBgColor) == "table" then
        self.prefs.notificationBgColor = {
            r = prefs.notificationBgColor.r or 0.0,
            g = prefs.notificationBgColor.g or 0.0,
            b = prefs.notificationBgColor.b or 0.0,
            a = prefs.notificationBgColor.a or 1.0
        }
    else
        self.prefs.notificationBgColor = nil
    end
    self.prefs.controllerLayout = getVal(prefs.controllerLayout, 'xinput')
    self.prefs.flistBindButton = getVal(prefs.flistBindButton, '')
    self.prefs.closeBindButton = getVal(prefs.closeBindButton, '')
    self.prefs.flBindButton = getVal(prefs.flBindButton, '')
    -- Notification mute settings
    self.prefs.dontSendNotificationsGlobal = getVal(prefs.dontSendNotificationsGlobal, false)
    if prefs.mutedFriends and type(prefs.mutedFriends) == "table" then
        self.prefs.mutedFriends = prefs.mutedFriends
    else
        self.prefs.mutedFriends = {}
    end
    return true
end

function M.Preferences:save()
    -- Use Settings module (Lua table persistence - preserves types)
    local prefsData = {
        shareFriendsAcrossAlts = self.prefs.shareFriendsAcrossAlts,
        mainShowJob = self.prefs.mainFriendView.showJob,
        mainShowZone = self.prefs.mainFriendView.showZone,
        mainShowNationRank = self.prefs.mainFriendView.showNationRank,
        mainShowLastSeen = self.prefs.mainFriendView.showLastSeen,
        mainHoverShowJob = self.prefs.mainHoverTooltip.showJob,
        mainHoverShowZone = self.prefs.mainHoverTooltip.showZone,
        mainHoverShowNationRank = self.prefs.mainHoverTooltip.showNationRank,
        mainHoverShowLastSeen = self.prefs.mainHoverTooltip.showLastSeen,
        mainHoverShowFriendedAs = self.prefs.mainHoverTooltip.showFriendedAs,
        mainHoverShowRealm = self.prefs.mainHoverTooltip.showRealm,
        quickHoverShowJob = self.prefs.quickOnlineHoverTooltip.showJob,
        quickHoverShowZone = self.prefs.quickOnlineHoverTooltip.showZone,
        quickHoverShowNationRank = self.prefs.quickOnlineHoverTooltip.showNationRank,
        quickHoverShowLastSeen = self.prefs.quickOnlineHoverTooltip.showLastSeen,
        quickHoverShowFriendedAs = self.prefs.quickOnlineHoverTooltip.showFriendedAs,
        quickHoverShowRealm = self.prefs.quickOnlineHoverTooltip.showRealm,
        debugMode = self.prefs.debugMode,
        shareJobWhenAnonymous = self.prefs.shareJobWhenAnonymous,
        showOnlineStatus = self.prefs.showOnlineStatus,
        shareLocation = self.prefs.shareLocation,
        presenceStatus = self.prefs.presenceStatus,
        notificationDuration = self.prefs.notificationDuration,
        notificationPositionX = self.prefs.notificationPositionX,
        notificationPositionY = self.prefs.notificationPositionY,
        customCloseKeyCode = self.prefs.customCloseKeyCode,
        controllerCloseButton = self.prefs.controllerCloseButton,
        windowsLocked = self.prefs.windowsLocked,
        windowsPositionLocked = self.prefs.windowsPositionLocked,
        useIconsForTabs = self.prefs.useIconsForTabs,
        tabIconTint = self.prefs.tabIconTint,
        tabIconColors = self.prefs.tabIconColors,
        uiIconColors = self.prefs.uiIconColors,
        notificationSoundsEnabled = self.prefs.notificationSoundsEnabled,
        soundOnFriendOnline = self.prefs.soundOnFriendOnline,
        soundOnFriendRequest = self.prefs.soundOnFriendRequest,
        notificationSoundVolume = self.prefs.notificationSoundVolume,
        notificationShowTestPreview = self.prefs.notificationShowTestPreview,
        muteTestFriendOnline = self.prefs.muteTestFriendOnline,
        muteTestFriendRequest = self.prefs.muteTestFriendRequest,
        notificationBgColor = self.prefs.notificationBgColor,
        controllerLayout = self.prefs.controllerLayout,
        flistBindButton = self.prefs.flistBindButton,
        closeBindButton = self.prefs.closeBindButton,
        flBindButton = self.prefs.flBindButton,
        dontSendNotificationsGlobal = self.prefs.dontSendNotificationsGlobal,
        mutedFriends = self.prefs.mutedFriends
    }
    
    -- Update preferences in the data section (preserves apiKeys, serverSelection, etc.)
    local data = Settings.get("data") or {}
    data.preferences = data.preferences or {}
    for k, v in pairs(prefsData) do
        data.preferences[k] = v
    end
    Settings.save()
    
    self.lastUpdatedAt = getTime(self)
    return true
end

function M.Preferences:getPrefs()
    return self.prefs
end

function M.Preferences:setPref(key, value)
    -- Check if key exists in prefs (even if value is nil)
    -- Use rawget to check for key existence without triggering __index
    if rawget(self.prefs, key) ~= nil or 
       key == "notificationBgColor" or  -- Allow notificationBgColor even if nil
       key == "notificationShowTestPreview" or  -- Allow notificationShowTestPreview
       (self.prefs[key] == nil and key ~= nil) then  -- Key exists but value is nil
        self.prefs[key] = value
        return true
    end
    -- Fallback: if it's a known preference field, allow setting it
    local knownPrefs = {
        notificationBgColor = true,
        notificationShowTestPreview = true,
        muteTestFriendOnline = true,
        muteTestFriendRequest = true,
        -- Add other optional fields here if needed
    }
    if knownPrefs[key] then
        self.prefs[key] = value
        return true
    end
    return false
end

function M.Preferences:syncToServer(onComplete)
    if not self.deps.net or not self.deps.connection then
        if onComplete then onComplete(false) end
        return false
    end
    
    if not self.deps.connection:isConnected() then
        if onComplete then onComplete(false) end
        return false
    end
    
    -- Use new server endpoint: PATCH /api/preferences
    local url = self.deps.connection:getBaseUrl() .. Endpoints.PREFERENCES
    
    local characterName = ""
    if self.deps.connection.getCharacterName then
        characterName = self.deps.connection:getCharacterName()
    elseif self.deps.connection.lastCharacterName then
        characterName = self.deps.connection.lastCharacterName
    end
    
    local headers = self.deps.connection:getHeaders(characterName)
    
    -- New server expects: { presenceStatus?, shareLocation?, shareJobWhenAnonymous? }
    local RequestEncoder = require("protocol.Encoding.RequestEncoder")
    local body = RequestEncoder.encodeUpdatePreferences({
        presenceStatus = self.prefs.presenceStatus,
        shareLocation = self.prefs.shareLocation,
        shareJobWhenAnonymous = self.prefs.shareJobWhenAnonymous
    })
    
    local selfRef = self
    
    self.deps.net.request({
        url = url,
        method = "PATCH",
        headers = headers,
        body = body,
        callback = function(success, response)
            local syncSuccess = false
            if success then
                -- Use new envelope format: { success, data, timestamp }
                local ok, result = Envelope.decode(response)
                if ok then
                    syncSuccess = true
                end
            end
            
            if onComplete then
                onComplete(syncSuccess)
            end
        end
    })
    
    return true
end

-- Update a single preference and sync to server
-- This can be called before character detection completes
function M.Preferences:updatePreference(key, value, onComplete)
    if not self:setPref(key, value) then
        if onComplete then onComplete(false) end
        return false
    end
    
    -- If connection is available, sync to server
    -- Otherwise just update locally (will sync when connection is ready)
    if self.deps.connection and self.deps.connection.apiKey and self.deps.connection.apiKey ~= "" then
        return self:syncToServer(onComplete)
    end
    
    if onComplete then onComplete(true) end
    return true
end

function M.Preferences:refresh()
    if not self.deps.net or not self.deps.connection then
        return false
    end
    
    if not self.deps.connection:isConnected() then
        return false
    end
    
    -- Use new server endpoint: GET /api/preferences
    local url = self.deps.connection:getBaseUrl() .. Endpoints.PREFERENCES
    
    local characterName = ""
    if self.deps.connection.getCharacterName then
        characterName = self.deps.connection:getCharacterName()
    elseif self.deps.connection.lastCharacterName then
        characterName = self.deps.connection.lastCharacterName
    end
    
    local headers = self.deps.connection:getHeaders(characterName)
    
    local requestId = self.deps.net.request({
        url = url,
        method = "GET",
        headers = headers,
        body = "",
        callback = function(success, response)
            if success then
                -- Use new envelope format: { success, data, timestamp }
                local ok, result = Envelope.decode(response)
                if ok then
                    -- New server returns PreferencesData directly in data
                    local data = result.data or {}
                    
                    if data.presenceStatus ~= nil then
                        self.prefs.presenceStatus = data.presenceStatus
                        self.prefs.showOnlineStatus = data.presenceStatus ~= "invisible"
                    end
                    if data.shareLocation ~= nil then
                        self.prefs.shareLocation = data.shareLocation
                    end
                    if data.shareJobWhenAnonymous ~= nil then
                        self.prefs.shareJobWhenAnonymous = data.shareJobWhenAnonymous
                    end
                    
                    self:save()
                else
                    if self.deps.logger and self.deps.logger.warn then
                        self.deps.logger.warn("[Preferences] Refresh: Failed to decode")
                    end
                end
            else
                if self.deps.logger and self.deps.logger.warn then
                    self.deps.logger.warn(string.format("[Preferences] Refresh: Request failed: %s", tostring(response)))
                end
            end
        end
    })
    
    return requestId ~= nil
end

-- Check if a friend is muted by account ID
function M.Preferences:isFriendMuted(friendAccountId)
    if not friendAccountId then return false end
    return self.prefs.mutedFriends[friendAccountId] == true
end

-- Toggle mute status for a friend by account ID
function M.Preferences:toggleFriendMuted(friendAccountId)
    if not friendAccountId then return false end
    local currentlyMuted = self.prefs.mutedFriends[friendAccountId] == true
    self.prefs.mutedFriends[friendAccountId] = not currentlyMuted
    self:save()
    return not currentlyMuted  -- Return new mute status
end

-- Set mute status for a friend by account ID
function M.Preferences:setFriendMuted(friendAccountId, muted)
    if not friendAccountId then return false end
    self.prefs.mutedFriends[friendAccountId] = muted == true
    self:save()
    return self.prefs.mutedFriends[friendAccountId]
end

-- Clear mute entry for a friend by account ID
function M.Preferences:clearFriendMute(friendAccountId)
    if not friendAccountId then return false end
    if self.prefs.mutedFriends[friendAccountId] ~= nil then
        self.prefs.mutedFriends[friendAccountId] = nil
        self:save()
        return true
    end
    return false
end

return M
