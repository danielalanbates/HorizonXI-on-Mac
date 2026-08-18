-- ui/helpers/IconText.lua
-- Shared helper for consistent icon+text layout with proper vertical alignment
-- Centralizes icon sizing, spacing, and alignment across all UI components

local imgui = require('imgui')
local icons = require('libs.icons')

local M = {}

-- Standard icon sizes for different contexts
M.ICON_SIZE = {
    SMALL = 12,     -- Compact lists, inline text
    MEDIUM = 16,    -- Standard list rows, tooltips
    LARGE = 20,     -- Detailed views, headers
}

-- Standard spacing between icon and text
M.SPACING = {
    TIGHT = 2,
    NORMAL = 4,
    WIDE = 8,
}

--- Render an icon followed by text with proper vertical alignment
-- @param iconName string The icon name to render (from icons module)
-- @param text string The text to display after the icon
-- @param iconSize number Optional icon size (default: MEDIUM)
-- @param spacing number Optional spacing between icon and text (default: NORMAL)
-- @return boolean True if icon was rendered, false if fallback text was used
function M.render(iconName, text, iconSize, spacing)
    iconSize = iconSize or M.ICON_SIZE.MEDIUM
    spacing = spacing or M.SPACING.NORMAL
    
    -- Get current cursor position for alignment calculation
    local startPosX, startPosY = imgui.GetCursorPos()
    
    -- Calculate vertical offset to center icon with text baseline
    -- Font height is typically ~14px, icons should be centered
    local lineHeight = imgui.GetTextLineHeight()
    local iconOffset = math.max(0, (lineHeight - iconSize) / 2)
    
    -- Render the icon
    local iconRendered = false
    if iconName and iconName ~= "" then
        -- Offset cursor for vertical centering
        imgui.SetCursorPos({startPosX, startPosY + iconOffset})
        iconRendered = icons.RenderIcon(iconName, iconSize, iconSize)
    end
    
    -- Restore vertical position and move past icon
    if iconRendered then
        imgui.SameLine(0, spacing)
        -- Align text to frame padding for consistent baseline
        imgui.AlignTextToFramePadding()
    end
    
    -- Render the text
    if text and text ~= "" then
        imgui.Text(tostring(text))
    end
    
    return iconRendered
end

--- Render an icon with custom vertical alignment
-- @param iconName string The icon name to render
-- @param iconSize number The icon size
-- @param spacing number Optional spacing after icon (default: NORMAL)
-- @return boolean True if icon was rendered
function M.renderIconAligned(iconName, iconSize, spacing)
    iconSize = iconSize or M.ICON_SIZE.MEDIUM
    spacing = spacing or M.SPACING.NORMAL
    
    local startPosX, startPosY = imgui.GetCursorPos()
    local lineHeight = imgui.GetTextLineHeight()
    local iconOffset = math.max(0, (lineHeight - iconSize) / 2)
    
    imgui.SetCursorPos({startPosX, startPosY + iconOffset})
    local rendered = icons.RenderIcon(iconName, iconSize, iconSize)
    
    if rendered then
        -- Reset Y position to original baseline for text
        local afterIconX = imgui.GetCursorPosX()
        imgui.SetCursorPos({afterIconX, startPosY})
        imgui.SameLine(0, spacing)
    end
    
    return rendered
end

--- Prepare cursor for text after an icon (call after RenderIcon manually)
-- Use this when you need more control over the rendering
-- @param spacing number Optional spacing (default: NORMAL)
function M.prepareTextAfterIcon(spacing)
    spacing = spacing or M.SPACING.NORMAL
    imgui.SameLine(0, spacing)
    imgui.AlignTextToFramePadding()
end

return M
