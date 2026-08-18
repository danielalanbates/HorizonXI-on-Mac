--[[
* Notifications Module - Init
* Public API and lifecycle management
]]

local notifications = {}

notifications.data = require('modules.notifications.data')
notifications.display = require('modules.notifications.display')

local moduleState = {
    initialized = false,
    hidden = false
}

function notifications.Initialize(settings)
    if moduleState.initialized then
        return nil
    end
    
    local _ = notifications.data.Initialize(settings)  -- Capture return value
    local _ = notifications.display.Initialize(settings)  -- Capture return value
    
    moduleState.initialized = true
    return nil  -- Explicitly return nil
end

function notifications.UpdateVisuals(settings)
    if not moduleState.initialized then
        return
    end
    
    notifications.display.UpdateVisuals(settings)
end

function notifications.DrawWindow(settings)
    if not moduleState.initialized or moduleState.hidden then
        return
    end
    
    notifications.data.Update()
    notifications.display.DrawWindow(settings, notifications.data)
end

function notifications.SetHidden(hidden)
    moduleState.hidden = hidden or false
    if notifications.display.SetHidden then
        notifications.display.SetHidden(hidden)
    end
end

function notifications.Cleanup()
    if notifications.display.Cleanup then
        notifications.display.Cleanup()
    end
    if notifications.data.Cleanup then
        notifications.data.Cleanup()
    end
    
    moduleState.initialized = false
end

return notifications

