local M = {}

M.Note = {}
M.Note.__index = M.Note

function M.Note.new(friendName, note, updatedAt)
    local self = setmetatable({}, M.Note)
    self.friendName = friendName or ""
    self.note = note or ""
    self.updatedAt = updatedAt or 0
    return self
end

function M.Note:__eq(other)
    return self.friendName == other.friendName
end

function M.Note:isEmpty()
    return self.note == "" or self.note == nil
end

M.NoteMerger = {}
M.NoteMerger.MERGE_DIVIDER = "\n\n--- Merged Notes ---\n\n"

local function trim(str)
    if not str or str == "" then
        return ""
    end
    
    local start = 1
    local len = string.len(str)
    
    while start <= len do
        local c = string.sub(str, start, start)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            break
        end
        start = start + 1
    end
    
    if start > len then
        return ""
    end
    
    local finish = len
    while finish >= start do
        local c = string.sub(str, finish, finish)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            break
        end
        finish = finish - 1
    end
    
    return string.sub(str, start, finish)
end

-- Merge notes (local-only, no server notes)
-- Note: Server notes feature removed, this function now just returns local note
function M.NoteMerger.merge(localNote, localTimestamp, serverNote, serverTimestamp, localFormattedTimestamp, serverFormattedTimestamp)
    local localTrimmed = trim(localNote or "")
    -- Server notes are no longer supported, return local note only
    return localTrimmed
end

function M.NoteMerger.containsMergeMarker(note)
    -- Server notes removed, only check for local merge markers
    if string.find(note, "--- Merged Notes ---") then
        return true
    end
    if string.find(note, "=== Local Note %(") then
        return true
    end
    return false
end

function M.NoteMerger.areNotesEqual(note1, note2)
    local t1 = trim(note1 or "")
    local t2 = trim(note2 or "")
    return t1 == t2
end

function M.NoteMerger.formatTimestamp(timestamp, formattedString)
    if formattedString and formattedString ~= "" then
        return formattedString
    end
    if timestamp == 0 or not timestamp then
        return "unknown"
    end
    -- Convert milliseconds to seconds if timestamp appears to be in ms
    -- (timestamps > 10 billion are likely milliseconds)
    local seconds = timestamp
    if timestamp > 10000000000 then
        seconds = math.floor(timestamp / 1000)
    end
    -- Format: YYYY-MM-DD HH:MM:SS
    local formatted = os.date("%Y-%m-%d %H:%M:%S", seconds)
    if formatted then
        return formatted
    end
    return "unknown"
end

return M

