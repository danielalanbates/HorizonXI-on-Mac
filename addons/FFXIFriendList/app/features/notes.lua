local M = {}

-- Pending note expiry: 7 days in seconds
local PENDING_EXPIRY_SECONDS = 7 * 24 * 60 * 60

M.Notes = {}
M.Notes.__index = M.Notes

function M.Notes.new(deps)
    local self = setmetatable({}, M.Notes)
    self.deps = deps or {}
    
    self.notes = {}
    self.pendingNotes = {}  -- { [lowerName] = { note = "...", createdAt = timestamp } }
    self.dirty = false
    self.pendingDirty = false
    
    return self
end

function M.Notes:getState()
    local pendingCount = 0
    for _ in pairs(self.pendingNotes) do
        pendingCount = pendingCount + 1
    end
    local noteCount = 0
    for _ in pairs(self.notes) do
        noteCount = noteCount + 1
    end
    return {
        noteCount = noteCount,
        pendingCount = pendingCount,
        dirty = self.dirty,
        pendingDirty = self.pendingDirty
    }
end

local function getTime(self)
    if self.deps.time then
        return self.deps.time()
    end
    return os.time() * 1000
end

function M.Notes:load()
    if not self.deps.storage then
        return false
    end
    
    -- Load notes
    local data = self.deps.storage.load("notes")
    if data and type(data) == "table" then
        self.notes = data
        self.dirty = false
    end
    
    -- Load pending notes (drafts)
    local pendingData = self.deps.storage.load("pending_notes")
    if pendingData and type(pendingData) == "table" then
        self.pendingNotes = pendingData
        self.pendingDirty = false
        -- Clean up expired pending notes on load
        self:cleanupExpiredPending()
    end
    
    return true
end

function M.Notes:save()
    if not self.deps.storage then
        return false
    end
    
    local saved = false
    if self.dirty then
        self.deps.storage.save("notes", self.notes)
        self.dirty = false
        saved = true
    end
    
    if self.pendingDirty then
        self.deps.storage.save("pending_notes", self.pendingNotes)
        self.pendingDirty = false
        saved = true
    end
    
    return saved
end

-- Clean up pending notes older than 7 days
function M.Notes:cleanupExpiredPending()
    local now = os.time()
    local expired = {}
    
    for key, entry in pairs(self.pendingNotes) do
        if type(entry) == "table" and entry.createdAt then
            local age = now - entry.createdAt
            if age > PENDING_EXPIRY_SECONDS then
                table.insert(expired, key)
            end
        elseif type(entry) == "string" then
            -- Migrate old format (just a string) to new format with timestamp
            self.pendingNotes[key] = { note = entry, createdAt = now }
            self.pendingDirty = true
        end
    end
    
    for _, key in ipairs(expired) do
        self.pendingNotes[key] = nil
        self.pendingDirty = true
    end
    
    if self.pendingDirty then
        self:save()
    end
end

function M.Notes:getNote(friendKey)
    return self.notes[friendKey] or ""
end

function M.Notes:setNote(friendKey, note)
    if note and note ~= "" then
        self.notes[friendKey] = note
    else
        self.notes[friendKey] = nil
    end
    self.dirty = true
end

function M.Notes:deleteNote(friendKey)
    self.notes[friendKey] = nil
    self.dirty = true
end

function M.Notes:hasNote(friendKey)
    return self.notes[friendKey] ~= nil and self.notes[friendKey] ~= ""
end

function M.Notes:setPendingNote(friendName, note)
    if not friendName or friendName == "" then
        return false
    end
    
    local key = string.lower(friendName)
    
    if note and note ~= "" then
        self.pendingNotes[key] = {
            note = note,
            createdAt = os.time()
        }
        self.pendingDirty = true
        -- Persist immediately
        self:save()
    else
        if self.pendingNotes[key] then
            self.pendingNotes[key] = nil
            self.pendingDirty = true
            self:save()
        end
    end
    
    return true
end

function M.Notes:getPendingNote(friendName)
    if not friendName or friendName == "" then
        return nil
    end
    
    local key = string.lower(friendName)
    local entry = self.pendingNotes[key]
    if type(entry) == "table" then
        return entry.note
    elseif type(entry) == "string" then
        return entry  -- Legacy format
    end
    return nil
end

function M.Notes:consumePendingNote(friendName)
    if not friendName or friendName == "" then
        return nil
    end
    
    local key = string.lower(friendName)
    local entry = self.pendingNotes[key]
    local note = nil
    
    if type(entry) == "table" then
        note = entry.note
    elseif type(entry) == "string" then
        note = entry
    end
    
    if note then
        self.pendingNotes[key] = nil
        self.pendingDirty = true
        self:save()
    end
    
    return note
end

return M
