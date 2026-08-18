local ffi = require('ffi')

local M = {}

local activeController = nil
local activeControllerName = nil

-- XINPUT structures for FFI access
-- Wrap in pcall to handle case where another addon already defined these
pcall(function()
    ffi.cdef[[
        typedef struct {
            uint16_t wButtons;
            uint8_t  bLeftTrigger;
            uint8_t  bRightTrigger;
            int16_t  sThumbLX;
            int16_t  sThumbLY;
            int16_t  sThumbRX;
            int16_t  sThumbRY;
        } XINPUT_GAMEPAD;

        typedef struct {
            uint32_t       dwPacketNumber;
            XINPUT_GAMEPAD Gamepad;
        } XINPUT_STATE;
    ]]
end)

-- Button bitmasks for xinput_state
local ButtonMasks = {
    A = 0x1000,
    B = 0x2000,
    X = 0x4000,
    Y = 0x8000,
    L1 = 0x0100,  -- LEFT_SHOULDER
    R1 = 0x0200,  -- RIGHT_SHOULDER
    L3 = 0x0040,  -- LEFT_THUMB
    R3 = 0x0080,  -- RIGHT_THUMB
    Dpad_Up = 0x0001,
    Dpad_Down = 0x0002,
    Dpad_Left = 0x0004,
    Dpad_Right = 0x0008,
    Menu = 0x0010,  -- START
    View = 0x0020,  -- BACK
}

-- Trigger threshold (0-255, triggers are analog)
local TRIGGER_THRESHOLD = 30

-- State tracking for button press detection
local previousButtons = 0
local previousL2 = false
local previousR2 = false

-- Handle close button press
-- Only uses windowClosePolicy - closeGating uses ImGui which can't be called in xinput_state
local function handleCloseButton()
    local windowClosePolicy = require('ui.window_close_policy')
    
    if not windowClosePolicy.anyWindowOpen() then
        return false
    end
    
    local closedWindow = windowClosePolicy.closeTopMostWindow()
    
    if closedWindow ~= "" then
        return true
    else
        return false
    end
end

-- Handle close button binding
local function handleCloseBinding(buttonName)
    local app = _G.FFXIFriendListApp
    if not app or not app.features or not app.features.preferences then
        return false
    end

    local prefs = app.features.preferences:getPrefs()
    local closeButton = prefs.closeBindButton
    
    if closeButton and closeButton ~= '' and buttonName == closeButton then
        -- Use pcall to prevent errors from breaking controller handling
        local success, result = pcall(handleCloseButton)
        if success then
            return result
        end
        -- On error, return false so other bindings can still work
        return false
    end
    
    return false
end

-- Global handle binding function to be called by controller files
-- Using a TRUE global (no _G. prefix) so Lua resolves it at call time, matching cBind's pattern
HandleBinding = function(buttonName, newState)
    return M.HandleBinding(buttonName, newState)
end

function M.HandleBinding(buttonName, newState)
    -- Only trigger on button press (newState == true)
    if newState ~= true then
        return
    end
    
    -- Check close window binding first
    if handleCloseBinding(buttonName) then
        return true
    end
    
    local app = _G.FFXIFriendListApp
    if not app or not app.features or not app.features.preferences then
        return
    end

    local prefs = app.features.preferences:getPrefs()
    
    -- Check main window binding (flistBindButton -> /fl opens main window)
    local flistButton = prefs.flistBindButton
    if flistButton and flistButton ~= '' and buttonName == flistButton then
        local chatManager = AshitaCore:GetChatManager()
        if chatManager then
            chatManager:QueueCommand(-1, '/fl')
        end
        return true
    end
    
    -- Check compact friend list binding (flBindButton -> /flist opens compact list)
    local flButton = prefs.flBindButton
    if flButton and flButton ~= '' and buttonName == flButton then
        local chatManager = AshitaCore:GetChatManager()
        if chatManager then
            chatManager:QueueCommand(-1, '/flist')
        end
        return true
    end
end

-- Handle XInput state event (polled every frame)
-- This is more reliable than xinput_button which doesn't fire on all systems
function M.HandleXInputState(e)
    if not e.state then
        return
    end

    local xinputState = ffi.cast('XINPUT_STATE*', e.state)
    if not xinputState then
        return
    end

    local gamepad = xinputState.Gamepad
    local currentButtons = gamepad.wButtons
    local leftTrigger = gamepad.bLeftTrigger
    local rightTrigger = gamepad.bRightTrigger

    -- Detect newly pressed buttons (was 0, now 1)
    local newPresses = bit.band(currentButtons, bit.bnot(previousButtons))

    -- Check if any modifier key is held (for XIUI crossbar compatibility)
    local L1_MASK = 0x0100
    local R1_MASK = 0x0200
    local isL1Held = bit.band(currentButtons, L1_MASK) ~= 0
    local isR1Held = bit.band(currentButtons, R1_MASK) ~= 0
    local isL2Held = leftTrigger >= TRIGGER_THRESHOLD
    local isR2Held = rightTrigger >= TRIGGER_THRESHOLD
    local modifierHeld = isL1Held or isR1Held or isL2Held or isR2Held

    -- Check each button for new presses
    for buttonName, mask in pairs(ButtonMasks) do
        if bit.band(newPresses, mask) ~= 0 then
            -- Skip if modifier held and this is NOT a modifier button (XIUI compatibility)
            local isModifierButton = (buttonName == 'L1' or buttonName == 'R1')
            if modifierHeld and not isModifierButton then
                -- Skip - modifier held, let XIUI handle this combo
            else
                M.HandleBinding(buttonName, true)
            end
        end
    end

    -- Handle L2 trigger (analog, use threshold)
    local currentL2 = leftTrigger >= TRIGGER_THRESHOLD
    if currentL2 and not previousL2 then
        M.HandleBinding('L2', true)
    end
    previousL2 = currentL2

    -- Handle R2 trigger (analog, use threshold)
    local currentR2 = rightTrigger >= TRIGGER_THRESHOLD
    if currentR2 and not previousR2 then
        M.HandleBinding('R2', true)
    end
    previousR2 = currentR2

    -- Update previous state for next frame
    previousButtons = currentButtons
end

function M.Initialize()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        local layout = prefs.controllerLayout
        if layout then
            M.LoadController(layout)
        else
            M.LoadController('xinput')
        end
    else
        M.LoadController('xinput')
    end
end

function M.Update(dt)
    -- No pending command logic needed for simple /flist bind
end

function M.LoadController(name)
    if activeControllerName == name and activeController then
        return -- Already loaded
    end

    -- Use addon path from gConfig (set during addon load)
    local addonPath = gConfig and gConfig.addonPath or nil
    if not addonPath then
        return
    end
    
    local path = addonPath .. 'controllers/' .. name .. '.lua'
    -- Normalize path separators for Windows
    path = path:gsub('/', '\\')
    
    if not ashita.fs.exists(path) then
        return
    end

    local f, err = loadfile(path)
    if not f then
        return
    end

    local success, result = pcall(f)
    if not success then
        return
    end

    activeController = result
    activeControllerName = name
end

function M.HandleDirectInput(e)
    if activeController and activeController.HandleDirectInput then
        activeController:HandleDirectInput(e)
    end
end

function M.HandleXInput(e)
    if activeController and activeController.HandleXInput then
        activeController:HandleXInput(e)
    end
end

function M.GetActiveController()
    return activeController
end

function M.GetActiveControllerName()
    return activeControllerName
end

function M.GetAvailableControllers()
    -- Use addon path from gConfig (set during addon load)
    local addonPath = gConfig and gConfig.addonPath or nil
    if not addonPath then
        return {}
    end
    
    local path = addonPath .. 'controllers/'
    -- Normalize path separators for Windows
    path = path:gsub('/', '\\')
    
    local controllers = {}
    if not ashita.fs.exists(path) then
        return controllers
    end
    
    local contents = ashita.fs.get_directory(path, '.*\\.lua')
    if contents then
        for _, file in pairs(contents) do
            file = string.sub(file, 1, -5)
            if file ~= 'init' then
                table.insert(controllers, file)
            end
        end
    end
    return controllers
end

function M.GetActiveControllerButtons()
    if activeController and activeController.Buttons then
        return activeController.Buttons
    end
    return {}
end

return M
