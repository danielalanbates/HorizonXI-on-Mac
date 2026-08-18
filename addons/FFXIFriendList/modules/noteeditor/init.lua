--[[
* NoteEditor Module - Init
* Public API and lifecycle management
]]

local noteeditor = {}

-- Load sub-modules
noteeditor.data = require('modules.noteeditor.data')
noteeditor.display = require('modules.noteeditor.display')

-- Module state
local moduleState = {
    initialized = false,
    hidden = false
}

-- Initialize the module (called once on addon load)
function noteeditor.Initialize(settings)
    if moduleState.initialized then
        return nil
    end
    
    local _ = noteeditor.data.Initialize(settings)
    local _ = noteeditor.display.Initialize(settings)
    
    moduleState.initialized = true
    return nil
end

-- Update visuals when settings change (fonts, themes, etc.)
function noteeditor.UpdateVisuals(settings)
    if not moduleState.initialized then
        return
    end
    
    noteeditor.display.UpdateVisuals(settings)
end

-- Main render function (called every frame)
function noteeditor.DrawWindow(settings)
    if not moduleState.initialized or moduleState.hidden then
        return
    end
    
    -- Update data from app state
    noteeditor.data.Update()
    
    -- Render display
    noteeditor.display.DrawWindow(settings, noteeditor.data)
end

-- Open note editor for a friend
function noteeditor.OpenEditor(friendName)
    if not moduleState.initialized then
        return
    end
    
    noteeditor.data.OpenEditor(friendName)
    noteeditor.display.SetVisible(true)
end

-- Check if editor is open
function noteeditor.IsEditorOpen()
    if not moduleState.initialized then
        return false
    end
    
    return noteeditor.data.IsEditorOpen()
end

-- Hide/show module elements
function noteeditor.SetHidden(hidden)
    moduleState.hidden = hidden or false
    if noteeditor.display.SetHidden then
        noteeditor.display.SetHidden(hidden)
    end
end

-- Cleanup resources (called on addon unload)
function noteeditor.Cleanup()
    if noteeditor.display.Cleanup then
        noteeditor.display.Cleanup()
    end
    if noteeditor.data.Cleanup then
        noteeditor.data.Cleanup()
    end
    
    moduleState.initialized = false
end

return noteeditor

