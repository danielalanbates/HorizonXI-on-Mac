-- constants/init.lua
-- Aggregator module for all addon constants
-- Provides convenient single-import access while keeping files small
--
-- Usage Options:
--   local C = require("constants")
--   C.UI.WINDOW_SIZES.QUICK_ONLINE
--   C.Colors.TRANSPARENT
--
--   OR import specific modules:
--   local UI = require("constants.ui")
--   local Colors = require("constants.colors")

local M = {}

-- UI constants (window sizes, spacing, layout)
M.UI = require("constants.ui")

-- Color palette and status colors
M.Colors = require("constants.colors")

-- Asset filenames (sounds, icons)
M.Assets = require("constants.assets")

-- Validation limits and thresholds
M.Limits = require("constants.limits")

--------------------------------------------------------------------------------
-- Re-export core constants for unified access
-- These already exist and are mature - don't duplicate, just re-export
--------------------------------------------------------------------------------

-- Timing constants (heartbeat, retry delays, notification durations)
M.Timings = require("core.TimingConstants")

-- Network constants (rate limits, request limits)
M.Network = require("core.NetworkConstants")

-- Server configuration (base URL, WS path)
M.Server = require("core.ServerConfig")

--------------------------------------------------------------------------------
-- Version info
--------------------------------------------------------------------------------

M.VERSION = "1.0.0"  -- Constants module version for migration tracking

return M
