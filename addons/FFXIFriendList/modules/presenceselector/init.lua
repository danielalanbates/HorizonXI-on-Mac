-- modules/presenceselector/init.lua
-- Presence selector module

local display = require('modules.presenceselector.display')

local M = {}

function M.Initialize(settings)
    display.Initialize(settings)
end

function M.Render(config, settings, eventSystemActive)
    -- Always render when character is not ready
    display.Render()
end

function M.UpdateVisuals(settings)
    display.UpdateVisuals(settings)
end

function M.SetHidden(hidden)
    display.SetHidden(hidden)
end

function M.Cleanup()
    display.Cleanup()
end

return M
