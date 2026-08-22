-- ServerDetector.lua
-- Auto-detects which private server was launched and maps to API configuration
--
-- Detection Strategy (in order of preference):
-- 1. Ashita ConfigurationManager API - read boot command directly
-- 2. Log file parsing - find latest log and extract boot profile/command
-- 3. Manual fallback - user selects server
--
-- Usage:
--   local ServerDetector = require("platform.services.ServerDetector")
--   local detector = ServerDetector.ServerDetector.new(ashitaCore)
--   local result = detector:detect()
--   if result.success then
--       print("Detected server: " .. result.profile.name)
--   end

local ServerProfiles = require("core.ServerProfiles")

local M = {}
M.ServerDetector = {}
M.ServerDetector.__index = M.ServerDetector

-- Detection methods
M.DetectionMethod = {
    ASHITA_CONFIG = "ashita_config",   -- Read from ConfigurationManager
    LOG_FILE = "log_file",              -- Parsed from latest log file
    BOOT_INI = "boot_ini",              -- Direct boot ini file read
    MANUAL = "manual",                  -- User selected manually
    NONE = "none"                       -- No detection performed
}

-- Detection result structure
-- {
--   success = boolean,
--   method = DetectionMethod,
--   profile = ServerProfile or nil,
--   rawHost = "play.horizonxi.com",  -- The raw host string detected
--   bootProfile = "QuickBoot.ini",   -- The boot profile name if available
--   matchedPattern = string,         -- Which pattern matched
--   candidates = {},                 -- Multiple matches if ambiguous
--   error = string or nil,           -- Error message if failed
--   timestamp = number,              -- Detection timestamp (ms)
--   cached = boolean                 -- Whether result was cached
-- }

function M.ServerDetector.new(ashitaCore, logger)
    local self = setmetatable({}, M.ServerDetector)
    self.ashitaCore = ashitaCore
    self.logger = logger or {
        debug = function() end,
        info = function() end,
        warn = function() end,
        error = function() end
    }
    
    -- Detection state
    self.lastResult = nil
    self.lastDetectionTime = 0
    self.detectionCooldownMs = 5000  -- Minimum 5s between detections
    
    -- Manual override (persisted separately)
    self.manualOverride = nil
    
    return self
end

-- Main detection entry point
-- @param forceRefresh If true, ignore cache and re-detect
-- @return Detection result table
function M.ServerDetector:detect(forceRefresh)
    local now = self:_getTime()
    
    -- Return cached result if within cooldown (unless forced)
    if not forceRefresh and self.lastResult and (now - self.lastDetectionTime) < self.detectionCooldownMs then
        local cachedResult = self:_cloneResult(self.lastResult)
        cachedResult.cached = true
        return cachedResult
    end
    
    -- If manual override is set, use it
    if self.manualOverride then
        local profile = ServerProfiles.findById(self.manualOverride)
        if profile then
            local result = {
                success = true,
                method = M.DetectionMethod.MANUAL,
                profile = profile,
                rawHost = nil,
                bootProfile = nil,
                matchedPattern = nil,
                candidates = {},
                error = nil,
                timestamp = now,
                cached = false
            }
            self.lastResult = result
            self.lastDetectionTime = now
            return result
        end
    end
    
    -- Strategy 1: Try Ashita ConfigurationManager API
    local result = self:_detectFromAshitaConfig()
    if result.success then
        self.lastResult = result
        self.lastDetectionTime = now
        return result
    end
    
    -- Strategy 2: Try log file parsing as fallback (wrapped in pcall to prevent crashes)
    local logOk, logResult = pcall(function()
        return self:_detectFromLogFile()
    end)
    if logOk and logResult and logResult.success then
        self.lastResult = logResult
        self.lastDetectionTime = now
        return logResult
    end
    
    -- No detection succeeded
    result = {
        success = false,
        method = M.DetectionMethod.NONE,
        profile = nil,
        rawHost = nil,
        bootProfile = nil,
        matchedPattern = nil,
        candidates = {},
        error = "Could not detect server. Please select manually.",
        timestamp = now,
        cached = false
    }
    self.lastResult = result
    self.lastDetectionTime = now
    self:_log("warn", "Server detection failed: " .. result.error)
    return result
end

-- Strategy 1: Read from Ashita ConfigurationManager
function M.ServerDetector:_detectFromAshitaConfig()
    local now = self:_getTime()
    local result = {
        success = false,
        method = M.DetectionMethod.ASHITA_CONFIG,
        profile = nil,
        rawHost = nil,
        bootProfile = nil,
        matchedPattern = nil,
        candidates = {},
        error = nil,
        timestamp = now,
        cached = false
    }
    
    if not self.ashitaCore then
        result.error = "AshitaCore not available"
        return result
    end
    
    -- Get ConfigurationManager
    local configMgr = nil
    local success, err = pcall(function()
        configMgr = self.ashitaCore:GetConfigurationManager()
    end)
    
    if not success or not configMgr then
        result.error = "Could not get ConfigurationManager: " .. tostring(err)
        return result
    end
    
    -- Read boot command (contains --server <host>)
    local bootCommand = nil
    success, err = pcall(function()
        -- GetString signature: (alias, section, key)
        -- 'boot' is the config alias, 'ashita.boot' is the section, 'command' is the key
        bootCommand = configMgr:GetString('boot', 'ashita.boot', 'command')
    end)
    
    if not success then
        result.error = "Could not read boot command: " .. tostring(err)
        return result
    end
    
    if not bootCommand or bootCommand == "" then
        result.error = "Boot command is empty"
        return result
    end
    
    self:_log("debug", "Boot command: " .. bootCommand)
    
    -- Parse host from boot command (--server <host> or --server=<host>)
    local host = self:_parseHostFromCommand(bootCommand)
    if not host then
        result.error = "Could not parse server host from boot command"
        return result
    end
    
    result.rawHost = host
    
    -- Match host to server profile
    local profile, pattern = ServerProfiles.findByHost(host)
    if profile then
        result.success = true
        result.profile = profile
        result.matchedPattern = pattern
        return result
    end
    
    -- Host found but no matching profile
    result.error = "Unknown server host: " .. host
    return result
end

-- Strategy 2: Parse latest Ashita log file
function M.ServerDetector:_detectFromLogFile()
    local now = self:_getTime()
    local result = {
        success = false,
        method = M.DetectionMethod.LOG_FILE,
        profile = nil,
        rawHost = nil,
        bootProfile = nil,
        matchedPattern = nil,
        candidates = {},
        error = nil,
        timestamp = now,
        cached = false
    }
    
    if not self.ashitaCore then
        result.error = "AshitaCore not available"
        return result
    end
    
    -- Get install path
    local installPath = nil
    local success, err = pcall(function()
        installPath = self.ashitaCore:GetInstallPath()
    end)
    
    if not success or not installPath then
        result.error = "Could not get install path: " .. tostring(err)
        return result
    end
    
    -- Clean path
    installPath = installPath:gsub("\\$", "")
    local logsPath = installPath .. "\\logs"
    
    -- Find latest log file
    local latestLog = self:_findLatestLogFile(logsPath)
    if not latestLog then
        result.error = "No log files found in " .. logsPath
        return result
    end
    
    self:_log("debug", "Parsing log file: " .. latestLog)
    
    -- Read and parse log file (only first ~100 lines needed)
    local host, bootProfile = self:_parseLogFile(latestLog)
    
    if bootProfile then
        result.bootProfile = bootProfile
    end
    
    if not host then
        result.error = "Could not find server host in log file"
        return result
    end
    
    result.rawHost = host
    
    -- Match host to server profile
    local profile, pattern = ServerProfiles.findByHost(host)
    if profile then
        result.success = true
        result.profile = profile
        result.matchedPattern = pattern
        return result
    end
    
    -- Try matching boot profile name to server
    if bootProfile then
        profile = ServerProfiles.findById(bootProfile:gsub("%.ini$", ""))
        if profile then
            result.success = true
            result.profile = profile
            result.matchedPattern = "boot_profile_name"
            return result
        end
    end
    
    result.error = "Unknown server host from log: " .. host
    return result
end

-- Parse server host from boot command string
-- Handles: --server play.horizonxi.com, --server=play.horizonxi.com
function M.ServerDetector:_parseHostFromCommand(command)
    if not command then return nil end
    
    -- Pattern 1: --server <host> (space separated)
    local host = command:match("%-%-server%s+([^%s]+)")
    if host then return host end
    
    -- Pattern 2: --server=<host> (equals separated)
    host = command:match("%-%-server=([^%s]+)")
    if host then return host end
    
    -- Pattern 3: -s <host> (short form)
    host = command:match("%-s%s+([^%s]+)")
    if host then return host end
    
    return nil
end

-- Find the most recent log file in the logs directory
function M.ServerDetector:_findLatestLogFile(logsPath)
    if not ashita or not ashita.fs then
        return nil
    end
    
    -- Check if directory exists
    local existsOk, exists = pcall(function()
        return ashita.fs.exists(logsPath)
    end)
    if not existsOk or not exists then
        return nil
    end
    
    -- Get directory contents - wrap in pcall as this can crash
    local getDirOk, files = pcall(function()
        return ashita.fs.get_dir(logsPath, "*.txt", false)
    end)
    if not getDirOk or not files or #files == 0 then
        self:_log("debug", "Could not read logs directory: " .. tostring(files))
        return nil
    end
    if not files or #files == 0 then
        return nil
    end
    
    -- Sort by name (log files are named with timestamp: MM_DD_YYYY HH.MM.SS.txt)
    -- Most recent will be last alphabetically for same year, or we parse dates
    local latestFile = nil
    local latestTime = 0
    
    for _, filename in ipairs(files) do
        -- Parse date from filename: "01_11_2026 10.25.27.txt"
        local month, day, year, hour, min, sec = filename:match("(%d+)_(%d+)_(%d+)%s+(%d+)%.(%d+)%.(%d+)")
        if month and day and year then
            -- Convert to comparable number (YYYYMMDDHHMMSS)
            local timeNum = tonumber(string.format("%04d%02d%02d%02d%02d%02d", 
                year, month, day, hour or 0, min or 0, sec or 0))
            if timeNum and timeNum > latestTime then
                latestTime = timeNum
                latestFile = logsPath .. "\\" .. filename
            end
        end
    end
    
    return latestFile
end

-- Parse log file to extract boot profile and server host
function M.ServerDetector:_parseLogFile(logPath)
    local file = io.open(logPath, "r")
    if not file then
        return nil, nil
    end
    
    local host = nil
    local bootProfile = nil
    local lineCount = 0
    local maxLines = 100  -- Only parse first 100 lines
    
    for line in file:lines() do
        lineCount = lineCount + 1
        if lineCount > maxLines then
            break
        end
        
        -- Look for boot profile: "Ashita Config Script: \boot\QuickBoot.ini"
        if not bootProfile then
            local profile = line:match("Ashita Config Script:%s*\\?boot\\([^%s]+)")
            if profile then
                bootProfile = profile
            end
        end
        
        -- Look for command with server: "command : --server play.horizonxi.com"
        -- Note: Password may be in log, but we only extract host
        if not host then
            local cmd = line:match("command%s*:%s*(.+)")
            if cmd then
                host = self:_parseHostFromCommand(cmd)
            end
        end
        
        -- If we found both, stop early
        if host and bootProfile then
            break
        end
    end
    
    file:close()
    return host, bootProfile
end

-- Set manual server override
function M.ServerDetector:setManualOverride(serverId)
    self.manualOverride = serverId
    -- Clear cached result to force re-detection
    self.lastResult = nil
end

-- Clear manual override
function M.ServerDetector:clearManualOverride()
    self.manualOverride = nil
    self.lastResult = nil
end

-- Invalidate cached detection result (forces re-detection on next detect() call)
function M.ServerDetector:invalidateCache()
    self.lastResult = nil
    self.lastDetectionTime = 0
end

-- Get current detection result (cached)
function M.ServerDetector:getLastResult()
    return self.lastResult
end

-- Get diagnostics info for /fl diag
function M.ServerDetector:getDiagnostics()
    -- Use cached result or try to detect (wrapped in pcall for safety)
    local result = self.lastResult
    if not result then
        local detectOk, detectResult = pcall(function()
            return self:detect()
        end)
        if detectOk and detectResult then
            result = detectResult
        else
            -- Return safe error result if detection crashes
            return {
                detectionMethod = "none",
                success = false,
                serverProfile = nil,
                serverName = nil,
                apiBaseUrl = nil,
                rawHost = nil,
                bootProfile = nil,
                matchedPattern = nil,
                error = "Detection failed: " .. tostring(detectResult),
                lastDetectionTime = 0,
                manualOverride = nil,
                cached = false,
                debug = { crashedDuringDetect = true }
            }
        end
    end
    
    -- Collect additional debug info
    local debugInfo = {
        profilesLoaded = ServerProfiles.isLoaded(),
        profileCount = ServerProfiles.getCount and ServerProfiles.getCount() or #ServerProfiles.profiles,
        profileLoadError = ServerProfiles.getLoadError and ServerProfiles.getLoadError() or nil,
        bootCommand = self:_getBootCommandSafe(),
    }
    
    return {
        detectionMethod = result.method,
        success = result.success,
        serverProfile = result.profile and result.profile.id or nil,
        serverName = result.profile and result.profile.name or nil,
        apiBaseUrl = result.profile and result.profile.apiBaseUrl or nil,
        rawHost = result.rawHost,
        bootProfile = result.bootProfile,
        matchedPattern = result.matchedPattern,
        error = result.error,
        lastDetectionTime = self.lastDetectionTime,
        manualOverride = self.manualOverride,
        cached = result.cached or false,
        debug = debugInfo
    }
end

-- Internal: Safely get boot command for diagnostics (tries multiple API variations)
function M.ServerDetector:_getBootCommandSafe()
    if not self.ashitaCore then
        return "[AshitaCore not available]"
    end
    
    local ok, configMgr = pcall(function()
        return self.ashitaCore:GetConfigurationManager()
    end)
    if not ok or not configMgr then
        return "[ConfigManager not available]"
    end
    
    -- Try various API signatures and key combinations
    local attempts = {}
    
    -- Attempt 1: Original signature (alias, section, key)
    local ok1, result1 = pcall(function()
        return configMgr:GetString('boot', 'ashita.boot', 'command')
    end)
    table.insert(attempts, {
        desc = "GetString('boot', 'ashita.boot', 'command')",
        ok = ok1,
        result = ok1 and result1 or tostring(result1)
    })
    
    -- Attempt 2: Just section and key
    local ok2, result2 = pcall(function()
        return configMgr:GetString('ashita.boot', 'command')
    end)
    table.insert(attempts, {
        desc = "GetString('ashita.boot', 'command')",
        ok = ok2,
        result = ok2 and result2 or tostring(result2)
    })
    
    -- Attempt 3: Different section name
    local ok3, result3 = pcall(function()
        return configMgr:GetString('boot', 'boot', 'command')
    end)
    table.insert(attempts, {
        desc = "GetString('boot', 'boot', 'command')",
        ok = ok3,
        result = ok3 and result3 or tostring(result3)
    })
    
    -- Attempt 4: Try Get method
    local ok4, result4 = pcall(function()
        return configMgr:Get('boot', 'ashita.boot', 'command')
    end)
    table.insert(attempts, {
        desc = "Get('boot', 'ashita.boot', 'command')",
        ok = ok4,
        result = ok4 and result4 or tostring(result4)
    })
    
    -- Build debug output
    local debugParts = {}
    for _, attempt in ipairs(attempts) do
        local resultStr = attempt.result
        if resultStr == nil or resultStr == "" then
            resultStr = "[empty]"
        elseif type(resultStr) == "string" and #resultStr > 60 then
            resultStr = string.sub(resultStr, 1, 60) .. "..."
        end
        table.insert(debugParts, attempt.desc .. " => " .. (attempt.ok and tostring(resultStr) or "ERROR: " .. tostring(resultStr)))
    end
    
    return table.concat(debugParts, " | ")
end

-- Internal: Clone result table
function M.ServerDetector:_cloneResult(result)
    if not result then return nil end
    local clone = {}
    for k, v in pairs(result) do
        if type(v) == "table" then
            clone[k] = {}
            for k2, v2 in pairs(v) do
                clone[k][k2] = v2
            end
        else
            clone[k] = v
        end
    end
    return clone
end

-- Internal: Get current time in ms
function M.ServerDetector:_getTime()
    return os.time() * 1000
end

-- Internal: Log with context
function M.ServerDetector:_log(level, message)
    local prefix = "[ServerDetector] "
    if self.logger and self.logger[level] then
        self.logger[level](prefix .. message)
    end
end

return M
