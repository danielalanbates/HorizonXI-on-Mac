-- constants/ui.lua
-- UI-related constants: window sizes, spacing, layout values
-- Centralized to reduce duplication and ease future UI changes
--
-- Usage: local UI = require("constants.ui")
--        imgui.SetNextWindowSize(UI.WINDOW_SIZES.QUICK_ONLINE, ImGuiCond_FirstUseEver)

local M = {}

--------------------------------------------------------------------------------
-- Window Sizes (width, height in pixels)
-- These are defaults for SetNextWindowSize - user may resize and persist
--------------------------------------------------------------------------------

M.WINDOW_SIZES = {
    QUICK_ONLINE = {420, 320},
    NOTE_EDITOR = {500, 400},
    SERVER_SELECTION = {350, 0},  -- 0 = auto-height
    FRIEND_DETAILS = {400, 350},
    OPTIONS = {600, 400},
}

--------------------------------------------------------------------------------
-- Window IDs (ImGui ## pattern for stable internal IDs)
-- Format: ##<module>_<window>
--------------------------------------------------------------------------------

M.WINDOW_IDS = {
    FRIEND_LIST = "##friendlist_main",
    QUICK_ONLINE = "##quickonline_main",
    NOTE_EDITOR = "##noteeditor_main",
    OPTIONS = "##options_main",
    SERVER_SELECTION = "##serverselection_main",
}

--------------------------------------------------------------------------------
-- Window Titles (display text before ## ID)
--------------------------------------------------------------------------------

M.WINDOW_TITLES = {
    FRIEND_LIST = "Friend List",
    QUICK_ONLINE = "Compact Friend List",
    NOTE_EDITOR = "Edit Note",
    OPTIONS = "Options",
    SERVER_SELECTION = "Select Server",
    FRIEND_DETAILS = "Friend Details",
}

--------------------------------------------------------------------------------
-- Notification Position (default X, Y in pixels)
--------------------------------------------------------------------------------

M.NOTIFICATION_POSITION = {10.0, 15.0}

--------------------------------------------------------------------------------
-- Spacing & Padding (pixels)
--------------------------------------------------------------------------------

M.SPACING = {
    DEFAULT_PADDING = 10,
    FRAME_PADDING = {10, 8},
    TOAST_SPACING = 10.0,
    ITEM_SPACING = {8, 4},
}

--------------------------------------------------------------------------------
-- Input Field Widths (pixels, for PushItemWidth)
--------------------------------------------------------------------------------

M.INPUT_WIDTHS = {
    TINY = 64,
    SMALL = 100,
    MEDIUM = 120,
    DEFAULT = 150,
    LARGE = 200,
    EXTRA_LARGE = 300,
}

--------------------------------------------------------------------------------
-- Button Sizes
--------------------------------------------------------------------------------

M.BUTTON_SIZES = {
    DEFAULT = {164, 32},
    SMALL = {100, 0},
    MEDIUM = {120, 0},
    ICON = {24, 24},
}

--------------------------------------------------------------------------------
-- Icon Sizes (pixels)
--------------------------------------------------------------------------------

M.ICON_SIZES = {
    SMALL = 14,
    MEDIUM = 16,
    LARGE = 24,
    XLARGE = 32,
    -- Button icon sizes (image is automatically scaled by ICON_SCALE)
    TAB_ICON_BUTTON = 28,      -- Button size for sidebar tabs
    ACTION_ICON_BUTTON = 28,   -- Button size for action buttons
    SOCIAL_ICON_BUTTON = 28,   -- Button size for social icons
}

-- Icon scale factor (image size relative to button size)
M.ICON_SCALE = 0.8  -- 80% of button size

--------------------------------------------------------------------------------
-- Child Heights (pixels, for BeginChild)
--------------------------------------------------------------------------------

M.CHILD_HEIGHTS = {
    TAG_LIST = 150,
    BLOCKED_PLAYERS = 150,
    ALT_VISIBILITY = 200,
    NOTE_INPUT = 200,
}

--------------------------------------------------------------------------------
-- Column Widths (default values, user may resize)
--------------------------------------------------------------------------------

M.COLUMN_WIDTHS = {
    NAME = 120.0,
    JOB = 100.0,
    ZONE = 120.0,
    NATION_RANK = 80.0,
    LAST_SEEN = 120.0,
    ADDED_AS = 100.0,
}

--------------------------------------------------------------------------------
-- Default Alpha Values (0.0 - 1.0 range)
--------------------------------------------------------------------------------

M.ALPHA = {
    BACKGROUND = 0.95,
    TEXT = 1.0,
    POPUP_BG = 0.9,
    DISABLED = 0.5,
}

--------------------------------------------------------------------------------
-- Tooltip Layout
--------------------------------------------------------------------------------

M.TOOLTIP = {
    LABEL_WIDTH = 95,
}

--------------------------------------------------------------------------------
-- Animation Timing (ms, for UI fade effects)
--------------------------------------------------------------------------------

M.ANIMATION = {
    FADE_DURATION_MS = 200,
    ENTER_DURATION_MS = 200,
    EXIT_DURATION_MS = 200,
}

return M
