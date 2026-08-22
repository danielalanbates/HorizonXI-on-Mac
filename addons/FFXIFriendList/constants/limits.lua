-- constants/limits.lua
-- Validation limits and thresholds
-- Re-exports existing limits from core/util.lua and adds addon-specific ones
--
-- Usage: local Limits = require("constants.limits")
--        if #name > Limits.CHARACTER_NAME_MAX then error("Name too long") end

local M = {}

--------------------------------------------------------------------------------
-- Character/String Length Limits
-- Mirrored from core/util.lua for convenience
--------------------------------------------------------------------------------

M.CHARACTER_NAME_MAX = 16
M.FRIEND_NAME_MAX = 16
M.NOTE_MAX = 8192
M.MAIL_SUBJECT_MAX = 100
M.MAIL_BODY_MAX = 2000
M.ZONE_MAX = 100
M.JOB_MAX = 50
M.RANK_MAX = 50

--------------------------------------------------------------------------------
-- List/Array Size Limits
--------------------------------------------------------------------------------

M.MAX_FRIEND_LIST_SIZE = 1000
M.MAX_BLOCKED_LIST_SIZE = 500
M.MAX_TAGS = 100
M.MAX_PENDING_REQUESTS = 100

--------------------------------------------------------------------------------
-- Network Limits
--------------------------------------------------------------------------------

M.MAX_IN_FLIGHT_REQUESTS = 8
M.POLL_CALLS_PER_FRAME = 3

--------------------------------------------------------------------------------
-- UI Limits
--------------------------------------------------------------------------------

M.MAX_TOAST_NOTIFICATIONS = 5
M.MAX_RING_BUFFER_SIZE = 32

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Reconnection Limits
--------------------------------------------------------------------------------

M.MAX_RECONNECT_ATTEMPTS = 30

return M
