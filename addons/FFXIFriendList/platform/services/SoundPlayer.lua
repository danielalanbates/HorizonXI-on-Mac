local M = {}
M.SoundPlayer = {}
M.SoundPlayer.__index = M.SoundPlayer

local ffi = nil
local winmm = nil
local isWindows = package.config:sub(1,1) == '\\'

local function initFFI()
    if ffi ~= nil then
        return ffi ~= false
    end
    
    local success, result = pcall(require, 'ffi')
    if not success then
        ffi = false
        return false
    end
    
    ffi = result
    
    if isWindows then
        local loadSuccess, lib = pcall(ffi.load, 'winmm')
        if loadSuccess then
            winmm = lib
            ffi.cdef[[
                int PlaySoundA(const char* pszSound, void* hmod, unsigned int fdwSound);
            ]]
            return true
        end
    end
    
    return false
end

local SND_FILENAME = 0x00020000
local SND_ASYNC = 0x0001
local SND_NODEFAULT = 0x0002

function M.SoundPlayer.new(guiManager, logger)
    local self = setmetatable({}, M.SoundPlayer)
    self.guiManager = guiManager
    self.logger = logger
    self.ffiAvailable = initFFI()
    return self
end

function M.SoundPlayer:playWavBytes(data, volume)
    if self.logger then
        self.logger:warning("playWavBytes not implemented")
    end
    return false
end

function M.SoundPlayer:playWavFile(path, volume)
    if not path or path == "" then
        return false
    end
    
    local fullPath = path
    if not string.match(path, "^[A-Za-z]:") and not string.match(path, "^/") then
        -- Check for custom sound override first
        local settings = require('libs.settings')
        local customPath = settings.getCustomSoundPath(path)
        if customPath then
            fullPath = customPath
        elseif _G.gConfig and _G.gConfig.addonPath then
            -- Fall back to bundled assets
            local addonPath = _G.gConfig.addonPath:gsub("/", "\\")
            if not addonPath:match("\\$") then
                addonPath = addonPath .. "\\"
            end
            fullPath = addonPath .. "assets\\sounds\\" .. path
        end
    end
    
    if isWindows and self.ffiAvailable and winmm then
        local success, err = pcall(function()
            winmm.PlaySoundA(fullPath, nil, bit.bor(SND_FILENAME, SND_ASYNC, SND_NODEFAULT))
        end)
        if success then
            return true
        end
        if self.logger then
            self.logger:debug("FFI PlaySound failed, falling back: " .. tostring(err))
        end
    end
    
    if isWindows then
        local escapedPath = fullPath:gsub("'", "''")
        local cmd = string.format(
            'powershell -WindowStyle Hidden -Command "(New-Object Media.SoundPlayer \'%s\').PlaySync()"',
            escapedPath
        )
        local result = os.execute('start /b "" ' .. cmd)
        return result == 0 or result == true
    end
    
    local linuxPath = fullPath:gsub("\\", "/")
    
    local players = {"paplay", "aplay", "afplay"}
    for _, player in ipairs(players) do
        local checkCmd = "which " .. player .. " > /dev/null 2>&1"
        if os.execute(checkCmd) == 0 then
            local playCmd = player .. ' "' .. linuxPath .. '" &'
            os.execute(playCmd)
            return true
        end
    end
    
    if self.logger then
        self.logger:warning("No sound player available for this platform")
    end
    return false
end

function M.playSound(path, volume, logger)
    local player = M.SoundPlayer.new(nil, logger)
    return player:playWavFile(path, volume)
end

return M
