--[[
* Themes Module - Data
* State management: reads theme data from app.features.themes
]]

local Models = require('core.models')

local M = {}

-- Module state
local state = {
    initialized = false,
    currentThemeIndex = 0,
    currentPresetName = "",
    currentCustomThemeName = "",
    builtInThemeNames = {},
    customThemes = {},
    isDefaultTheme = false
}

-- Initialize data module
function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
    -- Always set built-in theme names on initialization (from Models constant)
    state.builtInThemeNames = Models.BUILTIN_THEME_NAMES
end

-- Update data from app state (called every frame before render)
function M.Update()
    if not state.initialized then
        return
    end
    
    -- Get app instance from global (set by entry file)
    local app = _G.FFXIFriendListApp
    if not app then
        return
    end
    
    -- Get themes feature
    if app.features and app.features.themes then
        local themesFeature = app.features.themes
        local themeState = themesFeature:getState()
        
        if themeState then
            state.currentThemeIndex = themeState.themeIndex or 0
            state.currentPresetName = themeState.presetName or ""
            state.currentCustomThemeName = themeState.customThemeName or ""
            
            -- Get custom themes
            if themesFeature.getCustomThemes then
                state.customThemes = themesFeature:getCustomThemes() or {}
            end
            
            -- Update alpha values
            if themesFeature.getBackgroundAlpha then
                state.backgroundAlpha = themesFeature:getBackgroundAlpha() or 0.95
            end
            if themesFeature.getTextAlpha then
                state.textAlpha = themesFeature:getTextAlpha() or 1.0
            end
            
            -- Determine if default theme
            -- Default theme is now Classic (themeIndex 0), not -2
            -- isDefaultTheme is true only if themeIndex is -2 (which should not be used as default anymore)
            state.isDefaultTheme = (state.currentThemeIndex == -2) and 
                                   (state.currentCustomThemeName == "" or state.currentCustomThemeName == nil) and
                                   (state.currentPresetName == "" or state.currentPresetName == nil)
        end
        
    end
    
    -- Built-in theme names (always set, even if themes feature isn't available)
    state.builtInThemeNames = Models.BUILTIN_THEME_NAMES
end

-- Get current theme index
function M.GetCurrentThemeIndex()
    return state.currentThemeIndex
end

-- Get current preset name
function M.GetCurrentPresetName()
    return state.currentPresetName
end

-- Get current custom theme name
function M.GetCurrentCustomThemeName()
    return state.currentCustomThemeName
end

-- Get current theme name (for display)
function M.GetCurrentThemeName()
    if state.currentCustomThemeName and state.currentCustomThemeName ~= "" then
        return state.currentCustomThemeName
    elseif state.currentPresetName and state.currentPresetName ~= "" then
        return state.currentPresetName
    elseif state.builtInThemeNames and #state.builtInThemeNames > 0 then
        -- Map theme index to name (uses Models.BUILTIN_THEME_NAMES)
        -- -2 = Default (No Theme) -> return "Default (No Theme)" (not in list)
        -- 0+ = built-in themes from BUILTIN_THEME_NAMES array
        if state.currentThemeIndex == -2 then
            return "Default (No Theme)"
        elseif state.currentThemeIndex >= 0 and state.currentThemeIndex <= Models.MAX_BUILTIN_THEME_INDEX then
            return state.builtInThemeNames[state.currentThemeIndex + 1]  -- +1 because index 0 maps to builtInThemeNames[1]
        end
    end
    return "Default (No Theme)"
end

-- Get built-in theme names
function M.GetBuiltInThemeNames()
    return state.builtInThemeNames
end

-- Get custom themes
function M.GetCustomThemes()
    return state.customThemes
end

-- Check if default theme
function M.IsDefaultTheme()
    return state.isDefaultTheme
end

-- Get available presets
function M.GetAvailablePresets()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        return app.features.themes:getAvailablePresets() or {}
    end
    -- Presets removed - return empty list
    return {}
end

-- Get current theme colors
function M.GetCurrentThemeColors()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        return app.features.themes:getCurrentThemeColors()
    end
    return nil
end

-- Cleanup
function M.Cleanup()
    state.initialized = false
    state.customThemes = {}
end

return M

