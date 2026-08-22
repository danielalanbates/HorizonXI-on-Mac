local Models = require('core.models')

local M = {}

M.Vec2 = {}
M.Vec2.__index = M.Vec2

function M.Vec2.new(x, y)
    local self = setmetatable({}, M.Vec2)
    self.x = x or 0.0
    self.y = y or 0.0
    return self
end

M.ThemeTokens = {}
M.ThemeTokens.__index = M.ThemeTokens

function M.ThemeTokens.new()
    local self = setmetatable({}, M.ThemeTokens)
    
    self.windowBgColor = {r = 0, g = 0, b = 0, a = 0}
    self.childBgColor = {r = 0, g = 0, b = 0, a = 0}
    self.frameBgColor = {r = 0, g = 0, b = 0, a = 0}
    self.frameBgHovered = {r = 0, g = 0, b = 0, a = 0}
    self.frameBgActive = {r = 0, g = 0, b = 0, a = 0}
    self.titleBg = {r = 0, g = 0, b = 0, a = 0}
    self.titleBgActive = {r = 0, g = 0, b = 0, a = 0}
    self.titleBgCollapsed = {r = 0, g = 0, b = 0, a = 0}
    self.buttonColor = {r = 0, g = 0, b = 0, a = 0}
    self.buttonHoverColor = {r = 0, g = 0, b = 0, a = 0}
    self.buttonActiveColor = {r = 0, g = 0, b = 0, a = 0}
    self.separatorColor = {r = 0, g = 0, b = 0, a = 0}
    self.separatorHovered = {r = 0, g = 0, b = 0, a = 0}
    self.separatorActive = {r = 0, g = 0, b = 0, a = 0}
    self.scrollbarBg = {r = 0, g = 0, b = 0, a = 0}
    self.scrollbarGrab = {r = 0, g = 0, b = 0, a = 0}
    self.scrollbarGrabHovered = {r = 0, g = 0, b = 0, a = 0}
    self.scrollbarGrabActive = {r = 0, g = 0, b = 0, a = 0}
    self.checkMark = {r = 0, g = 0, b = 0, a = 0}
    self.sliderGrab = {r = 0, g = 0, b = 0, a = 0}
    self.sliderGrabActive = {r = 0, g = 0, b = 0, a = 0}
    self.header = {r = 0, g = 0, b = 0, a = 0}
    self.headerHovered = {r = 0, g = 0, b = 0, a = 0}
    self.headerActive = {r = 0, g = 0, b = 0, a = 0}
    self.textColor = {r = 0, g = 0, b = 0, a = 0}
    self.textDisabled = {r = 0, g = 0, b = 0, a = 0}
    self.borderColor = {r = 0, g = 0, b = 0, a = 0}
    
    self.windowPadding = M.Vec2.new(12.0, 12.0)
    self.windowRounding = 6.0
    self.framePadding = M.Vec2.new(6.0, 3.0)
    self.frameRounding = 3.0
    self.itemSpacing = M.Vec2.new(6.0, 4.0)
    self.itemInnerSpacing = M.Vec2.new(4.0, 3.0)
    self.scrollbarSize = 12.0
    self.scrollbarRounding = 3.0
    self.grabRounding = 3.0
    
    self.backgroundAlpha = 0.95
    self.textAlpha = 1.0
    self.presetName = ""
    
    return self
end

M.Themes = {}
M.Themes.__index = M.Themes

function M.Themes.new(deps)
    local self = setmetatable({}, M.Themes)
    self.deps = deps or {}
    self.themeIndex = 0  -- Default to Classic
    self.presetName = ""
    self.customThemeName = ""
    self.customThemes = {}
    self.backgroundAlpha = 0.95
    self.textAlpha = 1.0
    self.fontSizePx = 14
    -- Editing state: temporary copy of theme being edited
    self.currentCustomTheme = nil  -- Temporary copy for built-in theme editing
    self.isEditingBuiltInTheme = false  -- Flag indicating if built-in theme is being edited
    return self
end

-- Load themes from persistence (called during initialization)
function M.Themes:loadThemes()
    local ThemePersistence = require('platform.ashita.persistence.ThemePersistence')
    local state = ThemePersistence.loadFromFile()
    
    if state then
        -- Validate and set theme index
        if state.themeIndex and state.themeIndex >= -2 and state.themeIndex <= Models.MAX_BUILTIN_THEME_INDEX then
            self.themeIndex = state.themeIndex
        end
        
        -- Set preset name
        if state.presetName then
            self.presetName = state.presetName
        end
        
        -- Set custom theme name
        if state.customThemeName then
            self.customThemeName = state.customThemeName
        end
        
        -- Set custom themes
        if state.customThemes then
            self.customThemes = state.customThemes
        end
        
        -- Validate and set alpha values
        if state.backgroundAlpha and state.backgroundAlpha >= 0.0 and state.backgroundAlpha <= 1.0 then
            self.backgroundAlpha = state.backgroundAlpha
        end
        
        if state.textAlpha and state.textAlpha >= 0.0 and state.textAlpha <= 1.0 then
            self.textAlpha = state.textAlpha
        end
        
        local FontManager = require('app.ui.FontManager')
        if state.fontSizePx and FontManager.isValidSize(state.fontSizePx) then
            self.fontSizePx = state.fontSizePx
        end
        
        -- Initialize currentCustomTheme if custom theme is selected
        if self.themeIndex == -1 and self.customThemeName and self.customThemeName ~= "" then
            for _, theme in ipairs(self.customThemes) do
                if theme.name == self.customThemeName then
                    -- Create a copy for editing
                    self.currentCustomTheme = {}
                    for k, v in pairs(theme) do
                        if type(v) == "table" and v.r then
                            -- Deep copy color
                            self.currentCustomTheme[k] = {r = v.r, g = v.g, b = v.b, a = v.a}
                        else
                            self.currentCustomTheme[k] = v
                        end
                    end
                    break
                end
            end
        end
        
        -- Reset editing flag on load
        self.isEditingBuiltInTheme = false
    end
end

-- Save themes to persistence
function M.Themes:saveThemes()
    local ThemePersistence = require('platform.ashita.persistence.ThemePersistence')
    local state = {
        themeIndex = self.themeIndex,
        presetName = self.presetName,
        customThemeName = self.customThemeName,
        backgroundAlpha = self.backgroundAlpha,
        textAlpha = self.textAlpha,
        fontSizePx = self.fontSizePx,
        customThemes = self.customThemes
    }
    
    return ThemePersistence.saveToFile(state)
end

function M.Themes:getState()
    return {
        themeIndex = self.themeIndex,
        presetName = self.presetName,
        customThemeName = self.customThemeName,
        backgroundAlpha = self.backgroundAlpha,
        textAlpha = self.textAlpha,
        fontSizePx = self.fontSizePx
    }
end

function M.Themes:getThemeIndex()
    return self.themeIndex
end

function M.Themes:setThemeIndex(index)
    self.themeIndex = index
end

function M.Themes:getPresetName()
    return self.presetName
end

function M.Themes:setPresetName(name)
    self.presetName = name
end

function M.Themes:getCustomThemeName()
    return self.customThemeName
end

function M.Themes:setCustomThemeName(name)
    self.customThemeName = name
end

function M.Themes:getCustomThemes()
    return self.customThemes
end

function M.Themes:addCustomTheme(theme)
    table.insert(self.customThemes, theme)
end

function M.Themes:getBackgroundAlpha()
    return self.backgroundAlpha
end

function M.Themes:setBackgroundAlpha(alpha)
    -- Validate alpha range
    local num = tonumber(alpha)
    if not num then
        return false, "Background alpha is not a number: " .. tostring(alpha)
    end
    if num < 0.0 or num > 1.0 then
        return false, "Background alpha is out of range: " .. tostring(num) .. " (must be 0.0-1.0)"
    end
    self.backgroundAlpha = num
    -- Save to persistence
    self:saveThemes()
    return true
end

function M.Themes:getTextAlpha()
    return self.textAlpha
end

function M.Themes:setTextAlpha(alpha)
    -- Validate alpha range
    local num = tonumber(alpha)
    if not num then
        return false, "Text alpha is not a number: " .. tostring(alpha)
    end
    if num < 0.0 or num > 1.0 then
        return false, "Text alpha is out of range: " .. tostring(num) .. " (must be 0.0-1.0)"
    end
    self.textAlpha = num
    -- Save to persistence
    self:saveThemes()
    return true
end

function M.Themes:getFontSizePx()
    return self.fontSizePx
end

function M.Themes:setFontSizePx(size)
    local FontManager = require('app.ui.FontManager')
    local normalized = FontManager.normalizeSize(size)
    self.fontSizePx = normalized
    self:saveThemes()
    return true
end

-- Apply theme from color palette
local function applyThemeFromPalette(bgDark, bgMedium, bgLight, bgLighter, accent, accentDark, accentDarker, borderDark, textLight, textMuted, childBg, outTheme)
    outTheme.windowBgColor = bgDark
    outTheme.childBgColor = childBg
    outTheme.titleBg = bgMedium
    outTheme.titleBgActive = bgLight
    outTheme.titleBgCollapsed = bgDark
    outTheme.frameBgColor = bgMedium
    outTheme.frameBgHovered = bgLight
    outTheme.frameBgActive = bgLighter
    outTheme.header = bgLight
    outTheme.headerHovered = bgLighter
    outTheme.headerActive = {r = accent.r, g = accent.g, b = accent.b, a = 0.3}
    
    outTheme.buttonColor = bgMedium
    outTheme.buttonHoverColor = bgLight
    outTheme.buttonActiveColor = bgLighter
    
    outTheme.textColor = textLight
    outTheme.textDisabled = textMuted
    
    outTheme.scrollbarBg = bgMedium
    outTheme.scrollbarGrab = bgLighter
    outTheme.scrollbarGrabHovered = borderDark
    outTheme.scrollbarGrabActive = accentDark
    
    outTheme.separatorColor = borderDark
    outTheme.separatorHovered = borderDark
    outTheme.separatorActive = borderDark
    
    outTheme.checkMark = accent
    outTheme.sliderGrab = accentDark
    outTheme.sliderGrabActive = accent
    
    -- Note: tableBgColor is not used in ImGui theme application, but included for completeness
    outTheme.tableBgColor = {
        r = childBg.r * 1.1,
        g = childBg.g * 1.1,
        b = childBg.b * 1.1,
        a = childBg.a
    }
    
    -- borderColor is required for ImGui theme
    outTheme.borderColor = borderDark
end

-- themeIndex: 0 = Classic, 1 = ModernDark, 2 = GreenNature, 3 = PurpleMystic, 4 = Ashita
local function initializeBuiltInTheme(themeIndex)
    local theme = {
        name = "",
        windowBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        childBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 0.0},
        frameBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        frameBgHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        frameBgActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        titleBg = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        titleBgActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        titleBgCollapsed = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        buttonColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        buttonHoverColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        buttonActiveColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        separatorColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        separatorHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        separatorActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarBg = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarGrab = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarGrabHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarGrabActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        checkMark = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        sliderGrab = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        sliderGrabActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        header = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        headerHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        headerActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        textColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        textDisabled = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        borderColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        tableBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}
    }
    
    if themeIndex == 0 then
        -- Classic (FFXIClassic) - Warm browns, golds, and parchment tones
        local bgDark = {r = 0.20, g = 0.16, b = 0.14, a = 0.95}      -- Deep brown-black
        local bgMedium = {r = 0.30, g = 0.24, b = 0.20, a = 1.0}     -- Warm medium brown
        local bgLight = {r = 0.40, g = 0.32, b = 0.26, a = 1.0}      -- Lighter brown
        local bgLighter = {r = 0.50, g = 0.40, b = 0.32, a = 1.0}    -- Lightest brown
        local accent = {r = 0.85, g = 0.70, b = 0.45, a = 1.0}       -- Gold accent
        local accentDark = {r = 0.70, g = 0.58, b = 0.38, a = 1.0}   -- Darker gold
        local accentDarker = {r = 0.60, g = 0.50, b = 0.32, a = 1.0} -- Darkest gold
        local borderDark = {r = 0.50, g = 0.40, b = 0.30, a = 1.0}   -- Brown border
        local textLight = {r = 0.95, g = 0.90, b = 0.85, a = 1.0}    -- Warm off-white
        local textMuted = {r = 0.70, g = 0.65, b = 0.60, a = 1.0}    -- Muted brown
        local childBg = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}         -- Transparent
        
        applyThemeFromPalette(bgDark, bgMedium, bgLight, bgLighter, accent, accentDark, accentDarker, borderDark, textLight, textMuted, childBg, theme)
        
    elseif themeIndex == 1 then
        -- ModernDark - Dark blue/cyan theme
        local bgDark = {r = 0.08, g = 0.08, b = 0.12, a = 0.95}      -- Deep blue-black
        local bgMedium = {r = 0.12, g = 0.12, b = 0.18, a = 1.0}     -- Medium dark blue
        local bgLight = {r = 0.18, g = 0.20, b = 0.28, a = 1.0}      -- Lighter blue
        local bgLighter = {r = 0.24, g = 0.28, b = 0.38, a = 1.0}    -- Lightest blue
        local accent = {r = 0.40, g = 0.70, b = 1.0, a = 1.0}        -- Bright cyan accent
        local accentDark = {r = 0.30, g = 0.50, b = 0.80, a = 1.0}   -- Darker cyan
        local accentDarker = {r = 0.20, g = 0.40, b = 0.70, a = 1.0} -- Darkest cyan
        local borderDark = {r = 0.20, g = 0.25, b = 0.35, a = 1.0}   -- Blue border
        local textLight = {r = 0.90, g = 0.90, b = 0.95, a = 1.0}   -- Cool off-white
        local textMuted = {r = 0.60, g = 0.65, b = 0.70, a = 1.0}   -- Muted blue-gray
        local childBg = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}         -- Transparent
        
        applyThemeFromPalette(bgDark, bgMedium, bgLight, bgLighter, accent, accentDark, accentDarker, borderDark, textLight, textMuted, childBg, theme)
        
    elseif themeIndex == 2 then
        -- GreenNature - Forest/green tones
        local bgDark = {r = 0.10, g = 0.15, b = 0.12, a = 0.95}     -- Deep green-black
        local bgMedium = {r = 0.15, g = 0.22, b = 0.18, a = 1.0}     -- Medium dark green
        local bgLight = {r = 0.20, g = 0.30, b = 0.24, a = 1.0}      -- Lighter green
        local bgLighter = {r = 0.25, g = 0.38, b = 0.30, a = 1.0}   -- Lightest green
        local accent = {r = 0.40, g = 0.80, b = 0.50, a = 1.0}      -- Bright green accent
        local accentDark = {r = 0.35, g = 0.60, b = 0.40, a = 1.0}   -- Darker green
        local accentDarker = {r = 0.25, g = 0.50, b = 0.30, a = 1.0} -- Darkest green
        local borderDark = {r = 0.25, g = 0.35, b = 0.28, a = 1.0}  -- Green border
        local textLight = {r = 0.85, g = 0.95, b = 0.88, a = 1.0}   -- Cool green-tinted white
        local textMuted = {r = 0.60, g = 0.70, b = 0.65, a = 1.0}   -- Muted green-gray
        local childBg = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}        -- Transparent
        
        applyThemeFromPalette(bgDark, bgMedium, bgLight, bgLighter, accent, accentDark, accentDarker, borderDark, textLight, textMuted, childBg, theme)
        
    elseif themeIndex == 3 then
        -- PurpleMystic - Purple/violet tones
        local bgDark = {r = 0.12, g = 0.10, b = 0.18, a = 0.95}     -- Deep purple-black
        local bgMedium = {r = 0.18, g = 0.15, b = 0.25, a = 1.0}     -- Medium dark purple
        local bgLight = {r = 0.24, g = 0.20, b = 0.32, a = 1.0}      -- Lighter purple
        local bgLighter = {r = 0.30, g = 0.25, b = 0.40, a = 1.0}   -- Lightest purple
        local accent = {r = 0.80, g = 0.60, b = 0.95, a = 1.0}      -- Bright purple accent
        local accentDark = {r = 0.60, g = 0.45, b = 0.75, a = 1.0}  -- Darker purple
        local accentDarker = {r = 0.50, g = 0.35, b = 0.65, a = 1.0} -- Darkest purple
        local borderDark = {r = 0.30, g = 0.25, b = 0.38, a = 1.0}   -- Purple border
        local textLight = {r = 0.95, g = 0.90, b = 0.98, a = 1.0}   -- Cool purple-tinted white
        local textMuted = {r = 0.70, g = 0.65, b = 0.75, a = 1.0}   -- Muted purple-gray
        local childBg = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}        -- Transparent
        
        applyThemeFromPalette(bgDark, bgMedium, bgLight, bgLighter, accent, accentDark, accentDarker, borderDark, textLight, textMuted, childBg, theme)
        
    elseif themeIndex == 4 then
        -- Ashita - Dark gray with coral/salmon accent (Ashita launcher style)
        theme.windowBgColor = {r = 0.180392, g = 0.200000, b = 0.231373, a = 0.960784}
        theme.childBgColor = {r = 0.219608, g = 0.239216, b = 0.270588, a = 0.960784}
        theme.frameBgColor = {r = 0.160784, g = 0.168627, b = 0.200000, a = 1.000000}
        theme.frameBgHovered = {r = 0.141176, g = 0.141176, b = 0.141176, a = 0.780392}
        theme.frameBgActive = {r = 0.121569, g = 0.121569, b = 0.121569, a = 1.000000}
        theme.titleBg = {r = 0.831373, g = 0.329412, b = 0.278431, a = 0.690196}
        theme.titleBgActive = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.titleBgCollapsed = {r = 0.831373, g = 0.329412, b = 0.278431, a = 0.501961}
        theme.buttonColor = {r = 0.831373, g = 0.329412, b = 0.278431, a = 0.780392}
        theme.buttonHoverColor = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.buttonActiveColor = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.separatorColor = {r = 0.431373, g = 0.431373, b = 0.501961, a = 0.501961}
        theme.separatorHovered = {r = 0.101961, g = 0.400000, b = 0.749020, a = 0.780392}
        theme.separatorActive = {r = 0.101961, g = 0.400000, b = 0.749020, a = 1.000000}
        theme.scrollbarBg = {r = 0.121569, g = 0.129412, b = 0.168627, a = 1.000000}
        theme.scrollbarGrab = {r = 0.831373, g = 0.329412, b = 0.278431, a = 0.690196}
        theme.scrollbarGrabHovered = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.scrollbarGrabActive = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.checkMark = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.sliderGrab = {r = 0.831373, g = 0.329412, b = 0.278431, a = 0.690196}
        theme.sliderGrabActive = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.header = {r = 0.831373, g = 0.329412, b = 0.278431, a = 0.780392}
        theme.headerHovered = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.headerActive = {r = 0.831373, g = 0.329412, b = 0.278431, a = 1.000000}
        theme.textColor = {r = 0.941176, g = 0.941176, b = 0.941176, a = 1.000000}
        theme.textDisabled = {r = 0.941176, g = 0.941176, b = 0.941176, a = 0.290196}
        theme.borderColor = {r = 0.050980, g = 0.050980, b = 0.101961, a = 0.800000}
    end
    
    return theme
end

-- Get current theme colors (returns CustomTheme structure)
function M.Themes:getCurrentThemeColors()
    -- If default/no theme (themeIndex == -2), return empty theme (uses ImGui defaults)
    if self.themeIndex == -2 then
        -- Return empty theme structure (all zeros/defaults)
        return {
            name = "",
            windowBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            childBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 0.0},
            frameBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            frameBgHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            frameBgActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            titleBg = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            titleBgActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            titleBgCollapsed = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            buttonColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            buttonHoverColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            buttonActiveColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            separatorColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            separatorHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            separatorActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            scrollbarBg = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            scrollbarGrab = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            scrollbarGrabHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            scrollbarGrabActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            checkMark = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            sliderGrab = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            sliderGrabActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            header = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            headerHovered = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            headerActive = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            textColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            textDisabled = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            borderColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            tableBgColor = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}
        }
    end
    
    -- If custom theme (themeIndex == -1), return currentCustomTheme (temporary copy) or from customThemes
    if self.themeIndex == -1 then
        -- If we have a temporary copy, return it (for immediate updates)
        if self.currentCustomTheme then
            return self.currentCustomTheme
        end
        
        -- Otherwise, return from customThemes
        if self.customThemeName and self.customThemeName ~= "" then
            for _, theme in ipairs(self.customThemes) do
                if theme.name == self.customThemeName then
                    -- Ensure borderColor exists (for compatibility with older themes)
                    if not theme.borderColor then
                        theme.borderColor = theme.separatorColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}
                    end
                    -- Store in currentCustomTheme for editing
                    self.currentCustomTheme = theme
                    return self.currentCustomTheme
                end
            end
        end
        -- Fallback if custom theme not found or name is empty
        return initializeBuiltInTheme(0)
    end
    
    -- If built-in theme (themeIndex 0 to MAX_BUILTIN_THEME_INDEX)
    if self.themeIndex >= 0 and self.themeIndex <= Models.MAX_BUILTIN_THEME_INDEX then
        -- If editing built-in theme, return temporary copy
        if self.isEditingBuiltInTheme and self.currentCustomTheme then
            return self.currentCustomTheme
        end
        -- Otherwise, return initialized built-in theme
        return initializeBuiltInTheme(self.themeIndex)
    end
    
    -- Invalid themeIndex - fallback to Classic
    return initializeBuiltInTheme(0)
end

-- Apply theme by index
function M.Themes:applyTheme(themeIndex)
    -- Validate themeIndex range
    if not themeIndex or themeIndex < -2 or themeIndex > Models.MAX_BUILTIN_THEME_INDEX then
        return false, "Invalid theme index: " .. tostring(themeIndex) .. " (must be -2 to " .. Models.MAX_BUILTIN_THEME_INDEX .. ")"
    end
    
    -- Reset editing flag if switching to different theme
    if self.themeIndex ~= themeIndex then
        self.isEditingBuiltInTheme = false
        self.currentCustomTheme = nil
    end
    
    self.themeIndex = themeIndex
    if themeIndex == -1 then
        -- Custom theme - requires customThemeName to be set
        return false, "No custom theme selected"
    end
    -- Clear preset name for built-in themes
    if themeIndex >= 0 and themeIndex <= Models.MAX_BUILTIN_THEME_INDEX then
        self.presetName = ""
    end
    -- Save to persistence
    self:saveThemes()
    return true
end

-- Set custom theme by name
function M.Themes:setCustomTheme(themeName)
    -- Find custom theme
    for _, theme in ipairs(self.customThemes) do
        if theme.name == themeName then
            self.themeIndex = -1
            self.customThemeName = themeName
            self.presetName = ""  -- Clear preset name for custom themes
            self.isEditingBuiltInTheme = false  -- Not editing built-in theme
            -- Create a copy for editing (so edits don't modify the original until saved)
            self.currentCustomTheme = {}
            for k, v in pairs(theme) do
                if type(v) == "table" and v.r then
                    -- Deep copy color
                    self.currentCustomTheme[k] = {r = v.r, g = v.g, b = v.b, a = v.a}
                else
                    self.currentCustomTheme[k] = v
                end
            end
            -- Save to persistence
            self:saveThemes()
            return true
        end
    end
    return false, "Custom theme not found: " .. themeName
end

-- Set theme preset (deprecated - presets removed)
function M.Themes:setThemePreset(presetName)
    -- Presets are removed - this function is kept for compatibility but does nothing
    return false, "Presets are no longer supported"
end

-- Helper: Validate color value (0.0-1.0 range)
local function validateColorValue(value, name)
    if value == nil then
        return false, name .. " is nil"
    end
    local num = tonumber(value)
    if not num then
        return false, name .. " is not a number: " .. tostring(value)
    end
    if num < 0.0 or num > 1.0 then
        return false, name .. " is out of range: " .. tostring(num) .. " (must be 0.0-1.0)"
    end
    return true, num
end

-- Helper: Validate color object {r, g, b, a}
local function validateColor(color, name)
    if not color or type(color) ~= "table" then
        return false, name .. " is not a table"
    end
    local rOk, r = validateColorValue(color.r, name .. ".r")
    if not rOk then return false, r end
    local gOk, g = validateColorValue(color.g, name .. ".g")
    if not gOk then return false, g end
    local bOk, b = validateColorValue(color.b, name .. ".b")
    if not bOk then return false, b end
    local aOk, a = validateColorValue(color.a, name .. ".a")
    if not aOk then return false, a end
    return true, {r = r, g = g, b = b, a = a}
end

-- Update current theme colors
function M.Themes:updateCurrentThemeColors(colors)
    -- Cannot update default theme (themeIndex == -2)
    if self.themeIndex == -2 then
        return false, "Cannot update colors for default theme"
    end
    
    -- Validate themeIndex
    if self.themeIndex < -2 or self.themeIndex > Models.MAX_BUILTIN_THEME_INDEX then
        return false, "Invalid theme index: " .. tostring(self.themeIndex)
    end
    
    -- Validate all color values (clamp to 0.0-1.0 range)
    local colorFields = {
        "windowBgColor", "childBgColor", "frameBgColor", "frameBgHovered", "frameBgActive",
        "titleBg", "titleBgActive", "titleBgCollapsed", "buttonColor", "buttonHoverColor",
        "buttonActiveColor", "separatorColor", "separatorHovered", "separatorActive",
        "scrollbarBg", "scrollbarGrab", "scrollbarGrabHovered", "scrollbarGrabActive",
        "checkMark", "sliderGrab", "sliderGrabActive", "header", "headerHovered",
        "headerActive", "textColor", "textDisabled", "borderColor"
    }
    
    local validatedColors = {}
    for _, field in ipairs(colorFields) do
        if colors[field] then
            local ok, validated = validateColor(colors[field], field)
            if not ok then
                return false, validated  -- validated contains error message
            end
            validatedColors[field] = validated
        else
            -- Use default if missing
            validatedColors[field] = {r = 0.0, g = 0.0, b = 0.0, a = 1.0}
        end
    end
    
    -- Copy name if present
    if colors.name then
        validatedColors.name = colors.name
    end
    
    -- Store validated colors in temporary copy (for immediate application)
    self.currentCustomTheme = validatedColors
    
    -- For custom themes, also update the theme in customThemes array
    if self.themeIndex == -1 and self.customThemeName ~= "" then
        -- Set name to match current custom theme
        self.currentCustomTheme.name = self.customThemeName
        
        -- Update the theme in customThemes array
        for i, theme in ipairs(self.customThemes) do
            if theme.name == self.customThemeName then
                self.customThemes[i] = self.currentCustomTheme
                -- Save to persistence
                self:saveThemes()
                return true
            end
        end
    elseif self.themeIndex >= 0 and self.themeIndex <= Models.MAX_BUILTIN_THEME_INDEX then
        -- For built-in themes, mark as editing (temporary copy)
        self.isEditingBuiltInTheme = true
        -- Don't save to persistence yet (only save when saved as custom theme)
        return true
    end
    
    return true
end

-- Save custom theme
function M.Themes:saveCustomTheme(themeName, colors)
    -- Use currentCustomTheme if available (has latest edits), otherwise use provided colors
    local themeToSave = self.currentCustomTheme or colors
    
    -- Ensure name is set
    themeToSave.name = themeName
    
    -- Check if theme already exists
    for i, theme in ipairs(self.customThemes) do
        if theme.name == themeName then
            -- Update existing
            self.customThemes[i] = themeToSave
            -- If this is the current custom theme, update currentCustomTheme
            if self.themeIndex == -1 and self.customThemeName == themeName then
                self.currentCustomTheme = themeToSave
            end
            -- Save to persistence
            self:saveThemes()
            return true
        end
    end
    -- Add new theme
    table.insert(self.customThemes, themeToSave)
    -- If saving current edited built-in theme, switch to it
    if self.isEditingBuiltInTheme and self.currentCustomTheme == themeToSave then
        self.themeIndex = -1
        self.customThemeName = themeName
        self.isEditingBuiltInTheme = false
    end
    -- Save to persistence
    self:saveThemes()
    return true
end

-- Delete custom theme
function M.Themes:deleteCustomTheme(themeName)
    for i, theme in ipairs(self.customThemes) do
        if theme.name == themeName then
            table.remove(self.customThemes, i)
            -- If this was the current theme, reset to default (Classic)
            if self.customThemeName == themeName then
                self.themeIndex = 0  -- Reset to Classic
                self.customThemeName = ""
            end
            -- Save to persistence
            self:saveThemes()
            return true
        end
    end
    return false, "Theme not found: " .. themeName
end

-- Get available presets (empty - presets removed, use built-in themes instead)
function M.Themes:getAvailablePresets()
    return {}
end

return M

