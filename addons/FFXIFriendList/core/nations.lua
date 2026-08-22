-- core/nations.lua
-- Canonical nation display mapper
-- Handles nation ID -> display string and icon name mapping
-- Supports both numeric IDs (from game) and string values (from server)

local M = {}

-- Nation display names
M.DISPLAY_NAMES = {
    -- Numeric keys (from FFXI game API)
    [0] = "San d'Oria",
    [1] = "Bastok",
    [2] = "Windurst",
    
    -- String keys (from server - lowercase for case-insensitive lookup)
    ["san d'oria"] = "San d'Oria",
    ["sandoria"] = "San d'Oria",
    ["sandy"] = "San d'Oria",
    ["bastok"] = "Bastok",
    ["windurst"] = "Windurst",
    ["windy"] = "Windurst",
}

-- Nation icon names (for icons.RenderIcon)
M.ICON_NAMES = {
    -- Numeric keys
    [0] = "nation_sandoria",
    [1] = "nation_bastok",
    [2] = "nation_windurst",
    
    -- String keys (lowercase for case-insensitive lookup)
    ["san d'oria"] = "nation_sandoria",
    ["sandoria"] = "nation_sandoria",
    ["sandy"] = "nation_sandoria",
    ["bastok"] = "nation_bastok",
    ["windurst"] = "nation_windurst",
    ["windy"] = "nation_windurst",
}

-- Display text for anonymous/unknown nation
M.ANONYMOUS_TEXT = "Anonymous"
M.UNKNOWN_TEXT = "Unknown"

--- Get the display name for a nation value
-- @param nationValue number|string|nil The nation value (ID or string)
-- @param defaultIfUnknown string Optional default text if unknown (default: "Anonymous")
-- @return string The display name
function M.getDisplayName(nationValue, defaultIfUnknown)
    defaultIfUnknown = defaultIfUnknown or M.ANONYMOUS_TEXT
    
    if nationValue == nil then
        return defaultIfUnknown
    end
    
    -- Direct numeric lookup
    if type(nationValue) == "number" then
        local name = M.DISPLAY_NAMES[nationValue]
        return name or defaultIfUnknown
    end
    
    -- String lookup (case-insensitive)
    if type(nationValue) == "string" then
        local lower = string.lower(nationValue)
        local name = M.DISPLAY_NAMES[lower]
        if name then
            return name
        end
        
        -- If the string is already a valid nation name, return it capitalized
        if lower == "san d'oria" or lower == "bastok" or lower == "windurst" then
            return M.DISPLAY_NAMES[lower]
        end
        
        -- Check if the original string looks like a valid nation name (case-insensitive match)
        for key, displayName in pairs(M.DISPLAY_NAMES) do
            if type(key) == "string" and string.lower(displayName) == lower then
                return displayName
            end
        end
        
        -- If it's a non-empty string we don't recognize, return as-is (might be localized)
        if nationValue ~= "" then
            return nationValue
        end
    end
    
    return defaultIfUnknown
end

--- Get the icon name for a nation value
-- @param nationValue number|string|nil The nation value (ID or string)
-- @return string|nil The icon name, or nil if unknown/anonymous
function M.getIconName(nationValue)
    if nationValue == nil then
        return nil
    end
    
    -- Direct numeric lookup
    if type(nationValue) == "number" then
        return M.ICON_NAMES[nationValue]
    end
    
    -- String lookup (case-insensitive)
    if type(nationValue) == "string" and nationValue ~= "" then
        local lower = string.lower(nationValue)
        return M.ICON_NAMES[lower]
    end
    
    return nil
end

--- Check if a nation value represents a known nation
-- @param nationValue number|string|nil The nation value
-- @return boolean True if the nation is known and valid
function M.isKnown(nationValue)
    return M.getIconName(nationValue) ~= nil
end

--- Check if a nation value represents anonymous/hidden status
-- @param nationValue any The nation value to check
-- @return boolean True if the value indicates anonymous
function M.isAnonymous(nationValue)
    if nationValue == nil then
        return true
    end
    if type(nationValue) == "string" and nationValue == "" then
        return true
    end
    -- Numeric -1 or negative values typically mean anonymous
    if type(nationValue) == "number" and nationValue < 0 then
        return true
    end
    return not M.isKnown(nationValue)
end

return M
