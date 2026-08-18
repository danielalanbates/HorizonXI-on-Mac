local M = {}

local MENU_POLL_INTERVAL_MS = 50
local STABLE_POLL_COUNT = 1
local DEBUG_LOG_THROTTLE_MS = 250
local RING_BUFFER_SIZE = 20

local FRIENDLIST_MENU_PATTERN = "flistmai"
local TOLIST_TRIGGER_PATTERN = "friend"

local startClock = os.clock()
local startTime = os.time()

local function getCurrentTimeMs()
    local clockElapsed = os.clock() - startClock
    return (startTime * 1000) + (clockElapsed * 1000)
end

local state = {
    pGameMenu = nil,
    patternScanAttempted = false,
    lastMenuName = "",
    normalizedMenuName = "",
    inFriendListMenu = false,
    toListTriggered = false,
    windowOpened = false,
    stableFlistmaiCount = 0,
    stableExitCount = 0,
    lastPollTime = 0,
    lastDebugLogTime = 0,
    lastTransitionTime = 0,
    ringBuffer = {},
    ringBufferIndex = 1,
    lastPointerChain = {
        subPointer = 0,
        subValue = 0,
        menuHeader = 0,
    },
    detectionMode = "auto",
}

local function isDebugEnabled()
    return gConfig and gConfig.menuDebugEnabled
end

local function debugLog(msg)
    if isDebugEnabled() then
        print("[FFXIFriendList MenuDetect] " .. msg)
    end
end

local function throttledDebugLog(msg)
    local now = getCurrentTimeMs()
    if now - state.lastDebugLogTime >= DEBUG_LOG_THROTTLE_MS then
        debugLog(msg)
        state.lastDebugLogTime = now
    end
end

local function hexDump(ptr, length)
    if not ptr or ptr == 0 then
        return "<nil>"
    end
    local bytes = {}
    for i = 0, length - 1 do
        local success, byte = pcall(ashita.memory.read_uint8, ptr + i)
        if success and byte then
            table.insert(bytes, string.format("%02X", byte))
        else
            table.insert(bytes, "??")
        end
    end
    return table.concat(bytes, " ")
end

local function normalizeMenuName(name)
    if not name or type(name) ~= "string" then
        return ""
    end
    name = name:gsub('\x00', '')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    return name:lower()
end

local function addToRingBuffer(menuName, normalized)
    state.ringBuffer[state.ringBufferIndex] = {
        raw = menuName,
        normalized = normalized,
        time = getCurrentTimeMs(),
    }
    state.ringBufferIndex = (state.ringBufferIndex % RING_BUFFER_SIZE) + 1
end

local function matchesPattern(normalizedName, pattern)
    if normalizedName == "" then
        return false
    end
    return normalizedName:find(pattern, 1, true) ~= nil
end

local function getMenuName()
    if not state.pGameMenu or state.pGameMenu == 0 then
        return ""
    end
    
    local success, subPointer = pcall(ashita.memory.read_uint32, state.pGameMenu)
    if not success or not subPointer or subPointer == 0 then
        state.lastPointerChain.subPointer = 0
        state.lastPointerChain.subValue = 0
        state.lastPointerChain.menuHeader = 0
        return ""
    end
    state.lastPointerChain.subPointer = subPointer
    
    local success2, subValue = pcall(ashita.memory.read_uint32, subPointer)
    if not success2 or not subValue or subValue == 0 then
        state.lastPointerChain.subValue = 0
        state.lastPointerChain.menuHeader = 0
        return ""
    end
    state.lastPointerChain.subValue = subValue
    
    local success3, menuHeader = pcall(ashita.memory.read_uint32, subValue + 4)
    if not success3 or not menuHeader or menuHeader == 0 then
        state.lastPointerChain.menuHeader = 0
        return ""
    end
    state.lastPointerChain.menuHeader = menuHeader
    
    local success4, menuName = pcall(ashita.memory.read_string, menuHeader + 0x46, 16)
    if not success4 or not menuName then
        return ""
    end
    
    return menuName
end

local function checkAshitaTargetApi()
    local success, result = pcall(function()
        local memMgr = AshitaCore:GetMemoryManager()
        if not memMgr then return nil end
        local target = memMgr:GetTarget()
        if not target then return nil end
        if target.GetIsMenuOpen then
            return target:GetIsMenuOpen()
        end
        return nil
    end)
    
    if success and result ~= nil then
        debugLog("Ashita Target API available: GetIsMenuOpen() = " .. tostring(result))
        return true, result
    end
    return false, nil
end

local function doPatternScan()
    if state.patternScanAttempted then
        return state.pGameMenu ~= nil and state.pGameMenu ~= 0
    end
    
    state.patternScanAttempted = true
    
    local apiAvailable, apiValue = checkAshitaTargetApi()
    if apiAvailable then
        debugLog("Ashita GetIsMenuOpen API detected (but we still use pattern scan for menu NAME)")
    end
    
    local success, result = pcall(function()
        return ashita.memory.find('FFXiMain.dll', 0, "8B480C85C974??8B510885D274??3B05", 16, 0)
    end)
    
    if success and result and result ~= 0 then
        state.pGameMenu = result
        debugLog("Pattern scan SUCCESS: 0x" .. string.format("%X", state.pGameMenu))
        state.detectionMode = "auto"
        return true
    else
        state.pGameMenu = nil
        debugLog("Pattern scan FAILED - menu detection unavailable, using manual mode")
        state.detectionMode = "manual"
        return false
    end
end

local escapeScheduled = false
local escapeSendCount = 0

local function closeGameWindow()
    debugLog("Attempting to close game friend list window (Lua limitation: window may briefly appear)")
    debugLog("Note: /escape command may not close game menus - this is a Lua port limitation")
    
    local chatManager = AshitaCore:GetChatManager()
    if not chatManager then
        debugLog("No chat manager available")
        return
    end
    
    escapeSendCount = 0
    escapeScheduled = true
    
    local success, err = pcall(function()
        chatManager:QueueCommand(1, '/escape')
    end)
    
    if success then
        debugLog("Queued /escape command")
        escapeSendCount = escapeSendCount + 1
    else
        debugLog("Failed to queue /escape: " .. tostring(err))
    end
end

local function sendPendingEscapes()
    if not escapeScheduled then
        return
    end
    
    if escapeSendCount >= 3 then
        escapeScheduled = false
        escapeSendCount = 0
        return
    end
    
    local chatManager = AshitaCore:GetChatManager()
    if chatManager then
        chatManager:QueueCommand(1, '/escape')
        escapeSendCount = escapeSendCount + 1
    end
end

local function openQuickOnlineWindow()
    debugLog("Opening Compact Friend List window (To List detected)")
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.friends then
        app.features.friends:refresh()
    end
    
    if gConfig then
        gConfig.showQuickOnline = true
        local moduleRegistry = _G.moduleRegistry
        if moduleRegistry then
            moduleRegistry.CheckVisibility(gConfig)
        end
    end
    
    state.windowOpened = true
end

local function closeQuickOnlineWindow()
    local isLocked = false
    if gConfig and gConfig.windows and gConfig.windows.quickOnline then
        isLocked = gConfig.windows.quickOnline.locked or false
    end
    
    if isLocked then
        debugLog("Compact Friend List window is locked, not closing")
        return
    end
    
    debugLog("Closing Compact Friend List window (exited friend list menu)")
    
    if gConfig then
        gConfig.showQuickOnline = false
        local moduleRegistry = _G.moduleRegistry
        if moduleRegistry then
            moduleRegistry.CheckVisibility(gConfig)
        end
    end
    
    state.windowOpened = false
    state.toListTriggered = false
end

function M.initialize()
    state.pGameMenu = nil
    state.patternScanAttempted = false
    state.lastMenuName = ""
    state.normalizedMenuName = ""
    state.inFriendListMenu = false
    state.toListTriggered = false
    state.windowOpened = false
    state.stableFlistmaiCount = 0
    state.stableExitCount = 0
    state.lastPollTime = 0
    state.lastDebugLogTime = 0
    state.lastTransitionTime = 0
    state.ringBuffer = {}
    state.ringBufferIndex = 1
    state.lastPointerChain = { subPointer = 0, subValue = 0, menuHeader = 0 }
    state.detectionMode = "auto"
    
    doPatternScan()
    
    return nil
end

function M.update(dtSeconds)
    sendPendingEscapes()
    
    if state.detectionMode == "manual" then
        return
    end
    
    if gConfig and gConfig.menuDetectionEnabled == false then
        return
    end
    
    if not state.pGameMenu or state.pGameMenu == 0 then
        return
    end
    
    local now = getCurrentTimeMs()
    
    if now - state.lastPollTime < MENU_POLL_INTERVAL_MS then
        return
    end
    state.lastPollTime = now
    
    local rawMenuName = getMenuName()
    local normalized = normalizeMenuName(rawMenuName)
    
    if normalized ~= state.normalizedMenuName then
        addToRingBuffer(rawMenuName, normalized)
        
        if isDebugEnabled() then
            throttledDebugLog("Menu name changed: \"" .. rawMenuName .. "\" -> normalized: \"" .. normalized .. "\"")
        end
        
        state.lastMenuName = rawMenuName
        state.normalizedMenuName = normalized
    end
    
    local isFlistmai = matchesPattern(normalized, FRIENDLIST_MENU_PATTERN)
    local isToList = matchesPattern(normalized, TOLIST_TRIGGER_PATTERN) and not isFlistmai
    
    if isFlistmai then
        if state.toListTriggered and state.windowOpened then
            debugLog("BACK to flistmai from friend: closing Compact Friend List")
            closeQuickOnlineWindow()
            state.toListTriggered = false
        end
        
        if not state.inFriendListMenu then
            state.stableFlistmaiCount = state.stableFlistmaiCount + 1
            if state.stableFlistmaiCount >= STABLE_POLL_COUNT then
                state.inFriendListMenu = true
                state.stableFlistmaiCount = 0
                debugLog("ENTER flistmai context: menuName=\"" .. rawMenuName .. "\"")
            end
        end
        state.stableExitCount = 0
    elseif isToList and state.inFriendListMenu then
        if not state.toListTriggered then
            state.toListTriggered = true
            debugLog("TO LIST clicked: menuName=\"" .. rawMenuName .. "\"")
            closeGameWindow()
            openQuickOnlineWindow()
        end
        state.stableExitCount = 0
    else
        if state.inFriendListMenu or state.windowOpened then
            state.stableExitCount = state.stableExitCount + 1
            if state.stableExitCount >= STABLE_POLL_COUNT then
                debugLog("EXIT friend list area entirely: menuName=\"" .. rawMenuName .. "\"")
                state.inFriendListMenu = false
                state.toListTriggered = false
                if state.windowOpened then
                    closeQuickOnlineWindow()
                end
                state.stableExitCount = 0
            end
        end
        state.stableFlistmaiCount = 0
    end
end

function M.tick(dtSeconds)
    M.update(dtSeconds)
end

function M.handleMenuPacket(packet)
    if not packet or packet.type ~= "menu" then
        return false
    end
    return true
end

function M.isMenuOpen()
    return state.inFriendListMenu or state.windowOpened
end

function M.getCurrentMenuId()
    return nil
end

function M.getMenuName()
    return state.lastMenuName
end

function M.getNormalizedMenuName()
    return state.normalizedMenuName
end

function M.getPatternScanResult()
    return state.pGameMenu
end

function M.getState()
    local ashitaApiAvailable = false
    local ashitaMenuOpen = nil
    pcall(function()
        local memMgr = AshitaCore:GetMemoryManager()
        if memMgr then
            local target = memMgr:GetTarget()
            if target and target.GetIsMenuOpen then
                ashitaApiAvailable = true
                ashitaMenuOpen = target:GetIsMenuOpen()
            end
        end
    end)
    
    return {
        pGameMenu = state.pGameMenu,
        lastMenuName = state.lastMenuName,
        normalizedMenuName = state.normalizedMenuName,
        inFriendListMenu = state.inFriendListMenu,
        toListTriggered = state.toListTriggered,
        windowOpened = state.windowOpened,
        stableFlistmaiCount = state.stableFlistmaiCount,
        stableExitCount = state.stableExitCount,
        detectionMode = state.detectionMode,
        ashitaApiAvailable = ashitaApiAvailable,
        ashitaMenuOpen = ashitaMenuOpen,
        pointerChain = {
            subPointer = state.lastPointerChain.subPointer,
            subValue = state.lastPointerChain.subValue,
            menuHeader = state.lastPointerChain.menuHeader,
        },
    }
end

function M.getRingBuffer()
    local result = {}
    local startIdx = state.ringBufferIndex
    
    for i = 0, RING_BUFFER_SIZE - 1 do
        local idx = ((startIdx - 1 + i) % RING_BUFFER_SIZE) + 1
        local entry = state.ringBuffer[idx]
        if entry then
            table.insert(result, entry)
        end
    end
    
    return result
end

function M.getHexDump(ptr, length)
    return hexDump(ptr, length or 32)
end

function M.handleCommand(mode, command, injected)
    return false
end

function M.forceToggle()
    if gConfig then
        gConfig.showQuickOnline = not gConfig.showQuickOnline
        local moduleRegistry = _G.moduleRegistry
        if moduleRegistry then
            moduleRegistry.CheckVisibility(gConfig)
        end
        return gConfig.showQuickOnline
    end
    return false
end

function M.cleanup()
    state.pGameMenu = nil
    state.patternScanAttempted = false
    state.lastMenuName = ""
    state.normalizedMenuName = ""
    state.inFriendListMenu = false
    state.toListTriggered = false
    state.windowOpened = false
    state.stableFlistmaiCount = 0
    state.stableExitCount = 0
    state.ringBuffer = {}
    state.detectionMode = "auto"
    return nil
end

return M
