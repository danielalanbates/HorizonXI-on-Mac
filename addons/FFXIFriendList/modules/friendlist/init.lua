--[[
* FriendList Module - Init
* Public API and lifecycle management
]]

local friendlist = {}

-- Load sub-modules
friendlist.data = require('modules.friendlist.data')
friendlist.display = require('modules.friendlist.display')

-- Module state
local moduleState = {
    initialized = false,
    hidden = false
}

-- Initialize the module (called once on addon load)
function friendlist.Initialize(settings)
    if moduleState.initialized then
        return nil
    end
    
    local _ = friendlist.data.Initialize(settings)  -- Capture return value
    local _ = friendlist.display.Initialize(settings)  -- Capture return value
    
    moduleState.initialized = true
    return nil  -- Explicitly return nil
end

-- Update visuals when settings change (fonts, themes, etc.)
function friendlist.UpdateVisuals(settings)
    if not moduleState.initialized then
        return
    end
    
    friendlist.display.UpdateVisuals(settings)
end

-- Main render function (called every frame)
function friendlist.DrawWindow(settings)
    if not moduleState.initialized or moduleState.hidden then
        return
    end
    
    -- Update data from app state
    friendlist.data.Update()
    
    -- Render display
    friendlist.display.DrawWindow(settings, friendlist.data)
end

-- Hide/show module elements
function friendlist.SetHidden(hidden)
    moduleState.hidden = hidden or false
    if friendlist.display.SetHidden then
        friendlist.display.SetHidden(hidden)
    end
end

-- Cleanup resources (called on addon unload)
function friendlist.Cleanup()
    if friendlist.display.Cleanup then
        friendlist.display.Cleanup()
    end
    if friendlist.data.Cleanup then
        friendlist.data.Cleanup()
    end
    
    moduleState.initialized = false
end

return friendlist

