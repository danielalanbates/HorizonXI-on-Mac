local M = {}

--- Parse an ISO8601 timestamp string to Unix timestamp in milliseconds
-- Handles format: "2024-01-01T12:00:00.000Z" or "2024-01-01T12:00:00Z"
-- @param isoString string|nil The ISO8601 timestamp string
-- @return number Unix timestamp in milliseconds, or 0 if parsing fails
function M.parseISO8601(isoString)
    if type(isoString) ~= "string" or isoString == "" then
        return 0
    end
    
    -- Pattern: YYYY-MM-DDTHH:MM:SS(.sss)?Z
    local year, month, day, hour, min, sec, ms = isoString:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)%.?(%d*)Z?$"
    )
    
    if not year then
        -- Try without milliseconds
        year, month, day, hour, min, sec = isoString:match(
            "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z?$"
        )
        ms = "0"
    end
    
    if not year then
        return 0
    end
    
    -- Convert to numbers
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    hour = tonumber(hour)
    min = tonumber(min)
    sec = tonumber(sec)
    ms = tonumber(ms) or 0
    
    -- Validate ranges
    if not year or year < 1970 or year > 2100 then return 0 end
    if not month or month < 1 or month > 12 then return 0 end
    if not day or day < 1 or day > 31 then return 0 end
    if not hour or hour < 0 or hour > 23 then return 0 end
    if not min or min < 0 or min > 59 then return 0 end
    if not sec or sec < 0 or sec > 59 then return 0 end
    
    -- Convert to Unix timestamp using os.time (assumes UTC)
    -- Note: os.time in Lua treats input as local time, so we need to adjust
    local timestamp = os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = min,
        sec = sec
    })
    
    -- Adjust for timezone offset (os.time assumes local, we have UTC)
    -- Get the difference between local time and UTC
    local now = os.time()
    local utcNow = os.time(os.date("!*t", now))
    local tzOffset = now - utcNow
    
    -- Apply timezone offset to get correct UTC timestamp
    timestamp = timestamp - tzOffset
    
    -- Convert to milliseconds and add the fractional part
    local msValue = ms
    if type(msValue) == "number" and msValue > 0 then
        -- Normalize milliseconds (could be 1-3 digits)
        local msStr = tostring(ms)
        while #msStr < 3 do msStr = msStr .. "0" end
        msValue = tonumber(string.sub(msStr, 1, 3)) or 0
    else
        msValue = 0
    end
    
    return (timestamp * 1000) + msValue
end

--- Convert a lastSeen value to a numeric timestamp in milliseconds
-- Handles: number (passthrough), ISO8601 string, nil (returns 0)
-- @param lastSeenValue any The last seen value from server or cache
-- @return number Unix timestamp in milliseconds
function M.normalizeLastSeen(lastSeenValue)
    if type(lastSeenValue) == "number" then
        return lastSeenValue
    end
    if type(lastSeenValue) == "string" then
        return M.parseISO8601(lastSeenValue)
    end
    return 0
end

function M.capitalizeName(name)
    if not name or name == "" then
        return name or ""
    end
    
    local result = ""
    local capitalizeNext = true
    
    for i = 1, #name do
        local char = string.sub(name, i, i)
        if char == " " then
            capitalizeNext = true
            result = result .. char
        else
            if capitalizeNext then
                result = result .. string.upper(char)
                capitalizeNext = false
            else
                result = result .. string.lower(char)
            end
        end
    end
    
    return result
end

function M.getDisplayName(friend)
    local isOnline = friend.isOnline or false
    local name = friend.name or ""
    local friendedAs = friend.friendedAs or ""
    
    -- Offline and on an alt: show friendedAs
    if not isOnline and friendedAs ~= "" and name ~= friendedAs then
        return friendedAs
    end
    return name ~= "" and name or "Unknown"
end

function M.formatRelativeTime(timestampMs)
    if type(timestampMs) ~= "number" or timestampMs <= 0 then
        return "Unknown"
    end
    
    local now = os.time()
    local diff = now - (timestampMs / 1000)
    
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h ago"
    elseif diff < 604800 then
        return math.floor(diff / 86400) .. "d ago"
    else
        return os.date("%m/%d/%Y", timestampMs / 1000)
    end
end

return M

