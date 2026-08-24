-- HXI_MAC_JIT_GUARD: Ashita 4.3's LuaJIT trace patcher faults under Wine/Rosetta.
if jit and jit.off then jit.off() end
addon.name    = 'lslog'
addon.author  = 'batesai'
addon.version = '0.1'
addon.desc    = 'Timestamped log of every incoming chat line + zone changes, for scripted verification.'

require('common')

local path = AshitaCore:GetInstallPath() .. '\\addons\\lslog\\lslog' .. (os.getenv('FLCLIENT') or '') .. '.log'

local function w(s)
    local f = io.open(path, 'a')
    if f then f:write(os.date('%H:%M:%S ') .. s .. '\n') f:close() end
end

w('=== lslog loaded ===')

ashita.events.register('text_in', 'lslog_text_in', function(e)
    local msg = e.message_modified or e.message or ''
    msg = string.gsub(msg, '[%z\1-\31\127-\255]', function(c)
        local b = string.byte(c)
        return (b == 10 or b == 13) and ' ' or string.format('<%02X>', b)
    end)
    w(string.format('TEXT mode=%d msg=%s', e.mode or -1, msg))
end)

-- 0x0A = zone-in, 0x0B = zone-out (server), 0xCC = linkshell message, 0xC8 = party/ls list
ashita.events.register('packet_in', 'lslog_packet_in', function(e)
    if e.id == 0x000A then
        w('PACKET 0x0A zone-in')
    elseif e.id == 0x000B then
        w('PACKET 0x0B zone-out')
    elseif e.id == 0x00CC then
        w('PACKET 0xCC linkshell-message')
    end
end)
