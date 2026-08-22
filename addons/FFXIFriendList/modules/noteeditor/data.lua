--[[
* NoteEditor Module - Data
* State management: reads notes from app.features.notes
]]

local M = {}

-- Module state
local state = {
    initialized = false,
    currentFriendName = "",
    currentNoteText = "",
    originalNoteText = "",
    lastSavedAt = 0,
    isLoading = false,
    errorMessage = "",
    statusMessage = "",
    hasUnsavedChanges = false
}

-- Initialize data module
function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
end

-- Update data from app state (called every frame before render)
function M.Update()
    if not state.initialized then
        return
    end
    
    -- Check for unsaved changes
    if state.currentFriendName ~= "" then
        state.hasUnsavedChanges = (state.currentNoteText ~= state.originalNoteText)
    else
        state.hasUnsavedChanges = false
    end
end

-- Open editor for a friend
function M.OpenEditor(friendName)
    if not state.initialized then
        return
    end
    
    state.currentFriendName = friendName or ""
    
    -- Load note from app.features.notes
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notes then
        local friendKey = friendName  -- Use friend name as key
        local noteText = app.features.notes:getNote(friendKey) or ""
        state.currentNoteText = noteText
        state.originalNoteText = noteText
        state.lastSavedAt = os.time() * 1000  -- Current time in ms
    else
        state.currentNoteText = ""
        state.originalNoteText = ""
        state.lastSavedAt = 0
    end
    
    state.isLoading = false
    state.errorMessage = ""
    state.statusMessage = ""
end

-- Close editor
function M.CloseEditor()
    state.currentFriendName = ""
    state.currentNoteText = ""
    state.originalNoteText = ""
    state.lastSavedAt = 0
    state.isLoading = false
    state.errorMessage = ""
    state.statusMessage = ""
    state.hasUnsavedChanges = false
end

-- Set note text (from UI input)
function M.SetNoteText(text)
    state.currentNoteText = text or ""
end

-- Get current friend name
function M.GetCurrentFriendName()
    return state.currentFriendName
end

-- Get current note text
function M.GetCurrentNoteText()
    return state.currentNoteText
end

-- Check if editor is open
function M.IsEditorOpen()
    return state.currentFriendName ~= ""
end

-- Check if has unsaved changes
function M.HasUnsavedChanges()
    return state.hasUnsavedChanges
end

-- Save note
function M.SaveNote()
    if not state.initialized or state.currentFriendName == "" then
        return false
    end
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notes then
        local friendKey = state.currentFriendName
        app.features.notes:setNote(friendKey, state.currentNoteText)
        app.features.notes:save()
        
        state.originalNoteText = state.currentNoteText
        state.lastSavedAt = os.time() * 1000
        state.hasUnsavedChanges = false
        state.errorMessage = ""
        state.statusMessage = "Saved"
        
        return true
    end
    
    return false
end

-- Delete note
function M.DeleteNote()
    if not state.initialized or state.currentFriendName == "" then
        return false
    end
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notes then
        local friendKey = state.currentFriendName
        app.features.notes:deleteNote(friendKey)
        app.features.notes:save()
        
        state.currentNoteText = ""
        state.originalNoteText = ""
        state.lastSavedAt = 0
        state.hasUnsavedChanges = false
        state.errorMessage = ""
        state.statusMessage = "Deleted"
        
        return true
    end
    
    return false
end

-- Get last saved timestamp
function M.GetLastSavedAt()
    return state.lastSavedAt
end

-- Get error message
function M.GetError()
    return state.errorMessage
end

-- Get status message
function M.GetStatus()
    return state.statusMessage
end

-- Clear status
function M.ClearStatus()
    state.statusMessage = ""
end

-- Cleanup
function M.Cleanup()
    state.initialized = false
end

return M

