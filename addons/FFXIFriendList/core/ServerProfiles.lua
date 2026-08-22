-- ServerProfiles.lua
-- Server profiles fetched from /api/servers at startup
-- No fallback - if API is unreachable, user must select manually or request server be added

local ServerConfig = require("core.ServerConfig")

local M = {}

-- Active profiles - populated from server API via setProfiles()
-- Empty until fetched from /api/servers
M.profiles = {}

-- Whether profiles have been successfully loaded from API
M.loaded = false

-- Error message if fetch failed
M.loadError = nil

-- Set profiles from server API response
-- @param serverList Array of server objects from /api/servers
-- @return success boolean
function M.setProfiles(serverList)
    if not serverList or #serverList == 0 then
        M.loaded = false
        M.loadError = "No servers returned from API"
        return false
    end
    
    local profiles = {}
    for _, server in ipairs(serverList) do
        if server.id and server.name then
            table.insert(profiles, {
                id = server.id,
                name = server.name,
                hostPatterns = server.hostPatterns or {},
                apiBaseUrl = ServerConfig.DEFAULT_SERVER_URL,
                region = server.region,
                status = server.status,
            })
        end
    end
    
    if #profiles > 0 then
        M.profiles = profiles
        M.loaded = true
        M.loadError = nil
        return true
    else
        M.loaded = false
        M.loadError = "No valid server profiles in response"
        return false
    end
end

-- Set load error (called when API fetch fails)
function M.setLoadError(errorMsg)
    M.loaded = false
    M.loadError = errorMsg or "Failed to fetch server list"
end

-- Check if profiles are loaded
function M.isLoaded()
    return M.loaded
end

-- Get load error message
function M.getLoadError()
    return M.loadError
end

-- Find a server profile by matching host string against patterns
-- @param hostString The host string to match (from boot command or log)
-- @return profile, matchedPattern or nil, nil if no match
function M.findByHost(hostString)
    if not hostString or hostString == "" then
        return nil, nil
    end
    
    local lowerHost = string.lower(hostString)
    
    for _, profile in ipairs(M.profiles) do
        for _, pattern in ipairs(profile.hostPatterns or {}) do
            -- Case-insensitive substring match
            if string.find(lowerHost, string.lower(pattern), 1, true) then
                return profile, pattern
            end
        end
    end
    
    return nil, nil
end

-- Find a server profile by ID
-- @param id Server ID (e.g., "horizon")
-- @return profile or nil
function M.findById(id)
    if not id or id == "" then
        return nil
    end
    
    local lowerId = string.lower(id)
    
    for _, profile in ipairs(M.profiles) do
        if string.lower(profile.id) == lowerId then
            return profile
        end
    end
    
    return nil
end

-- Get all active profiles
-- @return Array of profiles (empty if not loaded)
function M.getAll()
    return M.profiles
end

-- Get count of loaded profiles
function M.getCount()
    return #M.profiles
end

-- Get profile names for display
-- @return Array of {id, name} pairs
function M.getNames()
    local names = {}
    for _, profile in ipairs(M.profiles) do
        table.insert(names, { id = profile.id, name = profile.name })
    end
    return names
end

return M
