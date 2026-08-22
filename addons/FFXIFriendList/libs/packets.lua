--[[
* libs/packets.lua
* Packet parsing functions (called from entry file for routing)
* All packet parsing functions return parsed packet table or nil
]]--

local M = {}

-- Helper: Read string from packet data
-- Note: Ashita packet data is a string, use string.byte() to get bytes
local function readString(data, offset, length)
    if not data or type(data) ~= "string" or offset < 0 or length <= 0 then
        return nil, offset
    end
    if offset + length > #data then
        return nil, offset
    end
    
    local str = ""
    for i = offset + 1, offset + length do  -- Lua strings are 1-indexed
        local byte = string.byte(data, i)
        if byte == 0 then
            break  -- Null terminator
        end
        str = str .. string.char(byte)
    end
    
    return str, offset + length
end

-- Helper: Read uint8 from packet data
-- Note: Ashita packet data is a string, use string.byte() to get bytes
local function readUint8(data, offset)
    if not data or type(data) ~= "string" or offset < 0 or offset >= #data then
        return nil, offset
    end
    return string.byte(data, offset + 1), offset + 1  -- Lua strings are 1-indexed
end

-- Helper: Read uint16 (little-endian) from packet data
-- Note: Ashita packet data is a string, use string.byte() to get bytes
local function readUint16(data, offset)
    if not data or type(data) ~= "string" or offset < 0 or offset + 1 >= #data then
        return nil, offset
    end
    local low = string.byte(data, offset + 1)   -- Lua strings are 1-indexed
    local high = string.byte(data, offset + 2)
    return low + (high * 256), offset + 2
end

-- Helper: Read uint32 (little-endian) from packet data
-- Note: Ashita packet data is a string, use string.byte() to get bytes
local function readUint32(data, offset)
    if not data or type(data) ~= "string" or offset < 0 or offset + 3 >= #data then
        return nil, offset
    end
    local b1 = string.byte(data, offset + 1)   -- Lua strings are 1-indexed
    local b2 = string.byte(data, offset + 2)
    local b3 = string.byte(data, offset + 3)
    local b4 = string.byte(data, offset + 4)
    return b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216), offset + 4
end

-- Parse zone packet (0x00A) - Zone change
function M.ParseZonePacket(e)
    if not e or e.id ~= 0x00A or e.size < 0xB8 then
        return nil
    end
    
    local data = e.data
    local offset = 0
    
    local zoneId, err = readUint16(data, offset)
    if not zoneId then 
        return nil 
    end
    
    return {
        type = "zone",
        zoneId = zoneId
    }
end

-- Parse PC Update packet (0x00D) - Detects anonymous and job changes
function M.ParsePCUpdatePacket(e)
    if not e or e.id ~= 0x00D or e.size < 0x24 then
        return nil
    end
    
    local data = e.data
    
    -- Byte 0x21 contains flags (0-indexed, so 34th byte in 1-indexed Lua string)
    -- Bit 0x10 (16) = Anonymous flag
    local flagByte = string.byte(data, 0x21 + 1)  -- +1 for Lua 1-indexing
    if not flagByte then return nil end
    
    local isAnonymous = bit.band(flagByte, 0x10) == 0x10
    
    return {
        type = "pc_update",
        isAnonymous = isAnonymous,
        flags = flagByte
    }
end

-- Parse Update Char packet (0x037) - Detects anonymous status (self-updates)
function M.Parse037Packet(e)
    if not e or e.id ~= 0x037 or e.size < 0x5C then
        return nil
    end
    
    local data = e.data
    
    -- Byte 0x28 (_flags1) contains anonymous flag
    -- Bit 0x0020 = /anon flag (blue name)
    -- This is a 16-bit value (unsigned short)
    local flagsLow = string.byte(data, 0x28 + 1)   -- +1 for Lua 1-indexing
    local flagsHigh = string.byte(data, 0x29 + 1)
    if not flagsLow or not flagsHigh then return nil end
    
    local flags1 = flagsLow + (flagsHigh * 256)
    local isAnonymous = bit.band(flags1, 0x0020) == 0x0020
    
    return {
        type = "update_char",
        isAnonymous = isAnonymous,
        flags1 = flags1
    }
end

-- Parse Char Update packet (0x0DF) - Detects job changes (HP/MP/TP/Job updates)
function M.Parse0DFPacket(e)
    if not e or e.id ~= 0x0DF or e.size < 0x26 then
        return nil
    end
    
    local data = e.data
    
    -- Byte 0x04-0x07 = Entity ID (uint32)
    local entityId1 = string.byte(data, 0x04 + 1)
    local entityId2 = string.byte(data, 0x05 + 1)
    local entityId3 = string.byte(data, 0x06 + 1)
    local entityId4 = string.byte(data, 0x07 + 1)
    local entityId = entityId1 + (entityId2 * 256) + (entityId3 * 65536) + (entityId4 * 16777216)
    
    -- Byte 0x20 = main job, 0x21 = main job level, 0x22 = sub job, 0x23 = sub job level
    local mainJob = string.byte(data, 0x20 + 1)  -- +1 for Lua 1-indexing
    local mainJobLevel = string.byte(data, 0x21 + 1)
    local subJob = string.byte(data, 0x22 + 1)
    local subJobLevel = string.byte(data, 0x23 + 1)
    
    if not mainJob or not subJob then return nil end
    
    return {
        type = "char_update",
        entityId = entityId,
        mainJob = mainJob,
        mainJobLevel = mainJobLevel or 0,
        subJob = subJob,
        subJobLevel = subJobLevel or 0
    }
end

-- Generic packet parser (returns basic info if no specific parser exists)
function M.ParseGenericPacket(e)
    if not e then
        return nil
    end
    
    return {
        type = "generic",
        id = e.id,
        size = e.size
    }
end

return M
