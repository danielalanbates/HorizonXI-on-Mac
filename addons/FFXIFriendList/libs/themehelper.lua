--[[
* ThemeHelper
* Converts theme colors to ImGui style tokens and manages push/pop stack
* Never mutates state - only applies styles to ImGui
]]

local imgui = require('imgui')

local M = {}

-- Error logging helper (only for actual errors)
local function errorLog(message)
    print("[FFXIFriendList ThemeHelper ERROR] " .. tostring(message))
    if _G.FFXIFriendListApp and _G.FFXIFriendListApp.deps and _G.FFXIFriendListApp.deps.logger and _G.FFXIFriendListApp.deps.logger.error then
        _G.FFXIFriendListApp.deps.logger.error("[ThemeHelper] " .. tostring(message))
    end
end

-- Validate color value is a number in valid range
local function validateColorComponent(value, name)
    if type(value) ~= "number" then
        errorLog("Invalid color component " .. tostring(name) .. ": not a number, got " .. type(value))
        return false
    end
    if value < 0.0 or value > 1.0 then
        errorLog("Invalid color component " .. tostring(name) .. ": out of range [0.0-1.0], got " .. tostring(value))
        return false
    end
    if value ~= value then -- NaN check
        errorLog("Invalid color component " .. tostring(name) .. ": NaN")
        return false
    end
    return true
end

-- Validate color table structure
local function validateColorTable(color, name)
    if not color then
        errorLog("Color table " .. tostring(name) .. " is nil")
        return false
    end
    if type(color) ~= "table" then
        errorLog("Color table " .. tostring(name) .. " is not a table, got " .. type(color))
        return false
    end
    if not validateColorComponent(color.r, name .. ".r") then return false end
    if not validateColorComponent(color.g, name .. ".g") then return false end
    if not validateColorComponent(color.b, name .. ".b") then return false end
    if not validateColorComponent(color.a or 1.0, name .. ".a") then return false end
    return true
end

-- ImGui style variable constants (use global if available, otherwise use fallbacks)
-- Note: Check global scope first before creating local
local ImGuiStyleVar_WindowPadding = (_G.ImGuiStyleVar_WindowPadding ~= nil) and _G.ImGuiStyleVar_WindowPadding or 0
local ImGuiStyleVar_WindowRounding = (_G.ImGuiStyleVar_WindowRounding ~= nil) and _G.ImGuiStyleVar_WindowRounding or 1
local ImGuiStyleVar_FramePadding = (_G.ImGuiStyleVar_FramePadding ~= nil) and _G.ImGuiStyleVar_FramePadding or 2
local ImGuiStyleVar_FrameRounding = (_G.ImGuiStyleVar_FrameRounding ~= nil) and _G.ImGuiStyleVar_FrameRounding or 3
local ImGuiStyleVar_ItemSpacing = (_G.ImGuiStyleVar_ItemSpacing ~= nil) and _G.ImGuiStyleVar_ItemSpacing or 4
local ImGuiStyleVar_ItemInnerSpacing = (_G.ImGuiStyleVar_ItemInnerSpacing ~= nil) and _G.ImGuiStyleVar_ItemInnerSpacing or 5
local ImGuiStyleVar_ScrollbarSize = (_G.ImGuiStyleVar_ScrollbarSize ~= nil) and _G.ImGuiStyleVar_ScrollbarSize or 6
local ImGuiStyleVar_ScrollbarRounding = (_G.ImGuiStyleVar_ScrollbarRounding ~= nil) and _G.ImGuiStyleVar_ScrollbarRounding or 7
local ImGuiStyleVar_GrabRounding = (_G.ImGuiStyleVar_GrabRounding ~= nil) and _G.ImGuiStyleVar_GrabRounding or 8

-- ImGui color constants (use global if available, otherwise use fallbacks)
local ImGuiCol_WindowBg = (_G.ImGuiCol_WindowBg ~= nil) and _G.ImGuiCol_WindowBg or 2
local ImGuiCol_ChildBg = (_G.ImGuiCol_ChildBg ~= nil) and _G.ImGuiCol_ChildBg or 3
local ImGuiCol_FrameBg = (_G.ImGuiCol_FrameBg ~= nil) and _G.ImGuiCol_FrameBg or 4
local ImGuiCol_FrameBgHovered = (_G.ImGuiCol_FrameBgHovered ~= nil) and _G.ImGuiCol_FrameBgHovered or 5
local ImGuiCol_FrameBgActive = (_G.ImGuiCol_FrameBgActive ~= nil) and _G.ImGuiCol_FrameBgActive or 6
local ImGuiCol_TitleBg = (_G.ImGuiCol_TitleBg ~= nil) and _G.ImGuiCol_TitleBg or 7
local ImGuiCol_TitleBgActive = (_G.ImGuiCol_TitleBgActive ~= nil) and _G.ImGuiCol_TitleBgActive or 8
local ImGuiCol_TitleBgCollapsed = (_G.ImGuiCol_TitleBgCollapsed ~= nil) and _G.ImGuiCol_TitleBgCollapsed or 9
local ImGuiCol_Button = (_G.ImGuiCol_Button ~= nil) and _G.ImGuiCol_Button or 10
local ImGuiCol_ButtonHovered = (_G.ImGuiCol_ButtonHovered ~= nil) and _G.ImGuiCol_ButtonHovered or 11
local ImGuiCol_ButtonActive = (_G.ImGuiCol_ButtonActive ~= nil) and _G.ImGuiCol_ButtonActive or 12
local ImGuiCol_Separator = (_G.ImGuiCol_Separator ~= nil) and _G.ImGuiCol_Separator or 13
local ImGuiCol_SeparatorHovered = (_G.ImGuiCol_SeparatorHovered ~= nil) and _G.ImGuiCol_SeparatorHovered or 14
local ImGuiCol_SeparatorActive = (_G.ImGuiCol_SeparatorActive ~= nil) and _G.ImGuiCol_SeparatorActive or 15
local ImGuiCol_ScrollbarBg = (_G.ImGuiCol_ScrollbarBg ~= nil) and _G.ImGuiCol_ScrollbarBg or 16
local ImGuiCol_ScrollbarGrab = (_G.ImGuiCol_ScrollbarGrab ~= nil) and _G.ImGuiCol_ScrollbarGrab or 17
local ImGuiCol_ScrollbarGrabHovered = (_G.ImGuiCol_ScrollbarGrabHovered ~= nil) and _G.ImGuiCol_ScrollbarGrabHovered or 18
local ImGuiCol_ScrollbarGrabActive = (_G.ImGuiCol_ScrollbarGrabActive ~= nil) and _G.ImGuiCol_ScrollbarGrabActive or 19
local ImGuiCol_CheckMark = (_G.ImGuiCol_CheckMark ~= nil) and _G.ImGuiCol_CheckMark or 20
local ImGuiCol_SliderGrab = (_G.ImGuiCol_SliderGrab ~= nil) and _G.ImGuiCol_SliderGrab or 21
local ImGuiCol_SliderGrabActive = (_G.ImGuiCol_SliderGrabActive ~= nil) and _G.ImGuiCol_SliderGrabActive or 22
local ImGuiCol_Header = (_G.ImGuiCol_Header ~= nil) and _G.ImGuiCol_Header or 23
local ImGuiCol_HeaderHovered = (_G.ImGuiCol_HeaderHovered ~= nil) and _G.ImGuiCol_HeaderHovered or 24
local ImGuiCol_HeaderActive = (_G.ImGuiCol_HeaderActive ~= nil) and _G.ImGuiCol_HeaderActive or 25
local ImGuiCol_Text = (_G.ImGuiCol_Text ~= nil) and _G.ImGuiCol_Text or 26
local ImGuiCol_TextDisabled = (_G.ImGuiCol_TextDisabled ~= nil) and _G.ImGuiCol_TextDisabled or 27
local ImGuiCol_Border = (_G.ImGuiCol_Border ~= nil) and _G.ImGuiCol_Border or 28
local ImGuiCol_PopupBg = (_G.ImGuiCol_PopupBg ~= nil) and _G.ImGuiCol_PopupBg or 29

-- Stack tracking (for validation)
local styleVarPushCount = 0
local styleColorPushCount = 0

-- Default style variables
local DEFAULT_WINDOW_PADDING = {12.0, 12.0}
local DEFAULT_WINDOW_ROUNDING = 6.0
local DEFAULT_FRAME_PADDING = {6.0, 3.0}
local DEFAULT_FRAME_ROUNDING = 3.0
local DEFAULT_ITEM_SPACING = {6.0, 4.0}
local DEFAULT_ITEM_INNER_SPACING = {4.0, 3.0}
local DEFAULT_SCROLLBAR_SIZE = 12.0
local DEFAULT_SCROLLBAR_ROUNDING = 3.0
local DEFAULT_GRAB_ROUNDING = 3.0

--[[
* Convert CustomTheme to ThemeTokens format
* @param customTheme CustomTheme structure with colors
* @param backgroundAlpha float (0.0-1.0)
* @param textAlpha float (0.0-1.0)
* @param styleVars optional table with style variables, uses defaults if nil
* @return table with ThemeTokens structure
]]
local function createThemeTokens(customTheme, backgroundAlpha, textAlpha, styleVars)
    styleVars = styleVars or {}
    
    local tokens = {
        -- Colors (from CustomTheme)
        windowBgColor = customTheme.windowBgColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        childBgColor = customTheme.childBgColor or {r = 0.0, g = 0.0, b = 0.0, a = 0.0},
        frameBgColor = customTheme.frameBgColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        frameBgHovered = customTheme.frameBgHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        frameBgActive = customTheme.frameBgActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        titleBg = customTheme.titleBg or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        titleBgActive = customTheme.titleBgActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        titleBgCollapsed = customTheme.titleBgCollapsed or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        buttonColor = customTheme.buttonColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        buttonHoverColor = customTheme.buttonHoverColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        buttonActiveColor = customTheme.buttonActiveColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        separatorColor = customTheme.separatorColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        separatorHovered = customTheme.separatorHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        separatorActive = customTheme.separatorActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarBg = customTheme.scrollbarBg or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarGrab = customTheme.scrollbarGrab or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarGrabHovered = customTheme.scrollbarGrabHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        scrollbarGrabActive = customTheme.scrollbarGrabActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        checkMark = customTheme.checkMark or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        sliderGrab = customTheme.sliderGrab or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        sliderGrabActive = customTheme.sliderGrabActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        header = customTheme.header or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        headerHovered = customTheme.headerHovered or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        headerActive = customTheme.headerActive or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        textColor = customTheme.textColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        textDisabled = customTheme.textDisabled or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        borderColor = customTheme.borderColor or {r = 0.0, g = 0.0, b = 0.0, a = 1.0},
        
        -- Style variables (from styleVars or defaults)
        windowPadding = styleVars.windowPadding or DEFAULT_WINDOW_PADDING,
        windowRounding = styleVars.windowRounding or DEFAULT_WINDOW_ROUNDING,
        framePadding = styleVars.framePadding or DEFAULT_FRAME_PADDING,
        frameRounding = styleVars.frameRounding or DEFAULT_FRAME_ROUNDING,
        itemSpacing = styleVars.itemSpacing or DEFAULT_ITEM_SPACING,
        itemInnerSpacing = styleVars.itemInnerSpacing or DEFAULT_ITEM_INNER_SPACING,
        scrollbarSize = styleVars.scrollbarSize or DEFAULT_SCROLLBAR_SIZE,
        scrollbarRounding = styleVars.scrollbarRounding or DEFAULT_SCROLLBAR_ROUNDING,
        grabRounding = styleVars.grabRounding or DEFAULT_GRAB_ROUNDING,
        
        -- Alpha values
        backgroundAlpha = backgroundAlpha or 0.95,
        textAlpha = textAlpha or 1.0
    }
    
    return tokens
end

--[[
* Push theme styles to ImGui
* @param customTheme CustomTheme structure with colors
* @param backgroundAlpha float (0.0-1.0)
* @param textAlpha float (0.0-1.0)
* @param styleVars optional table with style variables
* @return boolean true if successful, false otherwise
]]
function M.pushThemeStyles(customTheme, backgroundAlpha, textAlpha, styleVars)
    -- Safety check: don't push if already pushed (would cause imbalance)
    if styleVarPushCount > 0 or styleColorPushCount > 0 then
        errorLog("pushThemeStyles: Already pushed! vars=" .. styleVarPushCount .. ", colors=" .. styleColorPushCount .. " - popping first")
        M.popThemeStyles()
    end
    
    if not customTheme then
        errorLog("pushThemeStyles: customTheme is nil")
        return false
    end
    
    if not imgui then
        errorLog("pushThemeStyles: imgui is nil")
        return false
    end
    
    if not imgui.PushStyleVar then
        errorLog("pushThemeStyles: imgui.PushStyleVar is nil")
        return false
    end
    
    if not imgui.PushStyleColor then
        errorLog("pushThemeStyles: imgui.PushStyleColor is nil")
        return false
    end
    
    -- Ensure ImGui is in a valid state (check if Begin is available as a proxy)
    if not imgui.Begin then
        errorLog("pushThemeStyles: imgui.Begin is nil - ImGui may not be initialized")
        return false
    end
    
    -- Validate inputs before creating tokens
    if not validateColorTable(customTheme.windowBgColor, "windowBgColor") then return false end
    if not validateColorTable(customTheme.childBgColor, "childBgColor") then return false end
    if not validateColorTable(customTheme.frameBgColor, "frameBgColor") then return false end
    if not validateColorTable(customTheme.frameBgHovered, "frameBgHovered") then return false end
    if not validateColorTable(customTheme.frameBgActive, "frameBgActive") then return false end
    if not validateColorTable(customTheme.titleBg, "titleBg") then return false end
    if not validateColorTable(customTheme.titleBgActive, "titleBgActive") then return false end
    if not validateColorTable(customTheme.titleBgCollapsed, "titleBgCollapsed") then return false end
    if not validateColorTable(customTheme.buttonColor, "buttonColor") then return false end
    if not validateColorTable(customTheme.buttonHoverColor, "buttonHoverColor") then return false end
    if not validateColorTable(customTheme.buttonActiveColor, "buttonActiveColor") then return false end
    if not validateColorTable(customTheme.separatorColor, "separatorColor") then return false end
    if not validateColorTable(customTheme.separatorHovered, "separatorHovered") then return false end
    if not validateColorTable(customTheme.separatorActive, "separatorActive") then return false end
    if not validateColorTable(customTheme.scrollbarBg, "scrollbarBg") then return false end
    if not validateColorTable(customTheme.scrollbarGrab, "scrollbarGrab") then return false end
    if not validateColorTable(customTheme.scrollbarGrabHovered, "scrollbarGrabHovered") then return false end
    if not validateColorTable(customTheme.scrollbarGrabActive, "scrollbarGrabActive") then return false end
    if not validateColorTable(customTheme.checkMark, "checkMark") then return false end
    if not validateColorTable(customTheme.sliderGrab, "sliderGrab") then return false end
    if not validateColorTable(customTheme.sliderGrabActive, "sliderGrabActive") then return false end
    if not validateColorTable(customTheme.header, "header") then return false end
    if not validateColorTable(customTheme.headerHovered, "headerHovered") then return false end
    if not validateColorTable(customTheme.headerActive, "headerActive") then return false end
    if not validateColorTable(customTheme.textColor, "textColor") then return false end
    if not validateColorTable(customTheme.textDisabled, "textDisabled") then return false end
    if not validateColorTable(customTheme.borderColor or customTheme.separatorColor, "borderColor") then return false end
    
    if not validateColorComponent(backgroundAlpha or 0.95, "backgroundAlpha") then return false end
    if not validateColorComponent(textAlpha or 1.0, "textAlpha") then return false end
    
    local success, tokens = pcall(createThemeTokens, customTheme, backgroundAlpha, textAlpha, styleVars)
    if not success then
        errorLog("pushThemeStyles: createThemeTokens failed: " .. tostring(tokens))
        return false
    end
    
    -- Validate token values
    if not tokens then
        errorLog("pushThemeStyles: createThemeTokens returned nil")
        return false
    end
    
    -- Push style variables (9 total)
    -- Vec2 types use table format {x, y}, float types use direct value
    local success, err = pcall(imgui.PushStyleVar, ImGuiStyleVar_WindowPadding, tokens.windowPadding)
    if not success then
        errorLog("pushThemeStyles: PushStyleVar(WindowPadding) failed: " .. tostring(err))
        return false
    end
    styleVarPushCount = styleVarPushCount + 1
    
    -- Push remaining style vars with error handling
    local styleVarCalls = {
        {ImGuiStyleVar_WindowRounding, tokens.windowRounding, "WindowRounding"},
        {ImGuiStyleVar_FramePadding, tokens.framePadding, "FramePadding"},
        {ImGuiStyleVar_FrameRounding, tokens.frameRounding, "FrameRounding"},
        {ImGuiStyleVar_ItemSpacing, tokens.itemSpacing, "ItemSpacing"},
        {ImGuiStyleVar_ItemInnerSpacing, tokens.itemInnerSpacing, "ItemInnerSpacing"},
        {ImGuiStyleVar_ScrollbarSize, tokens.scrollbarSize, "ScrollbarSize"},
        {ImGuiStyleVar_ScrollbarRounding, tokens.scrollbarRounding, "ScrollbarRounding"},
        {ImGuiStyleVar_GrabRounding, tokens.grabRounding, "GrabRounding"}
    }
    
    for _, call in ipairs(styleVarCalls) do
        local success, err = pcall(imgui.PushStyleVar, call[1], call[2])
        if not success then
            errorLog("pushThemeStyles: PushStyleVar(" .. call[3] .. ") failed: " .. tostring(err))
            -- Rollback previous pushes
            for i = 1, styleVarPushCount do
                if imgui.PopStyleVar then
                    pcall(imgui.PopStyleVar)
                end
            end
            styleVarPushCount = 0
            return false
        end
        styleVarPushCount = styleVarPushCount + 1
    end
    
    -- Push style colors (28 total) with error handling
    -- Colors use table format {r, g, b, a}
    -- Alpha: use color's own alpha multiplied by global alpha (both controls work together)
    local bgAlpha = tokens.backgroundAlpha or 1.0
    local txtAlpha = tokens.textAlpha or 1.0
    
    local colorCalls = {
        {ImGuiCol_WindowBg, {tokens.windowBgColor.r, tokens.windowBgColor.g, tokens.windowBgColor.b, tokens.windowBgColor.a * bgAlpha}, "WindowBg"},
        {ImGuiCol_ChildBg, {tokens.childBgColor.r, tokens.childBgColor.g, tokens.childBgColor.b, tokens.childBgColor.a}, "ChildBg"},
        {ImGuiCol_FrameBg, {tokens.frameBgColor.r, tokens.frameBgColor.g, tokens.frameBgColor.b, tokens.frameBgColor.a}, "FrameBg"},
        {ImGuiCol_FrameBgHovered, {tokens.frameBgHovered.r, tokens.frameBgHovered.g, tokens.frameBgHovered.b, tokens.frameBgHovered.a}, "FrameBgHovered"},
        {ImGuiCol_FrameBgActive, {tokens.frameBgActive.r, tokens.frameBgActive.g, tokens.frameBgActive.b, tokens.frameBgActive.a}, "FrameBgActive"},
        {ImGuiCol_TitleBg, {tokens.titleBg.r, tokens.titleBg.g, tokens.titleBg.b, tokens.titleBg.a}, "TitleBg"},
        {ImGuiCol_TitleBgActive, {tokens.titleBgActive.r, tokens.titleBgActive.g, tokens.titleBgActive.b, tokens.titleBgActive.a}, "TitleBgActive"},
        {ImGuiCol_TitleBgCollapsed, {tokens.titleBgCollapsed.r, tokens.titleBgCollapsed.g, tokens.titleBgCollapsed.b, tokens.titleBgCollapsed.a}, "TitleBgCollapsed"},
        {ImGuiCol_Button, {tokens.buttonColor.r, tokens.buttonColor.g, tokens.buttonColor.b, tokens.buttonColor.a}, "Button"},
        {ImGuiCol_ButtonHovered, {tokens.buttonHoverColor.r, tokens.buttonHoverColor.g, tokens.buttonHoverColor.b, tokens.buttonHoverColor.a}, "ButtonHovered"},
        {ImGuiCol_ButtonActive, {tokens.buttonActiveColor.r, tokens.buttonActiveColor.g, tokens.buttonActiveColor.b, tokens.buttonActiveColor.a}, "ButtonActive"},
        {ImGuiCol_Separator, {tokens.separatorColor.r, tokens.separatorColor.g, tokens.separatorColor.b, tokens.separatorColor.a}, "Separator"},
        {ImGuiCol_SeparatorHovered, {tokens.separatorHovered.r, tokens.separatorHovered.g, tokens.separatorHovered.b, tokens.separatorHovered.a}, "SeparatorHovered"},
        {ImGuiCol_SeparatorActive, {tokens.separatorActive.r, tokens.separatorActive.g, tokens.separatorActive.b, tokens.separatorActive.a}, "SeparatorActive"},
        {ImGuiCol_ScrollbarBg, {tokens.scrollbarBg.r, tokens.scrollbarBg.g, tokens.scrollbarBg.b, tokens.scrollbarBg.a}, "ScrollbarBg"},
        {ImGuiCol_ScrollbarGrab, {tokens.scrollbarGrab.r, tokens.scrollbarGrab.g, tokens.scrollbarGrab.b, tokens.scrollbarGrab.a}, "ScrollbarGrab"},
        {ImGuiCol_ScrollbarGrabHovered, {tokens.scrollbarGrabHovered.r, tokens.scrollbarGrabHovered.g, tokens.scrollbarGrabHovered.b, tokens.scrollbarGrabHovered.a}, "ScrollbarGrabHovered"},
        {ImGuiCol_ScrollbarGrabActive, {tokens.scrollbarGrabActive.r, tokens.scrollbarGrabActive.g, tokens.scrollbarGrabActive.b, tokens.scrollbarGrabActive.a}, "ScrollbarGrabActive"},
        {ImGuiCol_CheckMark, {tokens.checkMark.r, tokens.checkMark.g, tokens.checkMark.b, tokens.checkMark.a}, "CheckMark"},
        {ImGuiCol_SliderGrab, {tokens.sliderGrab.r, tokens.sliderGrab.g, tokens.sliderGrab.b, tokens.sliderGrab.a}, "SliderGrab"},
        {ImGuiCol_SliderGrabActive, {tokens.sliderGrabActive.r, tokens.sliderGrabActive.g, tokens.sliderGrabActive.b, tokens.sliderGrabActive.a}, "SliderGrabActive"},
        {ImGuiCol_Header, {tokens.header.r, tokens.header.g, tokens.header.b, tokens.header.a}, "Header"},
        {ImGuiCol_HeaderHovered, {tokens.headerHovered.r, tokens.headerHovered.g, tokens.headerHovered.b, tokens.headerHovered.a}, "HeaderHovered"},
        {ImGuiCol_HeaderActive, {tokens.headerActive.r, tokens.headerActive.g, tokens.headerActive.b, tokens.headerActive.a}, "HeaderActive"},
        {ImGuiCol_Text, {tokens.textColor.r, tokens.textColor.g, tokens.textColor.b, tokens.textColor.a * txtAlpha}, "Text"},
        {ImGuiCol_TextDisabled, {tokens.textDisabled.r, tokens.textDisabled.g, tokens.textDisabled.b, tokens.textDisabled.a}, "TextDisabled"},
        {ImGuiCol_Border, {tokens.borderColor.r, tokens.borderColor.g, tokens.borderColor.b, tokens.borderColor.a}, "Border"},
        {ImGuiCol_PopupBg, {tokens.frameBgColor.r, tokens.frameBgColor.g, tokens.frameBgColor.b, tokens.frameBgColor.a}, "PopupBg"}
    }
    
    for _, call in ipairs(colorCalls) do
        -- Validate color array before pushing
        local colorArray = call[2]
        if type(colorArray) ~= "table" then
            errorLog("pushThemeStyles: PushStyleColor(" .. call[3] .. ") color array is not a table")
            -- Rollback
            for i = 1, styleColorPushCount do
                if imgui.PopStyleColor then
                    pcall(imgui.PopStyleColor)
                end
            end
            for i = 1, styleVarPushCount do
                if imgui.PopStyleVar then
                    pcall(imgui.PopStyleVar)
                end
            end
            styleColorPushCount = 0
            styleVarPushCount = 0
            return false
        end
        if #colorArray ~= 4 then
            errorLog("pushThemeStyles: PushStyleColor(" .. call[3] .. ") color array must have 4 elements, got " .. #colorArray)
            -- Rollback
            for i = 1, styleColorPushCount do
                if imgui.PopStyleColor then
                    pcall(imgui.PopStyleColor)
                end
            end
            for i = 1, styleVarPushCount do
                if imgui.PopStyleVar then
                    pcall(imgui.PopStyleVar)
                end
            end
            styleColorPushCount = 0
            styleVarPushCount = 0
            return false
        end
        -- Validate each component
        for i = 1, 4 do
            if not validateColorComponent(colorArray[i], call[3] .. "[" .. i .. "]") then
                -- Rollback
                for j = 1, styleColorPushCount do
                    if imgui.PopStyleColor then
                        pcall(imgui.PopStyleColor)
                    end
                end
                for j = 1, styleVarPushCount do
                    if imgui.PopStyleVar then
                        pcall(imgui.PopStyleVar)
                    end
                end
                styleColorPushCount = 0
                styleVarPushCount = 0
                return false
            end
        end
        
        local success, err = pcall(imgui.PushStyleColor, call[1], colorArray)
        if not success then
            errorLog("pushThemeStyles: PushStyleColor(" .. call[3] .. ") failed: " .. tostring(err))
            errorLog("  Color values: r=" .. tostring(colorArray[1]) .. " g=" .. tostring(colorArray[2]) .. " b=" .. tostring(colorArray[3]) .. " a=" .. tostring(colorArray[4]))
            -- Rollback previous pushes
            for i = 1, styleColorPushCount do
                if imgui.PopStyleColor then
                    pcall(imgui.PopStyleColor)
                end
            end
            for i = 1, styleVarPushCount do
                if imgui.PopStyleVar then
                    pcall(imgui.PopStyleVar)
                end
            end
            styleColorPushCount = 0
            styleVarPushCount = 0
            return false
        end
        styleColorPushCount = styleColorPushCount + 1
    end
    
    return true
end

--[[
* Pop theme styles from ImGui
* Must be called after pushThemeStyles to balance the stack
* Uses individual pops for compatibility with Ashita's Lua bindings
]]
function M.popThemeStyles()
    -- Safety check: don't pop more than we've pushed
    local colorsToPop = math.min(28, styleColorPushCount)
    local varsToPop = math.min(9, styleVarPushCount)
    
    -- Pop style colors (28 total) - use individual pops for safety
    for i = 1, colorsToPop do
        if imgui and imgui.PopStyleColor then
            local success, err = pcall(imgui.PopStyleColor)
            if not success then
                errorLog("popThemeStyles: PopStyleColor failed: " .. tostring(err))
                break
            end
            styleColorPushCount = styleColorPushCount - 1
        else
            errorLog("popThemeStyles: imgui.PopStyleColor is nil")
            break
        end
    end
    
    -- Pop style variables (9 total) - use individual pops for safety
    for i = 1, varsToPop do
        if imgui and imgui.PopStyleVar then
            local success, err = pcall(imgui.PopStyleVar)
            if not success then
                errorLog("popThemeStyles: PopStyleVar failed: " .. tostring(err))
                break
            end
            styleVarPushCount = styleVarPushCount - 1
        else
            errorLog("popThemeStyles: imgui.PopStyleVar is nil")
            break
        end
    end
end

--[[
* Validate that push/pop stack is balanced
* @return boolean true if balanced, false otherwise
]]
function M.validateStackBalance()
    return styleVarPushCount == 0 and styleColorPushCount == 0
end

--[[
* Reset stack counters (for debugging/recovery)
]]
function M.resetStackCounters()
    styleVarPushCount = 0
    styleColorPushCount = 0
end

--[[
* Get current stack counts (for debugging)
* @return table with styleVarCount and styleColorCount
]]
function M.getStackCounts()
    return {
        styleVarCount = styleVarPushCount,
        styleColorCount = styleColorPushCount
    }
end

return M

