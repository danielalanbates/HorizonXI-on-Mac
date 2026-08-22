--[[
* ServerSelection Module - Init
* Public API and lifecycle management
]]

local serverselection = {}

-- Load sub-modules
serverselection.data = require('modules.serverselection.data')
serverselection.display = require('modules.serverselection.display')

-- Module state
local moduleState = {
    initialized = false,
    hidden = false
}

-- Initialize the module (called once on addon load)
function serverselection.Initialize(settings)
    if moduleState.initialized then
        return nil
    end
    
    local _ = serverselection.data.Initialize(settings)
    local _ = serverselection.display.Initialize(settings)
    
    moduleState.initialized = true
    return nil
end

-- Update visuals when settings change (fonts, themes, etc.)
function serverselection.UpdateVisuals(settings)
    if not moduleState.initialized then
        return
    end
    
    serverselection.display.UpdateVisuals(settings)
end

-- Main render function (called every frame)
function serverselection.DrawWindow(settings)
    if not moduleState.initialized or moduleState.hidden then
        return
    end
    
    -- Update data from app state
    serverselection.data.Update()
    
    -- Render display
    serverselection.display.DrawWindow(settings, serverselection.data)
end

-- Show server selection window
function serverselection.Show()
    if not moduleState.initialized then
        return
    end
    
    -- Set gConfig.showServerSelection so module registry renders us
    if gConfig then
        gConfig.showServerSelection = true
    end
    
    serverselection.display.SetVisible(true)
end

-- Check if window should be shown (no saved server)
function serverselection.ShouldShow(app)
    if not moduleState.initialized then
        return false
    end
    
    -- Use serverlist feature as source of truth
    if app and app.features and app.features.serverlist then
        return not app.features.serverlist:isServerSelected()
    end
    
    -- Fallback to data module check
    return serverselection.data.HasSavedServer() == false
end

-- Hide/show module elements
function serverselection.SetHidden(hidden)
    moduleState.hidden = hidden or false
    if serverselection.display.SetHidden then
        serverselection.display.SetHidden(hidden)
    end
end

-- Cleanup resources (called on addon unload)
function serverselection.Cleanup()
    if serverselection.display.Cleanup then
        serverselection.display.Cleanup()
    end
    if serverselection.data.Cleanup then
        serverselection.data.Cleanup()
    end
    
    moduleState.initialized = false
end

return serverselection

