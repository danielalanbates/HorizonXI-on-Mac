--[[
* ThemePersistence
* Loads and saves theme state from/to INI files
]]

local PathUtils = require('platform.assets.PathUtils')
local Models = require('core.models')

local M = {}

-- Helper: Trim whitespace from string
local function trimString(str)
    return str:match("^%s*(.-)%s*$")
end

-- Helper: Parse color string "r,g,b,a" to {r, g, b, a}
local function parseColor(colorStr)
    local components = {}
    for component in colorStr:gmatch("([^,]+)") do
        local trimmed = trimString(component)
        local num = tonumber(trimmed)
        if num then
            table.insert(components, num)
        end
    end
    
    if #components >= 3 then
        return {
            r = components[1],
            g = components[2] or 0.0,
            b = components[3] or 0.0,
            a = components[4] or 1.0
        }
    end
    
    return {r = 0.0, g = 0.0, b = 0.0, a = 1.0}
end

-- Helper: Format color {r, g, b, a} to "r,g,b,a" string
local function formatColor(color)
    return string.format("%.6f,%.6f,%.6f,%.6f", color.r, color.g, color.b, color.a)
end

-- Helper: Read INI value from [Settings] section (case-insensitive)
local function readIniValue(filePath, key)
    local file = io.open(filePath, "r")
    if not file then
        return ""
    end
    
    local isInSettingsSection = false
    local lowerSearchKey = string.lower(key)
    
    for line in file:lines() do
        local trimmed = trimString(line)
        
        if trimmed == "" or trimmed:match("^[;#]") then
            -- Skip comments and empty lines
        elseif trimmed:match("^%[") then
            -- Section header
            local section = trimmed:match("%[([^%]]+)%]")
            if section then
                isInSettingsSection = (string.lower(section) == "settings")
            end
        elseif isInSettingsSection then
            -- Look for key=value in Settings section
            local equalsPos = trimmed:find("=")
            if equalsPos then
                local lineKey = trimString(trimmed:sub(1, equalsPos - 1))
                local value = trimString(trimmed:sub(equalsPos + 1))
                
                if string.lower(lineKey) == lowerSearchKey then
                    file:close()
                    return value
                end
            end
        end
    end
    
    file:close()
    return ""
end

-- Helper: Write INI value to [Settings] section
local function writeIniValue(filePath, key, value)
    PathUtils.ensureDirectory(filePath)
    
    local file = io.open(filePath, "r")
    local lines = {}
    local isInSettingsSection = false
    local keyWritten = false
    local lowerSearchKey = string.lower(key)
    
    if file then
        for line in file:lines() do
            local trimmed = trimString(line)
            
            if trimmed:match("^%[") then
                -- Section header
                local section = trimmed:match("%[([^%]]+)%]")
                if section then
                    isInSettingsSection = (string.lower(section) == "settings")
                end
                table.insert(lines, line)
            elseif isInSettingsSection and not keyWritten then
                -- Check if this line is the key we want to write
                local equalsPos = trimmed:find("=")
                if equalsPos then
                    local lineKey = trimString(trimmed:sub(1, equalsPos - 1))
                    if string.lower(lineKey) == lowerSearchKey then
                        -- Replace existing value
                        table.insert(lines, key .. "=" .. tostring(value))
                        keyWritten = true
                    else
                        table.insert(lines, line)
                    end
                else
                    table.insert(lines, line)
                end
            else
                table.insert(lines, line)
            end
        end
        file:close()
    end
    
    -- If key wasn't found, add it to [Settings] section
    if not keyWritten then
        -- Find or create [Settings] section
        local settingsIndex = nil
        for i, line in ipairs(lines) do
            if line:match("%[Settings%]") or line:match("%[settings%]") then
                settingsIndex = i
                break
            end
        end
        
        if settingsIndex then
            -- Insert after [Settings] line
            table.insert(lines, settingsIndex + 1, key .. "=" .. tostring(value))
        else
            -- Add [Settings] section and key
            table.insert(lines, "[Settings]")
            table.insert(lines, key .. "=" .. tostring(value))
        end
    end
    
    -- Write file
    file = io.open(filePath, "w")
    if file then
        for _, line in ipairs(lines) do
            file:write(line .. "\n")
        end
        file:close()
        return true
    end
    
    return false
end

-- Get config path (ffxifriendlist.ini)
local function getConfigPath()
    return PathUtils.getConfigPath("ffxifriendlist.ini")
end

-- Get custom themes path (CustomThemes.ini)
local function getCustomThemesPath()
    return PathUtils.getConfigPath("CustomThemes.ini")
end

-- Load theme state from files
function M.loadFromFile()
    local state = {
        themeIndex = 0,
        presetName = "",
        customThemeName = "",
        backgroundAlpha = 0.95,
        textAlpha = 1.0,
        fontSizePx = 14,
        customThemes = {}
    }
    
    local configPath = getConfigPath()
    
    -- Read theme index
    local themeIndexStr = readIniValue(configPath, "Theme")
    if themeIndexStr and themeIndexStr ~= "" then
        local themeIndex = tonumber(themeIndexStr)
        if themeIndex and themeIndex >= -2 and themeIndex <= Models.MAX_BUILTIN_THEME_INDEX then
            state.themeIndex = themeIndex
        end
    end
    
    -- Read preset name (try multiple variations)
    state.presetName = readIniValue(configPath, "ThemePreset")
    if state.presetName == "" then
        state.presetName = readIniValue(configPath, "themePreset")
    end
    if state.presetName == "" then
        state.presetName = readIniValue(configPath, "theme_preset")
    end
    
    -- Read custom theme name
    state.customThemeName = readIniValue(configPath, "CustomThemeName")
    
    -- Read background alpha
    local bgAlphaStr = readIniValue(configPath, "BackgroundAlpha")
    if bgAlphaStr and bgAlphaStr ~= "" then
        local alpha = tonumber(bgAlphaStr)
        if alpha and alpha >= 0.0 and alpha <= 1.0 then
            state.backgroundAlpha = alpha
        end
    end
    
    -- Read text alpha
    local textAlphaStr = readIniValue(configPath, "TextAlpha")
    if textAlphaStr and textAlphaStr ~= "" then
        local alpha = tonumber(textAlphaStr)
        if alpha and alpha >= 0.0 and alpha <= 1.0 then
            state.textAlpha = alpha
        end
    end
    
    local fontSizeStr = readIniValue(configPath, "FontSizePx")
    if fontSizeStr and fontSizeStr ~= "" then
        local size = tonumber(fontSizeStr)
        if size and (size == 14 or size == 18 or size == 24 or size == 32) then
            state.fontSizePx = size
        end
    end
    
    -- Read custom themes from separate file
    local customThemesPath = getCustomThemesPath()
    local file = io.open(customThemesPath, "r")
    if file then
        local currentThemeName = nil
        local currentTheme = nil
        local isInThemeSection = false
        
        -- Color field mapping
        local colorMap = {
            WindowBg = "windowBgColor",
            ChildBg = "childBgColor",
            FrameBg = "frameBgColor",
            FrameBgHovered = "frameBgHovered",
            FrameBgActive = "frameBgActive",
            TitleBg = "titleBg",
            TitleBgActive = "titleBgActive",
            TitleBgCollapsed = "titleBgCollapsed",
            Button = "buttonColor",
            ButtonHovered = "buttonHoverColor",
            ButtonActive = "buttonActiveColor",
            Separator = "separatorColor",
            SeparatorHovered = "separatorHovered",
            SeparatorActive = "separatorActive",
            ScrollbarBg = "scrollbarBg",
            ScrollbarGrab = "scrollbarGrab",
            ScrollbarGrabHovered = "scrollbarGrabHovered",
            ScrollbarGrabActive = "scrollbarGrabActive",
            CheckMark = "checkMark",
            SliderGrab = "sliderGrab",
            SliderGrabActive = "sliderGrabActive",
            Header = "header",
            HeaderHovered = "headerHovered",
            HeaderActive = "headerActive",
            Text = "textColor",
            TextDisabled = "textDisabled",
            Border = "borderColor"
        }
        
        for line in file:lines() do
            local trimmed = trimString(line)
            
            if trimmed == "" or trimmed:match("^[;#]") then
                -- Skip comments and empty lines
            elseif trimmed:match("^%[") then
                -- Theme section header
                if isInThemeSection and currentThemeName and currentTheme then
                    table.insert(state.customThemes, currentTheme)
                end
                
                currentThemeName = trimmed:match("%[([^%]]+)%]")
                currentTheme = {
                    name = currentThemeName or "",
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
                    borderColor = {r = 0.0, g = 0.0, b = 0.0, a = 1.0}
                }
                isInThemeSection = true
            elseif isInThemeSection then
                -- Parse key=value
                local equalsPos = trimmed:find("=")
                if equalsPos then
                    local lineKey = trimString(trimmed:sub(1, equalsPos - 1))
                    local value = trimString(trimmed:sub(equalsPos + 1))
                    
                    local colorField = colorMap[lineKey]
                    if colorField and currentTheme then
                        currentTheme[colorField] = parseColor(value)
                    end
                end
            end
        end
        
        -- Add last theme if we were in a section
        if isInThemeSection and currentThemeName and currentTheme then
            table.insert(state.customThemes, currentTheme)
        end
        
        file:close()
    end
    
    return state
end

-- Save theme state to files
function M.saveToFile(state)
    local configPath = getConfigPath()
    
    -- Write theme index
    writeIniValue(configPath, "Theme", tostring(state.themeIndex))
    
    -- Write preset name (if not empty)
    if state.presetName and state.presetName ~= "" then
        writeIniValue(configPath, "ThemePreset", state.presetName)
    end
    
    -- Write custom theme name
    writeIniValue(configPath, "CustomThemeName", state.customThemeName or "")
    
    -- Write alpha values
    writeIniValue(configPath, "BackgroundAlpha", tostring(state.backgroundAlpha))
    writeIniValue(configPath, "TextAlpha", tostring(state.textAlpha))
    
    writeIniValue(configPath, "FontSizePx", tostring(state.fontSizePx or 14))
    
    -- Write custom themes to separate file
    local customThemesPath = getCustomThemesPath()
    PathUtils.ensureDirectory(customThemesPath)
    
    local file = io.open(customThemesPath, "w")
    if not file then
        return false
    end
    
    file:write("; Custom Themes for XIFriendList\n")
    file:write("; Format: [ThemeName]\n")
    file:write("; Key=Red,Green,Blue,Alpha\n\n")
    
    for _, theme in ipairs(state.customThemes or {}) do
        file:write("[" .. (theme.name or "Unknown") .. "]\n")
        file:write("WindowBg=" .. formatColor(theme.windowBgColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ChildBg=" .. formatColor(theme.childBgColor or {r = 0.0, g = 0.0, b = 0.0, a = 0.0}) .. "\n")
        file:write("FrameBg=" .. formatColor(theme.frameBgColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("FrameBgHovered=" .. formatColor(theme.frameBgHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("FrameBgActive=" .. formatColor(theme.frameBgActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("TitleBg=" .. formatColor(theme.titleBg or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("TitleBgActive=" .. formatColor(theme.titleBgActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("TitleBgCollapsed=" .. formatColor(theme.titleBgCollapsed or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("Button=" .. formatColor(theme.buttonColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ButtonHovered=" .. formatColor(theme.buttonHoverColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ButtonActive=" .. formatColor(theme.buttonActiveColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("Separator=" .. formatColor(theme.separatorColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("SeparatorHovered=" .. formatColor(theme.separatorHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("SeparatorActive=" .. formatColor(theme.separatorActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ScrollbarBg=" .. formatColor(theme.scrollbarBg or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ScrollbarGrab=" .. formatColor(theme.scrollbarGrab or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ScrollbarGrabHovered=" .. formatColor(theme.scrollbarGrabHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("ScrollbarGrabActive=" .. formatColor(theme.scrollbarGrabActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("CheckMark=" .. formatColor(theme.checkMark or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("SliderGrab=" .. formatColor(theme.sliderGrab or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("SliderGrabActive=" .. formatColor(theme.sliderGrabActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("Header=" .. formatColor(theme.header or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("HeaderHovered=" .. formatColor(theme.headerHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("HeaderActive=" .. formatColor(theme.headerActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("Text=" .. formatColor(theme.textColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        file:write("TextDisabled=" .. formatColor(theme.textDisabled or {r = 0.0, g = 0.0, b = 0.0, a = 1.0}) .. "\n")
        if theme.borderColor then
            file:write("Border=" .. formatColor(theme.borderColor) .. "\n")
        end
        file:write("\n")
    end
    
    file:close()
    return true
end

return M
