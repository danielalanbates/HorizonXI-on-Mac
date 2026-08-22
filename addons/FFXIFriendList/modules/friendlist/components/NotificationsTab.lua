local imgui = require('imgui')

local M = {}

function M.Render(state, dataModule, callbacks)
    local app = _G.FFXIFriendListApp
    local prefs = nil
    if app and app.features and app.features.preferences then
        prefs = app.features.preferences:getPrefs()
    end
    
    if not prefs then
        imgui.Text("Preferences not available")
        return
    end
    
    local prefsDuration = tonumber(prefs.notificationDuration) or 8.0
    if prefsDuration < 1.0 then prefsDuration = 8.0 end
    
    if not state.notificationDuration then
        state.notificationDuration = prefsDuration
        state.lastNotificationDurationValue = prefsDuration
    end
    if not state.soundVolumeDisplay then
        state.soundVolumeDisplay = (tonumber(prefs.notificationSoundVolume) or 0.6) * 100.0
        state.lastSoundVolumeValue = tonumber(prefs.notificationSoundVolume) or 0.6
    end
    
    if math.abs(state.notificationDuration - prefsDuration) > 0.1 and 
       math.abs(state.lastNotificationDurationValue - prefsDuration) < 0.01 then
        state.notificationDuration = prefsDuration
        state.lastNotificationDurationValue = prefsDuration
    end
    
    local currentVolume = prefs.notificationSoundVolume or 0.6
    local currentVolumeDisplay = currentVolume * 100.0
    if math.abs(state.soundVolumeDisplay - currentVolumeDisplay) > 5.0 and
       math.abs(state.lastSoundVolumeValue - currentVolume) < 0.01 then
        state.soundVolumeDisplay = currentVolumeDisplay
        state.lastSoundVolumeValue = currentVolume
    end
    
    local soundsEnabled = {prefs.notificationSoundsEnabled ~= false}
    if imgui.Checkbox("Enable Notification Sounds", soundsEnabled) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationSoundsEnabled", soundsEnabled[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Enable or disable all notification sounds.")
    end
    
    imgui.Spacing()
    
    local soundOnOnline = {prefs.soundOnFriendOnline ~= false}
    if imgui.Checkbox("Play Sound on Friend Online", soundOnOnline) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("soundOnFriendOnline", soundOnOnline[1])
            app.features.preferences:save()
        end
    end
    imgui.SameLine()
    if imgui.Button("Test Notification##friend_online") then
        if app and app.features and app.features.notifications then
            app.features.notifications:showTestFriendOnline(nil)
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Play a sound when a friend comes online.")
    end
    
    if not soundsEnabled[1] then
        imgui.PushStyleColor(ImGuiCol_Text, {0.5, 0.5, 0.5, 1.0})
        imgui.PushStyleColor(ImGuiCol_CheckMark, {0.5, 0.5, 0.5, 1.0})
    end
    
    imgui.Spacing()
    
    local soundOnRequest = {prefs.soundOnFriendRequest ~= false}
    local checkboxChanged = false
    if soundsEnabled[1] then
        checkboxChanged = imgui.Checkbox("Play Sound on Friend Request", soundOnRequest)
    else
        local disabledValue = {prefs.soundOnFriendRequest ~= false}
        imgui.Checkbox("Play Sound on Friend Request", disabledValue)
    end
    imgui.SameLine()
    if imgui.Button("Test Notification##friend_request") then
        if app and app.features and app.features.notifications then
            app.features.notifications:showTestFriendRequest(nil)
        end
    end
    
    if checkboxChanged then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("soundOnFriendRequest", soundOnRequest[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Play a sound when you receive a friend request.")
    end
    
    if not soundsEnabled[1] then
        imgui.PopStyleColor(2)
    end
    
    imgui.Spacing()
    
    local volumeValue = {state.soundVolumeDisplay}
    if imgui.SliderFloat("Notification Sound Volume", volumeValue, 0.0, 100.0, "%.0f%%") then
        local normalizedValue = volumeValue[1] / 100.0
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationSoundVolume", normalizedValue)
            state.lastSoundVolumeValue = normalizedValue
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Adjust the volume for notification sounds.")
    end
    if imgui.IsItemDeactivatedAfterEdit() then
        local normalizedValue = volumeValue[1] / 100.0
        if app and app.features and app.features.preferences then
            app.features.preferences:save()
        end
    end
    state.soundVolumeDisplay = volumeValue[1]
    
    if not soundsEnabled[1] then
        imgui.PushStyleColor(ImGuiCol_Text, {0.5, 0.5, 0.5, 1.0})
        imgui.PushStyleColor(ImGuiCol_SliderGrab, {0.5, 0.5, 0.5, 1.0})
    end
    
    imgui.Spacing()
    
    local durationValue = {state.notificationDuration}
    local sliderChanged = false
    if soundsEnabled[1] then
        sliderChanged = imgui.SliderFloat("Notification Duration (seconds)", durationValue, 1.0, 30.0, "%.1f")
    else
        imgui.SliderFloat("Notification Duration (seconds)", durationValue, 1.0, 30.0, "%.1f")
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("How long notification toasts remain visible on screen.")
    end
    
    if sliderChanged then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationDuration", durationValue[1])
            state.lastNotificationDurationValue = durationValue[1]
        end
    end
    if soundsEnabled[1] and imgui.IsItemDeactivatedAfterEdit() then
        if app and app.features and app.features.preferences then
            app.features.preferences:save()
        end
    end
    state.notificationDuration = durationValue[1]
    
    if not soundsEnabled[1] then
        imgui.PopStyleColor(2)
    end
    
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    imgui.Text("Notification Display Filters:")
    imgui.Spacing()
    
    local showFriendOnline = {prefs.notificationShowFriendOnline ~= false}
    if imgui.Checkbox("Show friend online notifications", showFriendOnline) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowFriendOnline", showFriendOnline[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show notifications when friends come online.")
    end
    
    local showFriendOffline = {prefs.notificationShowFriendOffline ~= false}
    if imgui.Checkbox("Show friend offline notifications", showFriendOffline) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowFriendOffline", showFriendOffline[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show notifications when friends go offline.")
    end
    
    local showFriendRequest = {prefs.notificationShowFriendRequest ~= false}
    if imgui.Checkbox("Show friend request notifications", showFriendRequest) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowFriendRequest", showFriendRequest[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show notifications when you receive a friend request.")
    end
    
    local showRequestAccepted = {prefs.notificationShowRequestAccepted ~= false}
    if imgui.Checkbox("Show request accepted notifications", showRequestAccepted) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowRequestAccepted", showRequestAccepted[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show notifications when someone accepts your friend request.")
    end
    
    local showRequestRejected = {prefs.notificationShowRequestRejected ~= false}
    if imgui.Checkbox("Show request rejected notifications", showRequestRejected) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowRequestRejected", showRequestRejected[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show notifications when someone rejects your friend request.")
    end
    
    imgui.Spacing()
    
    M.RenderNotificationBackgroundColor(state, prefs)
    
    imgui.Spacing()
    
    local stackFromBottom = {prefs.notificationStackFromBottom or false}
    if imgui.Checkbox("Stack notifications from bottom", stackFromBottom) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationStackFromBottom", stackFromBottom[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When enabled, notifications start at the bottom and stack upward. When disabled, they start at the top and stack downward.")
    end
    
    imgui.Spacing()
    
    local showProgressBar = {prefs.notificationShowProgressBar ~= false}
    if imgui.Checkbox("Show notification progress bar", showProgressBar) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowProgressBar", showProgressBar[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show a progress bar at the bottom of notifications indicating time remaining.")
    end
    
    imgui.Spacing()
    
    local showTestPreview = {prefs.notificationShowTestPreview or false}
    if imgui.Checkbox("Show test notification", showTestPreview) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationShowTestPreview", showTestPreview[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show a persistent test notification that can be dragged with Shift to set the position.")
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    imgui.Text("Tip: Hold Shift and drag a notification to reposition it.")
    imgui.Text("Enable 'Show test notification' to place it easily.")
    
    imgui.Spacing()
    
    M.RenderNotificationPosition(state, prefs)
end

function M.RenderNotificationPosition(state, prefs)
    local app = _G.FFXIFriendListApp
    
    imgui.Text("Position (X, Y pixels):")
    
    if not state.notificationPosXBuffer then
        state.notificationPosXBuffer = {string.format("%.3f", prefs.notificationPositionX or 0.0)}
        state.notificationPosYBuffer = {string.format("%.3f", prefs.notificationPositionY or 0.0)}
        state.lastPosX = prefs.notificationPositionX or 0.0
        state.lastPosY = prefs.notificationPositionY or 0.0
    end
    
    local currentPosX = prefs.notificationPositionX or 0.0
    local currentPosY = prefs.notificationPositionY or 0.0
    if math.abs(state.lastPosX - currentPosX) > 0.01 then
        state.notificationPosXBuffer[1] = string.format("%.3f", currentPosX)
        state.lastPosX = currentPosX
    end
    if math.abs(state.lastPosY - currentPosY) > 0.01 then
        state.notificationPosYBuffer[1] = string.format("%.3f", currentPosY)
        state.lastPosY = currentPosY
    end
    
    imgui.Text("X:")
    imgui.SameLine(0, 5)
    imgui.PushItemWidth(100)
    if imgui.InputText("##x_pos", state.notificationPosXBuffer, 64) then
        local x = tonumber(state.notificationPosXBuffer[1])
        if x then
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("notificationPositionX", x)
                state.lastPosX = x
            end
        end
    end
    if imgui.IsItemDeactivatedAfterEdit() then
        local x = tonumber(state.notificationPosXBuffer[1])
        if x then
            if app and app.features and app.features.preferences then
                app.features.preferences:save()
            end
        else
            state.notificationPosXBuffer[1] = string.format("%.3f", state.lastPosX)
        end
    end
    imgui.PopItemWidth()
    
    imgui.SameLine(0, 10)
    imgui.Text("Y:")
    imgui.SameLine(0, 5)
    imgui.PushItemWidth(100)
    if imgui.InputText("##y_pos", state.notificationPosYBuffer, 64) then
        local y = tonumber(state.notificationPosYBuffer[1])
        if y then
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("notificationPositionY", y)
                state.lastPosY = y
            end
        end
    end
    if imgui.IsItemDeactivatedAfterEdit() then
        local y = tonumber(state.notificationPosYBuffer[1])
        if y then
            if app and app.features and app.features.preferences then
                app.features.preferences:save()
            end
        else
            state.notificationPosYBuffer[1] = string.format("%.3f", state.lastPosY)
        end
    end
    imgui.PopItemWidth()
end

function M.RenderNotificationBackgroundColor(state, prefs)
    local app = _G.FFXIFriendListApp
    if not app or not app.features or not app.features.preferences then
        return
    end
    
    -- Get current theme color for default/display
    local function getThemeColor()
        local themeColor = {0.1, 0.1, 0.1, 0.9}
        if app.features.themes then
            local themeIndex = app.features.themes:getThemeIndex()
            if themeIndex ~= -2 then
                local success, themeColors, backgroundAlpha = pcall(function()
                    local colors = app.features.themes:getCurrentThemeColors()
                    local bgAlpha = app.features.themes:getBackgroundAlpha()
                    return colors, bgAlpha
                end)
                if success and themeColors and themeColors.windowBgColor then
                    local bgAlpha = backgroundAlpha or 0.95
                    themeColor = {
                        themeColors.windowBgColor.r,
                        themeColors.windowBgColor.g,
                        themeColors.windowBgColor.b,
                        (themeColors.windowBgColor.a or 1.0) * bgAlpha * 0.9
                    }
                end
            end
        end
        return themeColor
    end
    
    -- Initialize frame counter if needed
    state.notificationBgColorSaveFrame = state.notificationBgColorSaveFrame or 0
    
    -- Initialize buffer if needed (only on first load or when explicitly reset)
    if not state.notificationBgColorBuffer then
        if prefs.notificationBgColor and type(prefs.notificationBgColor) == "table" and
           prefs.notificationBgColor.r ~= nil and prefs.notificationBgColor.g ~= nil and prefs.notificationBgColor.b ~= nil then
            state.notificationBgColorBuffer = {
                prefs.notificationBgColor.r,
                prefs.notificationBgColor.g,
                prefs.notificationBgColor.b,
                prefs.notificationBgColor.a or 0.9
            }
        else
            state.notificationBgColorBuffer = getThemeColor()
        end
    end
    
    -- Color picker flags
    local ImGuiColorEditFlags_AlphaBar = 0x00010000
    local ImGuiColorEditFlags_AlphaPreviewHalf = 0x00040000
    local colorEditFlags = ImGuiColorEditFlags_AlphaBar + ImGuiColorEditFlags_AlphaPreviewHalf
    
    imgui.Text("Background Color:")
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Customize the notification background color. Defaults to theme window background.")
    end
    
    -- Render the color picker
    local colorChanged = imgui.ColorEdit4("##notification_bg_color", state.notificationBgColorBuffer, colorEditFlags)
    
    -- Track if user is currently editing (must be called after ColorEdit4)
    local isEditing = imgui.IsItemActive()
    local wasEditing = state.notificationBgColorEditing or false
    state.notificationBgColorEditing = isEditing
    
    -- Increment frame counter each frame when not editing (resets to 0 when saving)
    if not isEditing and not wasEditing then
        state.notificationBgColorSaveFrame = state.notificationBgColorSaveFrame + 1
    end
    
    -- Only sync from preferences if:
    -- 1. Not currently editing
    -- 2. Was not editing last frame
    -- 3. At least 3 frames have passed since last save (to prevent immediate overwrites)
    local framesSinceSave = state.notificationBgColorSaveFrame
    local shouldSync = not isEditing and not wasEditing and framesSinceSave >= 3
    
    if shouldSync then
        local currentColor = prefs.notificationBgColor
        if currentColor and type(currentColor) == "table" and
           currentColor.r ~= nil and currentColor.g ~= nil and currentColor.b ~= nil then
            -- Only update if buffer is different from preference (external change)
            if math.abs((state.notificationBgColorBuffer[1] or 0) - (currentColor.r or 0)) > 0.01 or
               math.abs((state.notificationBgColorBuffer[2] or 0) - (currentColor.g or 0)) > 0.01 or
               math.abs((state.notificationBgColorBuffer[3] or 0) - (currentColor.b or 0)) > 0.01 or
               math.abs((state.notificationBgColorBuffer[4] or 0) - (currentColor.a or 0)) > 0.01 then
                state.notificationBgColorBuffer = {
                    currentColor.r,
                    currentColor.g,
                    currentColor.b,
                    currentColor.a or 0.9
                }
            end
        elseif not currentColor then
            -- If preference is nil, update buffer to theme color
            local themeColor = getThemeColor()
            if math.abs((state.notificationBgColorBuffer[1] or 0) - themeColor[1]) > 0.01 or
               math.abs((state.notificationBgColorBuffer[2] or 0) - themeColor[2]) > 0.01 or
               math.abs((state.notificationBgColorBuffer[3] or 0) - themeColor[3]) > 0.01 or
               math.abs((state.notificationBgColorBuffer[4] or 0) - themeColor[4]) > 0.01 then
                state.notificationBgColorBuffer = themeColor
            end
        end
    end
    
    -- Handle color changes from user input
    if colorChanged then
        if app and app.features and app.features.preferences then
            local savedColor = {
                r = state.notificationBgColorBuffer[1],
                g = state.notificationBgColorBuffer[2],
                b = state.notificationBgColorBuffer[3],
                a = state.notificationBgColorBuffer[4]
            }
            app.features.preferences:setPref("notificationBgColor", savedColor)
            app.features.preferences:save()
            -- Reset frame counter to prevent immediate overwrites
            state.notificationBgColorSaveFrame = 0
        end
    end
    
    -- Handle deactivation (user finished editing)
    if imgui.IsItemDeactivatedAfterEdit() then
        if app and app.features and app.features.preferences then
            local savedColor = {
                r = state.notificationBgColorBuffer[1],
                g = state.notificationBgColorBuffer[2],
                b = state.notificationBgColorBuffer[3],
                a = state.notificationBgColorBuffer[4]
            }
            app.features.preferences:setPref("notificationBgColor", savedColor)
            app.features.preferences:save()
            -- Reset frame counter to prevent immediate overwrites
            state.notificationBgColorSaveFrame = 0
        end
    end
    
    imgui.SameLine(0, 10)
    if imgui.Button("Use Theme##notification_bg_theme") then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("notificationBgColor", nil)
            app.features.preferences:save()
            state.notificationBgColorBuffer = nil
            state.notificationBgColorSaveFrame = 0
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Use the theme's window background color for notifications.")
    end
end

return M

