local util = require("core.util")

local M = {}

local function isValidCharacterNameChar(c)
    local code = string.byte(c)
    return (code >= 48 and code <= 57) or
           (code >= 65 and code <= 90) or
           (code >= 97 and code <= 122) or
           code == 0x20 or
           code == 0x2D or
           code == 0x5F or
           code == 0x27
end

local function isValidZoneChar(c)
    local code = string.byte(c)
    return (code >= 48 and code <= 57) or
           (code >= 65 and code <= 90) or
           (code >= 97 and code <= 122) or
           c == " " or c == "-" or c == "_" or c == "'" or c == "."
end

local function isValidJobRankChar(c)
    local code = string.byte(c)
    return (code >= 48 and code <= 57) or
           (code >= 65 and code <= 90) or
           (code >= 97 and code <= 122) or
           c == " " or c == "-" or c == "_" or c == "'"
end

function M.removeControlChars(str, allowNewlines)
    allowNewlines = allowNewlines or false
    local result = {}
    
    for i = 1, #str do
        local c = string.sub(str, i, i)
        local code = string.byte(c)
        
        if code >= 0x20 or code == 0x09 then
            table.insert(result, c)
        elseif allowNewlines and (code == 0x0A or code == 0x0D) then
            table.insert(result, c)
        end
    end
    
    return table.concat(result, "")
end

function M.trim(str)
    if not str or str == "" then
        return str
    end
    
    local start = 1
    local len = #str
    
    while start <= len do
        local c = string.sub(str, start, start)
        local code = string.byte(c)
        if not (code == 0x20 or code == 0x09 or code == 0x0A or code == 0x0D) then
            break
        end
        start = start + 1
    end
    
    if start > len then
        return ""
    end
    
    local finish = len
    while finish >= start do
        local c = string.sub(str, finish, finish)
        local code = string.byte(c)
        if not (code == 0x20 or code == 0x09 or code == 0x0A or code == 0x0D) then
            break
        end
        finish = finish - 1
    end
    
    return string.sub(str, start, finish)
end

function M.collapseWhitespace(str)
    local result = {}
    local lastWasSpace = false
    
    for i = 1, #str do
        local c = string.sub(str, i, i)
        local code = string.byte(c)
        local isSpace = (code == 0x20 or code == 0x09 or code == 0x0A or code == 0x0D)
        
        if isSpace then
            if not lastWasSpace then
                table.insert(result, " ")
                lastWasSpace = true
            end
        else
            table.insert(result, c)
            lastWasSpace = false
        end
    end
    
    return table.concat(result, "")
end

function M.sanitizeForLogging(str)
    local result = {}
    
    for i = 1, #str do
        local c = string.sub(str, i, i)
        if c == "\n" then
            table.insert(result, "\\n")
        elseif c == "\r" then
            table.insert(result, "\\n")
        elseif c == "\t" then
            table.insert(result, "\\t")
        else
            local code = string.byte(c)
            if code >= 0x20 then
                table.insert(result, c)
            end
        end
    end
    
    return table.concat(result, "")
end

function M.validateCharacterName(name, maxLength)
    maxLength = maxLength or util.Limits.CHARACTER_NAME_MAX
    
    if not name or name == "" then
        return util.ValidationResult.new(false, "Character name is required", "")
    end
    
    local sanitized = M.removeControlChars(name, false)
    sanitized = M.trim(sanitized)
    
    if sanitized == "" then
        return util.ValidationResult.new(false, "Character name cannot be empty", "")
    end
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Character name must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    for i = 1, #sanitized do
        local c = string.sub(sanitized, i, i)
        if not isValidCharacterNameChar(c) then
            return util.ValidationResult.new(false,
                "Character name contains invalid characters. Only letters, numbers, spaces, hyphens, underscores, and apostrophes are allowed.", "")
        end
    end
    
    local lower = string.lower(sanitized)
    
    return util.ValidationResult.new(true, "", lower)
end

function M.validateFriendName(name, maxLength)
    return M.validateCharacterName(name, maxLength)
end

function M.validateNoteText(noteText, maxLength)
    maxLength = maxLength or util.Limits.NOTE_MAX
    
    if not noteText or noteText == "" then
        return util.ValidationResult.new(false, "Note text is required", "")
    end
    
    local sanitized = M.removeControlChars(noteText, true)
    sanitized = M.trim(sanitized)
    
    if sanitized == "" then
        return util.ValidationResult.new(false, "Note text cannot be empty or whitespace-only", "")
    end
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Note text must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    return util.ValidationResult.new(true, "", sanitized)
end

function M.validateMailSubject(subject, maxLength)
    maxLength = maxLength or util.Limits.MAIL_SUBJECT_MAX
    
    if not subject or subject == "" then
        return util.ValidationResult.new(false, "Mail subject is required", "")
    end
    
    local temp = {}
    for i = 1, #subject do
        local c = string.sub(subject, i, i)
        local code = string.byte(c)
        if code == 0x0A or code == 0x0D then
            table.insert(temp, " ")
        elseif code >= 0x20 or code == 0x09 then
            table.insert(temp, c)
        end
    end
    temp = table.concat(temp, "")
    
    local sanitized = M.collapseWhitespace(M.trim(temp))
    
    if sanitized == "" then
        return util.ValidationResult.new(false, "Mail subject cannot be empty", "")
    end
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Mail subject must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    return util.ValidationResult.new(true, "", sanitized)
end

function M.validateMailBody(body, maxLength)
    maxLength = maxLength or util.Limits.MAIL_BODY_MAX
    
    if not body or body == "" then
        return util.ValidationResult.new(false, "Mail body is required", "")
    end
    
    local sanitized = M.removeControlChars(body, true)
    sanitized = M.trim(sanitized)
    
    if sanitized == "" then
        return util.ValidationResult.new(false, "Mail body cannot be empty", "")
    end
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Mail body must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    return util.ValidationResult.new(true, "", sanitized)
end

function M.validateZone(zone, maxLength)
    maxLength = maxLength or util.Limits.ZONE_MAX
    
    if not zone or zone == "" then
        return util.ValidationResult.new(true, "", "")
    end
    
    local sanitized = M.removeControlChars(zone, false)
    sanitized = M.collapseWhitespace(M.trim(sanitized))
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Zone must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    if sanitized ~= "" then
        for i = 1, #sanitized do
            local c = string.sub(sanitized, i, i)
            if not isValidZoneChar(c) then
                return util.ValidationResult.new(false, "Zone contains invalid characters", "")
            end
        end
    end
    
    return util.ValidationResult.new(true, "", sanitized)
end

function M.validateJob(job, maxLength)
    maxLength = maxLength or util.Limits.JOB_MAX
    
    if not job or job == "" then
        return util.ValidationResult.new(true, "", "")
    end
    
    local sanitized = M.removeControlChars(job, false)
    sanitized = M.collapseWhitespace(M.trim(sanitized))
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Job must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    if sanitized ~= "" then
        for i = 1, #sanitized do
            local c = string.sub(sanitized, i, i)
            if not isValidJobRankChar(c) then
                return util.ValidationResult.new(false, "Job contains invalid characters", "")
            end
        end
    end
    
    return util.ValidationResult.new(true, "", sanitized)
end

function M.validateRank(rank, maxLength)
    maxLength = maxLength or util.Limits.RANK_MAX
    
    if not rank or rank == "" then
        return util.ValidationResult.new(true, "", "")
    end
    
    local sanitized = M.removeControlChars(rank, false)
    sanitized = M.collapseWhitespace(M.trim(sanitized))
    
    if #sanitized > maxLength then
        return util.ValidationResult.new(false,
            "Rank must be " .. tostring(maxLength) .. " characters or less", "")
    end
    
    if sanitized ~= "" then
        for i = 1, #sanitized do
            local c = string.sub(sanitized, i, i)
            if not isValidJobRankChar(c) then
                return util.ValidationResult.new(false, "Rank contains invalid characters", "")
            end
        end
    end
    
    return util.ValidationResult.new(true, "", sanitized)
end

function M.normalizeNameTitleCase(name)
    if not name or name == "" then
        return name
    end
    
    local result = {}
    local capitalizeNext = true
    
    for i = 1, #name do
        local c = string.sub(name, i, i)
        local code = string.byte(c)
        local isSpace = (code == 0x20 or code == 0x09 or code == 0x0A or code == 0x0D)
        
        if isSpace or c == "-" or c == "_" or c == "'" then
            table.insert(result, c)
            capitalizeNext = true
        elseif capitalizeNext then
            table.insert(result, string.upper(c))
            capitalizeNext = false
        else
            table.insert(result, string.lower(c))
        end
    end
    
    return table.concat(result, "")
end

M.isValidCharacterNameChar = isValidCharacterNameChar

return M

