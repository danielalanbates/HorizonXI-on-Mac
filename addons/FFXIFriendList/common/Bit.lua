-- Bit.lua
-- Bitwise operation wrapper for cross-environment compatibility
-- Uses: bit (LuaJIT/Lua 5.1), bit32 (Lua 5.2), or fallback pure-Lua implementation

local M = {}

-- Try to find available bitwise library
local bit_lib = nil

-- Try LuaJIT bit library first (most common in game engines)
local ok, lib = pcall(require, "bit")
if ok and lib then
    bit_lib = lib
else
    -- Try Lua 5.2+ bit32 library
    ok, lib = pcall(require, "bit32")
    if ok and lib then
        bit_lib = lib
    end
end

-- If no library found, use pure-Lua fallback (slow but works)
if not bit_lib then
    -- Pure-Lua bitwise operations (32-bit)
    local function normalize(x)
        return x % 4294967296  -- 2^32
    end
    
    local function band(a, b)
        local result = 0
        local bit = 1
        for _ = 1, 32 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + bit
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bit = bit * 2
        end
        return result
    end
    
    local function bor(a, b)
        local result = 0
        local bit = 1
        for _ = 1, 32 do
            if a % 2 == 1 or b % 2 == 1 then
                result = result + bit
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bit = bit * 2
        end
        return result
    end
    
    local function bxor(a, b)
        local result = 0
        local bit = 1
        for _ = 1, 32 do
            local abit = a % 2
            local bbit = b % 2
            if abit ~= bbit then
                result = result + bit
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bit = bit * 2
        end
        return result
    end
    
    local function lshift(a, n)
        if n < 0 then return M.rshift(a, -n) end
        return normalize(a * (2 ^ n))
    end
    
    local function rshift(a, n)
        if n < 0 then return M.lshift(a, -n) end
        return math.floor(normalize(a) / (2 ^ n))
    end
    
    bit_lib = {
        band = band,
        bor = bor,
        bxor = bxor,
        lshift = lshift,
        rshift = rshift
    }
end

-- Export unified API
M.band = bit_lib.band
M.bor = bit_lib.bor
M.bxor = bit_lib.bxor
M.lshift = bit_lib.lshift or bit_lib.shl
M.rshift = bit_lib.rshift or bit_lib.shr

-- Helper: check if native bit library is available
M.isNative = function()
    local ok = pcall(require, "bit")
    if ok then return true end
    ok = pcall(require, "bit32")
    return ok
end

return M

