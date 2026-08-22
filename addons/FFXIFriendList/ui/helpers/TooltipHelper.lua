-- ui/helpers/TooltipHelper.lua
-- Helper for rendering tooltips that work with or without interaction disabled
-- Provides a hover detection mechanism that works even when ImGuiWindowFlags_NoInputs is set

local imgui = require('imgui')

local M = {}

-- Track hover state via invisible button overlay when interaction is disabled
local hoverState = {
    currentItem = nil,
    lastMousePos = {0, 0},
}

--- Check if a rectangular region is hovered
-- Works even when NoInputs flag is set by checking mouse position directly
-- @param minX number Left edge of region
-- @param minY number Top edge of region
-- @param maxX number Right edge of region
-- @param maxY number Bottom edge of region
-- @return boolean True if mouse is within the region
function M.isRegionHovered(minX, minY, maxX, maxY)
    local mouseX, mouseY = imgui.GetMousePos()
    return mouseX >= minX and mouseX <= maxX and mouseY >= minY and mouseY <= maxY
end

--- Check if the last item is hovered, with fallback for disabled interaction
-- Call this after rendering an item to check hover state
-- When disableInteraction is true, uses screen-space mouse position check
-- @param disableInteraction boolean Whether interaction is disabled
-- @param itemId string|nil Optional item ID for tracking
-- @return boolean True if the item is hovered
function M.isItemHovered(disableInteraction, itemId)
    if not disableInteraction then
        -- Normal path: use ImGui's hover detection
        return imgui.IsItemHovered()
    end
    
    -- Disabled interaction path: check mouse position against item rect
    local minX, minY = imgui.GetItemRectMin()
    local maxX, maxY = imgui.GetItemRectMax()
    
    return M.isRegionHovered(minX, minY, maxX, maxY)
end

--- Begin a tooltip if the previous item is hovered (works with disabled interaction)
-- @param disableInteraction boolean Whether interaction is disabled
-- @return boolean True if tooltip should be rendered (caller should end with EndTooltip)
function M.beginTooltipIfHovered(disableInteraction)
    local hovered = M.isItemHovered(disableInteraction)
    if hovered then
        imgui.BeginTooltip()
        return true
    end
    return false
end

--- Render a text item and provide hover detection for tooltip
-- Returns whether the item is hovered
-- @param text string The text to render
-- @param disableInteraction boolean Whether interaction is disabled
-- @return boolean True if the text item is hovered
function M.renderTextWithHover(text, disableInteraction)
    imgui.Text(text)
    return M.isItemHovered(disableInteraction)
end

--- Render a selectable or text based on interaction mode, with unified hover detection
-- When interaction is disabled, renders as text but still detects hover
-- @param text string The text to display
-- @param uniqueId string Unique ID for the selectable
-- @param disableInteraction boolean Whether interaction is disabled
-- @param selected boolean Whether the item is selected (only applies when interactive)
-- @param selectableFlags number Optional selectable flags
-- @return clicked boolean Whether the item was clicked (false when disabled)
-- @return hovered boolean Whether the item is hovered
function M.renderSelectableOrText(text, uniqueId, disableInteraction, selected, selectableFlags)
    selected = selected or false
    selectableFlags = selectableFlags or 0
    
    local clicked = false
    local hovered = false
    
    if disableInteraction then
        imgui.Text(text)
        hovered = M.isItemHovered(true)
    else
        clicked = imgui.Selectable(text .. "##" .. uniqueId, selected, selectableFlags)
        hovered = imgui.IsItemHovered()
    end
    
    return clicked, hovered
end

return M
