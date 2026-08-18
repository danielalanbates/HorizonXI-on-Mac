-- close_gating.lua
-- Popup/menu detection for window close gating

local imgui = require('imgui')

local M = {}

-- Check if any popup is open
function M.isAnyPopupOpen()
    -- Try imgui.IsAnyPopupOpen if available
    if imgui.IsAnyPopupOpen then
        local success, result = pcall(imgui.IsAnyPopupOpen)
        if success then
            return result
        end
    end
    
    -- Fallback: Check known popup states via IsPopupOpen
    -- This is less comprehensive but works with Ashita's imgui binding
    if imgui.IsPopupOpen then
        -- Check common popup IDs used in our windows
        local knownPopups = {
            "Friend Details##friend_details",
            "Friend Details##quick_online_details",
            "##friend_context_menu",
            "##note_editor_context",
            "##server_context"
        }
        
        for _, popupId in ipairs(knownPopups) do
            local success, isOpen = pcall(imgui.IsPopupOpen, popupId)
            if success and isOpen then
                return true
            end
        end
    end
    
    return false
end

-- Check if close should be deferred
function M.shouldDeferClose()
    return M.isAnyPopupOpen()
end

-- Check if it is safe to close windows this frame
-- Inverse of shouldDeferClose for semantic clarity
function M.isCleanForClose()
    return not M.isAnyPopupOpen()
end

return M

