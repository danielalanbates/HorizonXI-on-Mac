local M = {}

-- Addon version constant
M.ADDON_VERSION = "1.0.0"

M.Version = {}
M.Version.__index = M.Version

function M.Version.new(major, minor, patch, prerelease, build)
    local self = setmetatable({}, M.Version)
    self.major = major or 0
    self.minor = minor or 0
    self.patch = patch or 0
    self.prerelease = prerelease or ""
    self.build = build or ""
    return self
end

function M.Version.parse(versionStr)
    if not versionStr or versionStr == "" then
        return nil
    end
    
    local lower = string.lower(versionStr)
    if lower == "dev" or lower == "unknown" or lower == "0.0.0-dev" then
        return nil
    end
    
    local str = versionStr
    if string.len(str) > 0 and (string.sub(str, 1, 1) == "v" or string.sub(str, 1, 1) == "V") then
        str = string.sub(str, 2)
    end
    
    local versionPart = str
    local buildPart = ""
    local plusPos = string.find(str, "+")
    if plusPos then
        versionPart = string.sub(str, 1, plusPos - 1)
        buildPart = string.sub(str, plusPos + 1)
    end
    
    local baseVersion = versionPart
    local prereleasePart = ""
    local dashPos = string.find(versionPart, "-")
    if dashPos then
        baseVersion = string.sub(versionPart, 1, dashPos - 1)
        prereleasePart = string.sub(versionPart, dashPos + 1)
    end
    
    local parts = {}
    for part in string.gmatch(baseVersion, "[^.]+") do
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
    
    return M.Version.new(major, minor, patch, prereleasePart, buildPart)
end

function M.Version:toString()
    local result = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease and self.prerelease ~= "" then
        result = result .. "-" .. self.prerelease
    end
    if self.build and self.build ~= "" then
        result = result .. "+" .. self.build
    end
    return result
end

function M.Version:isValid()
    return self.major >= 0 and self.minor >= 0 and self.patch >= 0
end

function M.Version:isDevVersion()
    if not self:isValid() then
        return true
    end
    if self.prerelease and string.find(self.prerelease, "dev") then
        return true
    end
    return false
end

function M.Version:__eq(other)
    return self.major == other.major and
           self.minor == other.minor and
           self.patch == other.patch and
           self.prerelease == other.prerelease
end

function M.Version:__lt(other)
    if self.major ~= other.major then
        return self.major < other.major
    end
    if self.minor ~= other.minor then
        return self.minor < other.minor
    end
    if self.patch ~= other.patch then
        return self.patch < other.patch
    end
    
    if (not self.prerelease or self.prerelease == "") and (other.prerelease and other.prerelease ~= "") then
        return false
    end
    if (self.prerelease and self.prerelease ~= "") and (not other.prerelease or other.prerelease == "") then
        return true
    end
    if (not self.prerelease or self.prerelease == "") and (not other.prerelease or other.prerelease == "") then
        return false
    end
    
    return self.prerelease < other.prerelease
end

function M.Version:__le(other)
    return not (other < self)
end

function M.Version:__gt(other)
    return other < self
end

function M.Version:__ge(other)
    return not (self < other)
end

function M.Version:isOutdated(latest)
    return self < latest
end

function M.parseVersion(versionStr)
    local v = M.Version.parse(versionStr)
    if not v then
        error("Invalid version string: " .. tostring(versionStr))
    end
    return v
end

function M.isValidVersionString(versionStr)
    local v = M.Version.parse(versionStr)
    return v ~= nil
end

return M

