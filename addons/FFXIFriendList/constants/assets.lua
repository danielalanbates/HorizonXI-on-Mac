-- constants/assets.lua
-- Asset filenames: sounds, icons, textures
-- Centralized to avoid hardcoded filenames scattered across modules
--
-- Usage: local Assets = require("constants.assets")
--        SoundPlayer.playSound(Assets.SOUNDS.FRIEND_ONLINE, volume)

local M = {}

--------------------------------------------------------------------------------
-- Sound Filenames (relative to assets/sounds/)
--------------------------------------------------------------------------------

M.SOUNDS = {
    FRIEND_ONLINE = "online.wav",
    FRIEND_REQUEST = "friend-request.wav",
}

--------------------------------------------------------------------------------
-- Icon Names (used with icons.lua GetIcon)
-- These map to filenames in assets/icons/ (without .png extension)
--------------------------------------------------------------------------------

M.ICONS = {
    -- Status icons
    ONLINE = "online",
    OFFLINE = "offline",
    PENDING = "friend_request",
    AWAY = "away",
    
    -- Lock icons
    LOCK = "lock_icon",
    UNLOCK = "unlock_icon",
    
    -- Social icons
    DISCORD = "discord",
    GITHUB = "github",
    HEART = "heart",
    FRIEND_REQUEST = "friend_request",
    
    -- Nation icons
    NATION_SANDORIA = "sandy_icon",
    NATION_BASTOK = "bastok_icon",
    NATION_WINDURST = "windy_icon",
    
    -- Tab icons
    TAB_FRIENDS = "friends",
    TAB_REQUESTS = "requests",
    TAB_NOTIFICATIONS = "notifications",
    TAB_PRIVACY = "privacy",
    TAB_VIEW = "view",
    TAB_TAGS = "tags",
    TAB_HELP = "help",
    TAB_THEMES = "theme",
    
    -- UI action icons
    REFRESH = "refresh",
    COLLAPSE = "collapse",
    EXPAND = "expand",
}

--------------------------------------------------------------------------------
-- Asset Paths (subdirectories under addon root)
--------------------------------------------------------------------------------

M.PATHS = {
    ICONS = "assets/icons",
    SOUNDS = "assets/sounds",
    CUSTOM_IMAGES = "images",   -- User override folder
    CUSTOM_SOUNDS = "sounds",   -- User override folder
}

--------------------------------------------------------------------------------
-- File Extensions
--------------------------------------------------------------------------------

M.EXTENSIONS = {
    IMAGE = ".png",
    SOUND = ".wav",
}

return M
