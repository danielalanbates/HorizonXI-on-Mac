-- constants/colors.lua
-- Color palette and status colors
-- Format: {r, g, b, a} where each component is 0.0 - 1.0
--
-- Usage: local Colors = require("constants.colors")
--        imgui.PushStyleColor(ImGuiCol_WindowBg, Colors.TRANSPARENT)

local M = {}

--------------------------------------------------------------------------------
-- Basic Colors
--------------------------------------------------------------------------------

M.WHITE = {1.0, 1.0, 1.0, 1.0}
M.BLACK = {0.0, 0.0, 0.0, 1.0}
M.TRANSPARENT = {0.0, 0.0, 0.0, 0.0}

--------------------------------------------------------------------------------
-- Status Indicator Colors
--------------------------------------------------------------------------------

M.STATUS = {
    ONLINE = {0.0, 1.0, 0.0, 1.0},        -- Green
    OFFLINE = {0.5, 0.5, 0.5, 1.0},       -- Gray
    AWAY = {1.0, 0.7, 0.2, 1.0},          -- Orange/amber
    INVISIBLE = {0.3, 0.3, 0.3, 1.0},     -- Dark gray
    ANONYMOUS = {0.4, 0.65, 0.85, 1.0},   -- Dark sky blue
}

--------------------------------------------------------------------------------
-- Button States (for disabled/inactive buttons)
--------------------------------------------------------------------------------

M.BUTTON = {
    DISABLED = {0.3, 0.3, 0.3, 1.0},
    DISABLED_TEXT = {0.5, 0.5, 0.5, 1.0},
}

--------------------------------------------------------------------------------
-- UI Element Colors
--------------------------------------------------------------------------------

M.UI = {
    HEADER_TRANSPARENT = {0.0, 0.0, 0.0, 0.0},
    POPUP_BG = {0.2, 0.2, 0.2, 0.9},
    DIMMED_TEXT = {0.6, 0.6, 0.6, 1.0},
    SELECTED_BUTTON = {0.2, 0.5, 0.8, 1.0},
    SELECTED_BUTTON_HOVER = {0.3, 0.6, 0.9, 1.0},
    SELECTED_BUTTON_ACTIVE = {0.1, 0.4, 0.7, 1.0},
    SIDEBAR_BUTTON_HOVER = {0.3, 0.6, 0.9, 1.0},
}

--------------------------------------------------------------------------------
-- Toast/Notification Colors
--------------------------------------------------------------------------------

M.TOAST = {
    INFO = {0.2, 0.6, 1.0, 1.0},          -- Blue
    SUCCESS = {0.2, 0.8, 0.2, 1.0},       -- Green
    WARNING = {1.0, 0.8, 0.0, 1.0},       -- Yellow
    ERROR = {1.0, 0.3, 0.3, 1.0},         -- Red
    FRIEND_ONLINE = {0.2, 0.8, 0.2, 1.0}, -- Green (same as success)
    FRIEND_OFFLINE = {0.5, 0.5, 0.5, 1.0},-- Gray
    FRIEND_REQUEST = {0.2, 0.6, 1.0, 1.0},-- Blue
    MAIL = {1.0, 0.6, 0.2, 1.0},          -- Orange
}

--------------------------------------------------------------------------------
-- Help Tab / Command Colors
--------------------------------------------------------------------------------

M.HELP = {
    COMMAND = {0.9, 0.9, 0.6, 1.0},       -- Light yellow
    SECTION = {0.7, 0.9, 1.0, 1.0},       -- Light cyan
    WELCOME = {0.4, 0.8, 1.0, 1.0},       -- Bright cyan
}

--------------------------------------------------------------------------------
-- Danger/Action Colors
--------------------------------------------------------------------------------

M.ACTION = {
    ACCEPT = {0.2, 0.6, 0.2, 1.0},        -- Green
    REJECT = {0.6, 0.2, 0.2, 1.0},        -- Red
}

--------------------------------------------------------------------------------
-- Helper: Create color with modified alpha
--------------------------------------------------------------------------------

function M.withAlpha(color, alpha)
    return {color[1], color[2], color[3], alpha}
end

--------------------------------------------------------------------------------
-- Helper: Validate color table (for theme loading)
--------------------------------------------------------------------------------

function M.isValidColor(color)
    if type(color) ~= "table" then return false end
    if #color < 3 then return false end
    for i = 1, math.min(#color, 4) do
        if type(color[i]) ~= "number" then return false end
        if color[i] < 0.0 or color[i] > 1.0 then return false end
    end
    return true
end

return M
