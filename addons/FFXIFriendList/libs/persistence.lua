--[[
* libs/persistence.lua
* File I/O helpers for persistence
]]--

local Json = require("protocol.Json")

local M = {}

-- Create directory recursively (creates parent directories if needed)
local function createDirectoryRecursive(dir, createDirFunc)
    if not createDirFunc then
        return false, "No createDirectory function provided"
    end
    
    -- Normalize path separators
    dir = dir:gsub("/", "\\")
    
    -- Extract the directory path (remove filename if present)
    -- Create each subdirectory level incrementally
    for i = 1, #dir do
        local char = dir:sub(i, i)
        if char == "\\" or char == "/" then
            -- Found a directory separator, create directory up to this point
            local subDir = dir:sub(1, i - 1)
            if subDir ~= "" then
                pcall(createDirFunc, subDir)
                -- Ignore errors - directory might already exist
            end
        end
    end
    
    -- Create the final directory (the full path)
    local success, err = pcall(createDirFunc, dir)
    if not success then
        local errorMsg = err
        if type(errorMsg) == "table" then
            errorMsg = "Failed to create directory"
        else
            errorMsg = tostring(errorMsg or "Failed to create directory")
        end
        -- Don't fail if directory already exists (that's OK)
        if not (errorMsg:match("exists") or errorMsg:match("already")) then
            return false, errorMsg .. ": " .. dir
        end
    end
    
    return true, nil
end

local function getFilePath(basePath, filename, createDirFunc)
    if not basePath or basePath == "" then
        return nil, "Install path is empty or nil"
    end
    
    basePath = basePath:gsub('\\$', '')  -- Remove trailing backslash
    
    local dir = basePath .. "\\config\\addons\\FFXIFriendList"
    
    if createDirFunc then
        local success, err = createDirectoryRecursive(dir, createDirFunc)
        if not success then
            return nil, err or "Failed to create directory: " .. dir
        end
    end
    
    local fullPath = dir .. "\\" .. filename
    return fullPath, nil
end

function M.loadJson(basePath, filename, createDirFunc)
    local path, err = getFilePath(basePath, filename, createDirFunc)
    if not path then
        return nil, err or "Could not determine file path"
    end
    
    local file = io.open(path, 'r')
    if not file then
        return nil, "File does not exist"
    end
    
    local content = file:read('*all')
    file:close()
    
    if not content or content == '' then
        return nil, "File is empty"
    end
    
    local ok, data = Json.decode(content)
    if not ok then
        return nil, "Failed to parse JSON: " .. tostring(data)
    end
    
    return data, nil
end

function M.saveJson(basePath, filename, data, createDirFunc)
    if not data or type(data) ~= 'table' then
        return false, "Invalid data"
    end
    
    local path, err = getFilePath(basePath, filename, createDirFunc)
    if not path then
        return false, err or "Could not determine file path"
    end
    
    local jsonStr = Json.encode(data)
    if not jsonStr then
        return false, "Failed to encode JSON"
    end
    
    local file, openErr = io.open(path, 'w')
    if not file then
        local errorMsg = "Failed to open file for writing: " .. tostring(path)
        if openErr then
            errorMsg = errorMsg .. " (Error: " .. tostring(openErr) .. ")"
        end
        return false, errorMsg
    end
    
    local success, writeErr = pcall(function()
        file:write(jsonStr)
    end)
    
    file:close()
    
    if not success then
        local errorMsg = writeErr
        if type(errorMsg) == "table" then
            errorMsg = "Failed to write file"
        else
            errorMsg = tostring(errorMsg or "Failed to write file")
        end
        return false, errorMsg
    end
    
    return true, nil
end

function M.loadIni(basePath, filename, createDirFunc)
    local path, err = getFilePath(basePath, filename, createDirFunc)
    if not path then
        return nil, err or "Could not determine file path"
    end
    
    local file = io.open(path, 'r')
    if not file then
        return {}, nil  -- Return empty table if file doesn't exist
    end
    
    local data = {}
    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")  -- Trim whitespace
        if line ~= "" and not line:match("^#") then  -- Skip empty lines and comments
            local key, value = line:match("^([^=]+)=(.+)$")
            if key and value then
                key = key:match("^%s*(.-)%s*$")  -- Trim key
                value = value:match("^%s*(.-)%s*$")  -- Trim value
                data[key] = value
            end
        end
    end
    
    file:close()
    return data, nil
end

function M.saveIni(basePath, filename, data, createDirFunc)
    if not data or type(data) ~= 'table' then
        return false, "Invalid data"
    end
    
    local path, err = getFilePath(basePath, filename, createDirFunc)
    if not path then
        return false, err or "Could not determine file path"
    end
    
    local file = io.open(path, 'w')
    if not file then
        return false, "Failed to open file for writing"
    end
    
    local success, writeErr = pcall(function()
        for key, value in pairs(data) do
            file:write(tostring(key) .. "=" .. tostring(value) .. "\n")
        end
    end)
    
    file:close()
    
    if not success then
        local errorMsg = writeErr
        if type(errorMsg) == "table" then
            errorMsg = "Failed to write file"
        else
            errorMsg = tostring(errorMsg or "Failed to write file")
        end
        return false, errorMsg
    end
    
    return true, nil
end

return M
