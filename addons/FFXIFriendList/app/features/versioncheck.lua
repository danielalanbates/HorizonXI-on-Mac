--[[
* app/features/versioncheck.lua
* Checks for addon updates on startup
]]--

local Endpoints = require('protocol.Endpoints')
local Envelope = require('protocol.Envelope')
local VersionCore = require('core.versioncore')

local M = {}

M.VersionCheck = {}
M.VersionCheck.__index = M.VersionCheck

function M.VersionCheck.new(deps)
    local self = setmetatable({}, M.VersionCheck)
    self.deps = deps
    self.checked = false
    self.latestVersion = nil
    return self
end

-- Check for updates (called once after character is detected)
function M.VersionCheck:checkForUpdates()
    if self.checked then
        return
    end
    
    self.checked = true
    
    local baseUrl = self.deps.connection:getBaseUrl()
    if not baseUrl or baseUrl == "" then
        return
    end
    
    local url = baseUrl .. Endpoints.VERSION
    
    self.deps.net.request({
        url = url,
        method = "GET",
        callback = function(success, response)
            if not success then
                return
            end
            
            local ok, envelope = Envelope.decode(response)
            if not ok or not envelope or not envelope.data then
                return
            end
            
            local data = envelope.data
            if not data.latestAddonVersion then
                return
            end
            
            self.latestVersion = data.latestAddonVersion
            
            -- Don't check if server returned 'unknown'
            if self.latestVersion == 'unknown' then
                return
            end
            
            -- Parse current and latest versions
            local currentVersion = VersionCore.Version.parse(VersionCore.ADDON_VERSION)
            local latestVersion = VersionCore.Version.parse(self.latestVersion)
            
            if not currentVersion or not latestVersion then
                return
            end
            
            -- Check if outdated
            if currentVersion:isOutdated(latestVersion) then
                self:notifyOutdated(currentVersion:toString(), latestVersion:toString())
            end
        end
    })
end

-- Notify user that addon is outdated
function M.VersionCheck:notifyOutdated(current, latest)
    if not self.deps.logger or not self.deps.logger.echo then
        return
    end
    
    self.deps.logger.echo("================================================")
    self.deps.logger.echo("  FFXI Friend List Update Available!")
    self.deps.logger.echo("  Current: " .. current .. " -> Latest: " .. latest)
    self.deps.logger.echo("  Download: github.com/Tanyrus/FFXIFriendList/releases")
    self.deps.logger.echo("================================================")
end

return M
