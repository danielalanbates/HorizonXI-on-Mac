-- ProtocolVersion.lua
-- Protocol version parsing, comparison, and compatibility checking

local PROTOCOL_VERSION = "2.0.0"

-- Version table with methods
local Version = {}
Version.__index = Version

function Version.new(major, minor, patch)
    local self = setmetatable({}, Version)
    self.major = major or 1
    self.minor = minor or 0
    self.patch = patch or 0
    return self
end

function Version.parse(versionStr)
    if not versionStr or versionStr == "" then
        return nil
    end
    
    local parts = {}
    for part in versionStr:gmatch("[^.]+") do
        table.insert(parts, part)
    end
    
    if #parts ~= 3 then
        return nil
    end
    
    local major = tonumber(parts[1])
    local minor = tonumber(parts[2])
    local patch = tonumber(parts[3])
    
    if not major or not minor or not patch then
        return nil
    end
    
    return Version.new(major, minor, patch)
end

function Version:toString()
    return string.format("%d.%d.%d", self.major, self.minor, self.patch)
end

function Version:__eq(other)
    return self.major == other.major and self.minor == other.minor and self.patch == other.patch
end

function Version:__lt(other)
    if self.major ~= other.major then
        return self.major < other.major
    end
    if self.minor ~= other.minor then
        return self.minor < other.minor
    end
    return self.patch < other.patch
end

function Version:__le(other)
    return self == other or self < other
end

function Version:__gt(other)
    return other < self
end

function Version:__ge(other)
    return other <= self
end

function Version:isCompatibleWith(other)
    return self.major == other.major
end

-- Module exports
local M = {}

M.PROTOCOL_VERSION = PROTOCOL_VERSION
M.Version = Version

function M.getCurrentVersion()
    return Version.parse(PROTOCOL_VERSION)
end

function M.isValidVersion(versionStr)
    return Version.parse(versionStr) ~= nil
end

return M

