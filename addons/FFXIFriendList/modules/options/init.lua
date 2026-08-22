--[[
* Options Module - Init
* Public API and lifecycle management
]]

local options = {}

-- Load sub-modules
options.data = require('modules.options.data')
options.display = require('modules.options.display')

-- Module state
local moduleState = {
    initialized = false,
    hidden = false
}

-- Initialize the module
function options.Initialize(settings)
    if moduleState.initialized then
        return nil
    end
    
    local _ = options.data.Initialize(settings)  -- Capture return value
    local _ = options.display.Initialize(settings)  -- Capture return value
    
    moduleState.initialized = true
    return nil  -- Explicitly return nil
end

-- Update visuals when settings change
function options.UpdateVisuals(settings)
    if not moduleState.initialized then
        return
    end
    
    options.display.UpdateVisuals(settings)
end

-- Main render function
function options.DrawWindow(settings)
    if not moduleState.initialized or moduleState.hidden then
        return
    end
    
    options.data.Update()
    options.display.DrawWindow(settings, options.data)
end

-- Hide/show module
function options.SetHidden(hidden)
    moduleState.hidden = hidden or false
    if options.display.SetHidden then
        options.display.SetHidden(hidden)
    end
end

-- Cleanup
function options.Cleanup()
    if options.display.Cleanup then
        options.display.Cleanup()
    end
    if options.data.Cleanup then
        options.data.Cleanup()
    end
    
    moduleState.initialized = false
end

return options

