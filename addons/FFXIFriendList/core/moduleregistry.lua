--[[
* FFXIFriendList Module Registry
* Data-driven module management for initialization, rendering, cleanup, and visibility
]]--

local M = {};

-- Module registry - defines all UI modules and their configuration
-- Each entry contains:
--   module: the required module
--   settingsKey: key in gAdjustedSettings for this module's settings (optional)
--   configKey: key in gConfig for visibility (optional)
--   hideOnEventKey: whether to hide during events (optional config key)
--   hasSetHidden: whether module has SetHidden function
local registry = {};

function M.Register(name, config)
    registry[name] = config;
    return nil  -- Explicitly return nil to prevent any table from being returned
end

function M.Get(name)
    return registry[name];
end

function M.GetAll()
    return registry;
end

-- Initialize all registered modules
function M.InitializeAll(gAdjustedSettings)
    for name, entry in pairs(registry) do
        if entry.module and entry.module.Initialize then
            local settings = gAdjustedSettings;
            if entry.settingsKey and gAdjustedSettings then
                settings = gAdjustedSettings[entry.settingsKey];
            end
            local _ = entry.module.Initialize(settings)
        end
    end
    return nil
end

-- Update visuals for all registered modules
function M.UpdateVisualsAll(gAdjustedSettings)
    for name, entry in pairs(registry) do
        if entry.module and entry.module.UpdateVisuals then
            local settings = gAdjustedSettings;
            if entry.settingsKey and gAdjustedSettings then
                settings = gAdjustedSettings[entry.settingsKey];
            end
            entry.module.UpdateVisuals(settings);
        end
    end
end

-- Cleanup all registered modules
function M.CleanupAll()
    for name, entry in pairs(registry) do
        if entry.module and entry.module.Cleanup then
            local _ = entry.module.Cleanup();  -- Capture return value to prevent printing
        end
    end
    return nil  -- Explicitly return nil
end

-- Hide all modules that support SetHidden
function M.HideAll()
    for name, entry in pairs(registry) do
        if entry.hasSetHidden and entry.module and entry.module.SetHidden then
            entry.module.SetHidden(true);
        end
    end
end

-- Check visibility based on config and update module visibility
function M.CheckVisibility(gConfig)
    if not gConfig then return; end
    for name, entry in pairs(registry) do
        if entry.configKey and entry.hasSetHidden and entry.module and entry.module.SetHidden then
            -- Hide if config is false, show if config is true/nil
            local shouldHide = gConfig[entry.configKey] == false
            entry.module.SetHidden(shouldHide)
        end
    end
end

-- Render a single module
-- Returns true if rendered, false if hidden
function M.RenderModule(name, gConfig, gAdjustedSettings, eventSystemActive)
    local entry = registry[name];
    if not entry or not entry.module then return false; end

    -- Check if module should be shown
    local shouldShow = true;
    if entry.configKey and gConfig then
        shouldShow = gConfig[entry.configKey] ~= false;
    end

    -- Check event hiding
    if shouldShow and entry.hideOnEventKey and eventSystemActive and gConfig then
        shouldShow = not gConfig[entry.hideOnEventKey];
    end

    if shouldShow then
        -- Restore visibility if module was previously hidden
        if entry.hasSetHidden and entry.module.SetHidden then
            entry.module.SetHidden(false);
        end
        if entry.module.DrawWindow then
            local settings = gAdjustedSettings;
            if entry.settingsKey and gAdjustedSettings then
                settings = gAdjustedSettings[entry.settingsKey];
            end
            entry.module.DrawWindow(settings);
        end
        return true;
    else
        if entry.hasSetHidden and entry.module.SetHidden then
            entry.module.SetHidden(true);
        end
        return false;
    end
end

-- Create a visual updater function for a specific module
function M.CreateVisualUpdater(name, saveSettingsFunc, gAdjustedSettings)
    local entry = registry[name];
    if not entry then return function() end; end

    return function()
        if saveSettingsFunc then
            saveSettingsFunc();
        end
        if entry.module and entry.module.UpdateVisuals then
            local settings = gAdjustedSettings;
            if entry.settingsKey and gAdjustedSettings then
                settings = gAdjustedSettings[entry.settingsKey];
            end
            entry.module.UpdateVisuals(settings);
        end
    end
end

return M;

