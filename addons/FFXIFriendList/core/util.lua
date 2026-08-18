local M = {}

M.Limits = {
    CHARACTER_NAME_MAX = 16,
    FRIEND_NAME_MAX = 16,
    NOTE_MAX = 8192,
    MAIL_SUBJECT_MAX = 100,
    MAIL_BODY_MAX = 2000,
    ZONE_MAX = 100,
    JOB_MAX = 50,
    RANK_MAX = 50
}

M.ValidationResult = {}
M.ValidationResult.__index = M.ValidationResult

function M.ValidationResult.new(valid, error, sanitized)
    local self = setmetatable({}, M.ValidationResult)
    self.valid = valid or false
    self.error = error or ""
    self.sanitized = sanitized or ""
    return self
end

return M

