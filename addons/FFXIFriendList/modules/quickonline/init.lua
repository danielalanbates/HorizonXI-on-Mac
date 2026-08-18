--[[
* QuickOnline Module - Init
* Public API and lifecycle management
]]

local quickonline = {}

-- Load sub-modules
quickonline.data = require('modules.quickonline.data')
quickonline.display = require('modules.quickonline.display')

-- Module state
local moduleState = {
    initialized = false,
    hidden = false
}

-- Initialize the module (called once on addon load)
function quickonline.Initialize(settings)
    if moduleState.initialized then
        return nil
    end
    
    local _ = quickonline.data.Initialize(settings)  -- Capture return value
    local _ = quickonline.display.Initialize(settings)  -- Capture return value
    
    moduleState.initialized = true
    return nil  -- Explicitly return nil
end

-- Update visuals when settings change (fonts, themes, etc.)
function quickonline.UpdateVisuals(settings)
    if not moduleState.initialized then
        return
    end
    
    quickonline.display.UpdateVisuals(settings)
end

-- Main render function (called every frame)
function quickonline.DrawWindow(settings)
    if not moduleState.initialized or moduleState.hidden then
        return
    end
    
    -- Update data from app state
    quickonline.data.Update()
    
    -- Render display
    quickonline.display.DrawWindow(settings, quickonline.data)
end

-- Hide/show module elements
function quickonline.SetHidden(hidden)
    moduleState.hidden = hidden or false
    if quickonline.display.SetHidden then
        quickonline.display.SetHidden(hidden)
    end
end

-- Cleanup resources (called on addon unload)
function quickonline.Cleanup()
    if quickonline.display.Cleanup then
        quickonline.display.Cleanup()
    end
    if quickonline.data.Cleanup then
        quickonline.data.Cleanup()
    end
    
    moduleState.initialized = false
end

return quickonline

