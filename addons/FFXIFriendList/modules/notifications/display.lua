local imgui = require('imgui')
local NotificationSoundPolicy = require('core.notificationsoundpolicy')
local ThemeHelper = require('libs.themehelper')
local SoundPlayer = require('platform.services.SoundPlayer')
local FontManager = require('app.ui.FontManager')
local InputHelper = require('ui.helpers.InputHelper')
local scaling = require('scaling')
local TimingConstants = require('core.TimingConstants')
local UIConst = require('constants.ui')
local Colors = require('constants.colors')
local Assets = require('constants.assets')

local M = {}

-- Use centralized constants (originals kept as fallbacks for compatibility)
local TOAST_SPACING = UIConst.SPACING.TOAST_SPACING
local DEFAULT_POSITION_X = UIConst.NOTIFICATION_POSITION and UIConst.NOTIFICATION_POSITION[1] or 10.0
local DEFAULT_POSITION_Y = UIConst.NOTIFICATION_POSITION and UIConst.NOTIFICATION_POSITION[2] or 15.0
local DEFAULT_DURATION_MS = TimingConstants.NOTIFICATION_DEFAULT_DURATION_MS or 8000

local TOAST_WINDOW_FLAGS = bit.bor(
    ImGuiWindowFlags_NoTitleBar or 0x00000001,
    ImGuiWindowFlags_NoResize or 0x00000002,
    ImGuiWindowFlags_NoMove or 0x00000004,
    ImGuiWindowFlags_NoScrollbar or 0x00000008,
    ImGuiWindowFlags_NoScrollWithMouse or 0x00000010,
    ImGuiWindowFlags_NoCollapse or 0x00000020,
    ImGuiWindowFlags_AlwaysAutoResize or 0x00000040,
    ImGuiWindowFlags_NoSavedSettings or 0x00002000,
    ImGuiWindowFlags_NoFocusOnAppearing or 0x00001000,
    ImGuiWindowFlags_NoNav or 0x00040000,
    ImGuiWindowFlags_NoInputs or 0x00020000
)

local ToastState = {
    ENTERING = "ENTERING",
    VISIBLE = "VISIBLE",
    EXITING = "EXITING",
    COMPLETE = "COMPLETE"
}

local ToastType = {
    FriendOnline = "FriendOnline",
    FriendOffline = "FriendOffline",
    FriendRequestReceived = "FriendRequestReceived",
    FriendRequestAccepted = "FriendRequestAccepted",
    FriendRequestRejected = "FriendRequestRejected",
    Error = "Error",
    Info = "Info",
    Warning = "Warning",
    Success = "Success"
}

local state = {
    initialized = false,
    hidden = false,
    positionX = DEFAULT_POSITION_X,
    positionY = DEFAULT_POSITION_Y,
    soundPolicy = nil,
    lastToastIds = {},
    activeToasts = {},
    isDragging = false,
    dragStartMouseX = 0,
    dragStartMouseY = 0,
    dragStartAnchorX = 0,
    dragStartAnchorY = 0,
    justFinishedDragging = false,
    dragEndFrame = 0
}

function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
    state.soundPolicy = NotificationSoundPolicy.NotificationSoundPolicy.new()
    state.activeToasts = {}
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs then
            state.positionX = prefs.notificationPositionX or DEFAULT_POSITION_X
            state.positionY = prefs.notificationPositionY or DEFAULT_POSITION_Y
        end
    end
end

function M.UpdateVisuals(settings)
    state.settings = settings or {}
    
    -- Don't reload position if we're currently dragging or just finished
    if state.isDragging or state.justFinishedDragging then
        return
    end
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs then
            state.positionX = prefs.notificationPositionX or DEFAULT_POSITION_X
            state.positionY = prefs.notificationPositionY or DEFAULT_POSITION_Y
        end
    end
end

function M.SetHidden(hidden)
    state.hidden = hidden or false
end

local startClock = os.clock()
local startTime = os.time()

local function getCurrentTimeMs()
    local clockElapsed = os.clock() - startClock
    return (startTime * 1000) + (clockElapsed * 1000)
end

local function getDurationFromPrefs()
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs and prefs.notificationDuration ~= nil then
            local duration = tonumber(prefs.notificationDuration)
            if duration and duration > 0 then
                return duration * 1000
            end
        end
    end
    return DEFAULT_DURATION_MS
end

local function getToastColor(toastType)
    if toastType == ToastType.FriendOnline then
        return {0.2, 1.0, 0.2, 1.0}
    elseif toastType == ToastType.FriendOffline then
        return {0.8, 0.8, 0.8, 1.0}
    elseif toastType == ToastType.FriendRequestReceived or toastType == ToastType.FriendRequestAccepted then
        return {0.2, 0.6, 1.0, 1.0}
    elseif toastType == ToastType.FriendRequestRejected then
        return {1.0, 0.6, 0.2, 1.0}
    elseif toastType == ToastType.Error then
        return {1.0, 0.2, 0.2, 1.0}
    elseif toastType == ToastType.Warning then
        return {1.0, 0.8, 0.0, 1.0}
    elseif toastType == ToastType.Success then
        return {0.2, 0.8, 0.2, 1.0}
    else
        return {0.8, 0.8, 1.0, 1.0}
    end
end

local function getProgressBarColors(toastType)
    -- Returns two colors for gradient effect: {color1, color2}
    if toastType == ToastType.FriendOnline then
        return {{0.29, 0.57, 0.21, 1.0}, {0.42, 0.75, 0.35, 1.0}}  -- Green
    elseif toastType == ToastType.FriendOffline then
        return {{0.65, 0.35, 0.35, 1.0}, {0.75, 0.45, 0.45, 1.0}}  -- Red
    elseif toastType == ToastType.FriendRequestReceived then
        return {{0.60, 0.40, 0.80, 1.0}, {0.73, 0.60, 0.87, 1.0}}  -- Purple
    elseif toastType == ToastType.FriendRequestAccepted then
        return {{0.30, 0.69, 0.31, 1.0}, {0.51, 0.78, 0.52, 1.0}}  -- Green
    elseif toastType == ToastType.FriendRequestRejected then
        return {{0.83, 0.22, 0.22, 1.0}, {0.93, 0.42, 0.42, 1.0}}  -- Red
    elseif toastType == ToastType.Error then
        return {{0.83, 0.22, 0.22, 1.0}, {0.93, 0.42, 0.42, 1.0}}  -- Red
    else
        return {{0.29, 0.56, 0.85, 1.0}, {0.42, 0.70, 0.94, 1.0}}  -- Default Blue
    end
end

local function getSoundType(toast)
    local toastType = toast.type
    if toastType == ToastType.FriendOnline then
        return NotificationSoundPolicy.NotificationSoundType.FriendOnline
    elseif toastType == ToastType.FriendRequestAccepted then
        -- Play friend online sound only if the friend is online, otherwise no sound
        if toast.isOnline then
            return NotificationSoundPolicy.NotificationSoundType.FriendOnline
        else
            return NotificationSoundPolicy.NotificationSoundType.Unknown
        end
    elseif toastType == ToastType.FriendRequestReceived then
        return NotificationSoundPolicy.NotificationSoundType.FriendRequest
    else
        return NotificationSoundPolicy.NotificationSoundType.Unknown
    end
end

local function maybePlaySound(toast)
    if not toast or type(toast) ~= "table" then
        return
    end
    
    local app = _G.FFXIFriendListApp
    if not app or not app.features or not app.features.preferences then
        return
    end
    
    local prefs = app.features.preferences:getPrefs()
    if not prefs then
        return
    end
    
    local soundsEnabled = prefs.notificationSoundsEnabled
    if soundsEnabled == false or soundsEnabled == "false" then
        return
    end
    
    local toastType = toast.type
    if not toastType then
        return
    end
    
    local soundType = getSoundType(toast)
    if soundType == NotificationSoundPolicy.NotificationSoundType.Unknown then
        return
    end
    
    local soundOnOnline = prefs.soundOnFriendOnline
    local soundOnRequest = prefs.soundOnFriendRequest
    
    if soundType == NotificationSoundPolicy.NotificationSoundType.FriendOnline then
        if soundOnOnline == false or soundOnOnline == "false" then
            return
        end
    end
    if soundType == NotificationSoundPolicy.NotificationSoundType.FriendRequest then
        if soundOnRequest == false or soundOnRequest == "false" then
            return
        end
    end
    
    local currentTime = getCurrentTimeMs()
    -- Test toasts bypass sound policy cooldown
    if not toast.isTest and not state.soundPolicy:shouldPlay(soundType, currentTime) then
        return
    end
    
    -- Use centralized asset constants for sound filenames
    local soundFile = nil
    if soundType == NotificationSoundPolicy.NotificationSoundType.FriendOnline then
        soundFile = Assets.SOUNDS.FRIEND_ONLINE
    elseif soundType == NotificationSoundPolicy.NotificationSoundType.FriendRequest then
        soundFile = Assets.SOUNDS.FRIEND_REQUEST
    end
    
    if soundFile then
        SoundPlayer.playSound(soundFile, 1.0, nil)
    end
end

local FADE_OUT_PERCENT = 0.20
local Y_ANIMATION_SPEED = 8.0

local function updateToast(toast, currentTime, prefsDurationMs)
    local elapsed = currentTime - (toast.createdAt or 0)
    local duration = prefsDurationMs
    if duration <= 0 then
        duration = DEFAULT_DURATION_MS
    end
    
    toast.duration = duration
    
    local fadeStartTime = duration * (1.0 - FADE_OUT_PERCENT)
    
    if toast.state == ToastState.ENTERING then
        toast.state = ToastState.VISIBLE
        toast.alpha = 1.0
    elseif toast.state == ToastState.VISIBLE then
        if toast.userDismissed then
            toast.state = ToastState.EXITING
        elseif elapsed >= fadeStartTime then
            toast.state = ToastState.EXITING
        end
    elseif toast.state == ToastState.EXITING then
        local fadeDuration = duration * FADE_OUT_PERCENT
        local fadeElapsed = elapsed - fadeStartTime
        
        if toast.userDismissed then
            fadeElapsed = (currentTime - (toast.dismissTime or currentTime))
            fadeDuration = 200
        end
        
        local fadeProgress = fadeElapsed / fadeDuration
        
        if fadeProgress >= 1.0 then
            toast.alpha = 0.0
            toast.state = ToastState.COMPLETE
            toast.dismissed = true  -- Mark as dismissed so it won't block future notifications with same dedupeKey
        else
            toast.alpha = math.max(0.0, 1.0 - fadeProgress)
        end
    end
end

local function renderToast(toast, targetY, isFirstToast)
    if toast.state == ToastState.COMPLETE then
        return 0
    end
    
    toast.frameCount = (toast.frameCount or 0) + 1
    local isFirstFrame = toast.frameCount <= 2
    
    if not toast.currentY then
        toast.currentY = targetY
    end
    
    local yDiff = targetY - toast.currentY
    if math.abs(yDiff) > 0.5 then
        toast.currentY = toast.currentY + yDiff * Y_ANIMATION_SPEED * 0.016
    else
        toast.currentY = targetY
    end
    
    local windowId = "##Toast_" .. tostring(toast.id or 0)
    
    local app = _G.FFXIFriendListApp
    local shiftHeld = InputHelper and InputHelper.isShiftDown() or false
    local mouseX, mouseY = imgui.GetMousePos()
    local mouseDown = imgui.IsMouseDown(0)
    local mouseReleased = imgui.IsMouseReleased(0)
    
    -- Update position if already dragging (from previous frame)
    if state.isDragging then
        if not shiftHeld or mouseReleased then
            state.isDragging = false
            state.justFinishedDragging = true
            state.dragEndFrame = (state.dragEndFrame or 0) + 1
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("notificationPositionX", state.positionX)
                app.features.preferences:setPref("notificationPositionY", state.positionY)
                app.features.preferences:save()
            end
        else
            local currentMouseX = mouseX or 0
            local currentMouseY = mouseY or 0
            local deltaX = currentMouseX - state.dragStartMouseX
            local deltaY = currentMouseY - state.dragStartMouseY
            
            local newX = state.dragStartAnchorX + deltaX
            local newY = state.dragStartAnchorY + deltaY
            
            local screenWidth = scaling.window.w or 1920
            local screenHeight = scaling.window.h or 1080
            
            -- Clamp X: leave some margin for the toast width (approximately 200-300px)
            newX = math.max(0, math.min(newX, screenWidth - 200))
            -- Clamp Y: allow toasts to go all the way to the bottom edge
            -- Only clamp the top to prevent going above screen
            newY = math.max(0, newY)
            -- Don't clamp bottom - allow toasts to go to the edge or slightly off-screen
            
            state.positionX = newX
            state.positionY = newY
        end
    end
    
    local posX = state.positionX
    -- When dragging, use state.positionY directly for the first toast
    -- Otherwise use the animated toast.currentY
    local posY
    if state.isDragging and isFirstToast then
        posY = state.positionY
        -- Also update toast.currentY to match so animation doesn't fight
        toast.currentY = state.positionY
    else
        posY = toast.currentY
    end
    
    local dynamicFlags = TOAST_WINDOW_FLAGS
    if shiftHeld then
        dynamicFlags = bit.band(dynamicFlags, bit.bnot(ImGuiWindowFlags_NoInputs or 0x00020000))
        dynamicFlags = bit.band(dynamicFlags, bit.bnot(ImGuiWindowFlags_NoMove or 0x00000004))
    end
    
    imgui.SetNextWindowPos({posX, posY}, ImGuiCond_Always)
    imgui.SetNextWindowSize({300, 0}, ImGuiCond_Always)
    
    local alpha = toast.alpha or 1.0
    if isFirstFrame then
        alpha = 0.0
    end
    
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {10, 8})
    
    local fontSizePx = 14
    local windowBgColor = {0.1, 0.1, 0.1, 0.9 * alpha}
    
    -- Check for custom notification background color
    local useCustomColor = false
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs and prefs.notificationBgColor and type(prefs.notificationBgColor) == "table" then
            local customColor = prefs.notificationBgColor
            -- Ensure we have valid color values
            if customColor.r ~= nil and customColor.g ~= nil and customColor.b ~= nil then
                windowBgColor = {
                    customColor.r or 0.1,
                    customColor.g or 0.1,
                    customColor.b or 0.1,
                    (customColor.a or 0.9) * alpha
                }
                useCustomColor = true
            end
        end
    end
    
    -- If no custom color, use theme color
    if not useCustomColor and app and app.features and app.features.themes then
        fontSizePx = app.features.themes:getFontSizePx() or 14
        local themeIndex = app.features.themes:getThemeIndex()
        if themeIndex ~= -2 then
            local success, themeColors, backgroundAlpha = pcall(function()
                local colors = app.features.themes:getCurrentThemeColors()
                local bgAlpha = app.features.themes:getBackgroundAlpha()
                return colors, bgAlpha
            end)
            if success and themeColors and themeColors.windowBgColor then
                local bgAlpha = backgroundAlpha or 0.95
                windowBgColor = {
                    themeColors.windowBgColor.r,
                    themeColors.windowBgColor.g,
                    themeColors.windowBgColor.b,
                    (themeColors.windowBgColor.a or 1.0) * bgAlpha * 0.9 * alpha
                }
            end
        end
    elseif app and app.features and app.features.themes then
        fontSizePx = app.features.themes:getFontSizePx() or 14
    end
    
    imgui.PushStyleColor(ImGuiCol_WindowBg, windowBgColor)
    
    local beginResult = imgui.Begin(windowId, true, dynamicFlags)
    if not beginResult then
        imgui.PopStyleColor(1)
        imgui.PopStyleVar(3)
        imgui.End()
        return 60
    end
    
    -- Check for new drag start (only if not already dragging)
    local isHovered = imgui.IsWindowHovered()
    if shiftHeld and isHovered and mouseDown and not state.isDragging then
        state.isDragging = true
        state.dragStartMouseX = mouseX or 0
        state.dragStartMouseY = mouseY or 0
        state.dragStartAnchorX = state.positionX
        state.dragStartAnchorY = state.positionY
    end
    
    local windowHeight = 60
    FontManager.withFont(fontSizePx, function()
        local color = getToastColor(toast.type or ToastType.Info)
        
        imgui.PushStyleColor(ImGuiCol_Text, {color[1], color[2], color[3], alpha})
        imgui.Text(toast.title or "")
        imgui.PopStyleColor()
        
        -- For FriendRequestReceived, show add-friend icon next to the message
        if toast.type == ToastType.FriendRequestReceived then
            local icons = require('libs.icons')
            if icons.RenderIcon("add_friend", 14, 14, {1.0, 1.0, 1.0, alpha}) then
                imgui.SameLine()
            end
        -- For FriendRequestAccepted, show online/offline status icon next to the message
        elseif toast.type == ToastType.FriendRequestAccepted and toast.isOnline ~= nil then
            local icons = require('libs.icons')
            if icons.RenderStatusIcon(toast.isOnline, false, 12, false) then
                imgui.SameLine()
            end
        end
        
        imgui.PushStyleColor(ImGuiCol_Text, {1.0, 1.0, 1.0, alpha * 0.9})
        imgui.TextWrapped(toast.message or "")
        imgui.PopStyleColor()
        
        local _, height = imgui.GetWindowSize()
        if height and height > 0 then
            windowHeight = height
        end
        
        toast.lastHeight = windowHeight
    end)
    
    -- Draw progress bar at the bottom (if enabled)
    local app = _G.FFXIFriendListApp
    local showProgressBar = true
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        if prefs then
            showProgressBar = prefs.notificationShowProgressBar ~= false
        end
    end
    
    if showProgressBar then
        local currentTime = getCurrentTimeMs()
        local progress = 1.0
        
        if toast.state == ToastState.VISIBLE then
            local elapsed = currentTime - (toast.createdAt or currentTime)
            local duration = toast.duration or DEFAULT_DURATION_MS
            progress = math.max(0, 1.0 - (elapsed / duration))
        elseif toast.state == ToastState.ENTERING then
            progress = 1.0
        elseif toast.state == ToastState.EXITING then
            progress = 0
        end
        
        -- Get window position and size for progress bar
        local windowPosX, windowPosY = imgui.GetWindowPos()
        local windowSizeX, windowSizeY = imgui.GetWindowSize()
        
        local barHeight = 4
        local barX = windowPosX
        local barY = windowPosY + windowSizeY - barHeight
        local barWidth = windowSizeX * progress
        
        -- Get colors for this notification type
        local barColors = getProgressBarColors(toast.type or ToastType.Info)
        local color1 = barColors[1]
        local color2 = barColors[2]
        
        -- Apply alpha from toast fade
        local barColor1R, barColor1G, barColor1B, barColor1A = color1[1], color1[2], color1[3], color1[4] * alpha
        local barColor2R, barColor2G, barColor2B, barColor2A = color2[1], color2[2], color2[3], color2[4] * alpha
        
        -- Draw the progress bar using ImGui draw list
        if barWidth > 0 then
            local drawList = imgui.GetWindowDrawList()
            drawList:AddRectFilledMultiColor(
                {barX, barY},
                {barX + barWidth, barY + barHeight},
                imgui.GetColorU32({barColor1R, barColor1G, barColor1B, barColor1A}),
                imgui.GetColorU32({barColor2R, barColor2G, barColor2B, barColor2A}),
                imgui.GetColorU32({barColor2R, barColor2G, barColor2B, barColor2A}),
                imgui.GetColorU32({barColor1R, barColor1G, barColor1B, barColor1A})
            )
        end
    end
    
    imgui.End()
    imgui.PopStyleColor(1)
    imgui.PopStyleVar(3)
    
    return windowHeight
end

function M.DrawWindow(settings, dataModule)
    if not state.initialized or state.hidden then
        return
    end
    
    if not dataModule then
        return
    end
    
    local rawToasts = dataModule.GetToasts()
    if not rawToasts then
        rawToasts = {}
    end
    
    -- Clear the "just finished dragging" flag after a few frames
    if state.justFinishedDragging then
        state.dragEndFrame = (state.dragEndFrame or 0) + 1
        if state.dragEndFrame >= 3 then
            state.justFinishedDragging = false
            state.dragEndFrame = 0
        end
    end
    
    local app = _G.FFXIFriendListApp
    local prefs = nil
    if app and app.features and app.features.preferences then
        prefs = app.features.preferences:getPrefs()
        -- Only reload position from preferences if not currently dragging and not just finished
        if prefs and not state.isDragging and not state.justFinishedDragging then
            state.positionX = prefs.notificationPositionX or DEFAULT_POSITION_X
            state.positionY = prefs.notificationPositionY or DEFAULT_POSITION_Y
        end
    end
    
    local currentTime = getCurrentTimeMs()
    local prefsDurationMs = getDurationFromPrefs()
    
    local seenIds = {}
    for i, toast in ipairs(rawToasts) do
        local toastId = toast.id or i
        seenIds[toastId] = true
        
        if not state.lastToastIds[toastId] then
            toast.state = ToastState.VISIBLE
            toast.alpha = 1.0
            if not toast.createdAt or toast.createdAt == 0 then
                toast.createdAt = currentTime
            end
            if not toast.duration or toast.duration == 0 then
                toast.duration = prefsDurationMs
            end
            maybePlaySound(toast)
            state.lastToastIds[toastId] = true
        end
        
        updateToast(toast, currentTime, prefsDurationMs)
    end
    
    local showTestPreview = false
    if prefs then
        showTestPreview = prefs.notificationShowTestPreview or false
    end
    
    if showTestPreview then
        local testToastId = "test_preview"
        seenIds[testToastId] = true
        if not state.testToast then
            state.testToast = {
                id = testToastId,
                type = ToastType.Info,
                title = "Test notification",
                message = "Drag with Shift to reposition. Notifications appear below previous notifications.",
                state = ToastState.VISIBLE,
                alpha = 1.0,
                createdAt = currentTime,
                duration = 0,
                currentY = nil,
                lastHeight = 60
            }
        end
        state.testToast.state = ToastState.VISIBLE
        state.testToast.alpha = 1.0
    else
        if state.testToast then
            state.testToast = nil
        end
    end
    
    for id, _ in pairs(state.lastToastIds) do
        if not seenIds[id] then
            state.lastToastIds[id] = nil
        end
    end
    
    local activeToasts = {}
    if showTestPreview and state.testToast then
        table.insert(activeToasts, state.testToast)
    end
    for _, toast in ipairs(rawToasts) do
        if toast.state ~= ToastState.COMPLETE then
            table.insert(activeToasts, toast)
        end
    end
    
    if #activeToasts == 0 then
        return
    end
    
    local themePushed = false
    if app and app.features and app.features.themes then
        local themesFeature = app.features.themes
        local themeIndex = themesFeature:getThemeIndex()
        
        if themeIndex ~= -2 then
            local success, err = pcall(function()
                local themeColors = themesFeature:getCurrentThemeColors()
                local backgroundAlpha = themesFeature:getBackgroundAlpha()
                local textAlpha = themesFeature:getTextAlpha()
                
                if themeColors then
                    themePushed = ThemeHelper.pushThemeStyles(themeColors, backgroundAlpha, textAlpha)
                end
            end)
        end
    end
    
    -- Check if we should stack from bottom
    local stackFromBottom = false
    if prefs and prefs.notificationStackFromBottom then
        stackFromBottom = true
    end
    
    local targetY = state.positionY
    
    if stackFromBottom then
        -- Calculate total height of all toasts (excluding exiting ones)
        local totalHeight = 0
        for i = 1, #activeToasts do
            local toast = activeToasts[i]
            local toastHeight = toast.lastHeight or 60
            if toast.state ~= ToastState.EXITING then
                if i > 1 then
                    totalHeight = totalHeight + TOAST_SPACING
                end
                totalHeight = totalHeight + toastHeight
            end
        end
        
        -- Render from bottom to top (reverse order, starting from position - totalHeight)
        targetY = state.positionY - totalHeight
        for i = #activeToasts, 1, -1 do
            local toast = activeToasts[i]
            local toastHeight = toast.lastHeight or 60
            local isFirstToast = (i == #activeToasts)  -- First is now the bottom-most
            renderToast(toast, targetY, isFirstToast)
            if toast.state ~= ToastState.EXITING then
                targetY = targetY + toastHeight + TOAST_SPACING
            end
        end
    else
        -- Default: stack from top to bottom
        for i = 1, #activeToasts do
            local toast = activeToasts[i]
            local toastHeight = toast.lastHeight or 60
            local isFirstToast = (i == 1)
            renderToast(toast, targetY, isFirstToast)
            if toast.state ~= ToastState.EXITING then
                targetY = targetY + toastHeight + TOAST_SPACING
            end
        end
    end
    
    if themePushed then
        pcall(ThemeHelper.popThemeStyles)
    end
end

function M.Cleanup()
    state.initialized = false
    state.lastToastIds = {}
    state.activeToasts = {}
    state.testToast = nil
    state.isDragging = false
end

return M
