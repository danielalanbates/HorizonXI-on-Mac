local imgui = require('imgui')

local M = {}

function M.Render(state, dataModule, callbacks)
    local themesDataModule = require('modules.themes.data')
    if not themesDataModule then
        imgui.Text("Themes data module not available")
        return
    end
    
    local testNames = themesDataModule.GetBuiltInThemeNames()
    if not testNames or #testNames == 0 then
        themesDataModule.Initialize({})
    end
    
    themesDataModule.Update()
    
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        state.themeBackgroundAlpha = app.features.themes:getBackgroundAlpha() or 0.95
        state.themeTextAlpha = app.features.themes:getTextAlpha() or 1.0
        state.themeFontSizePx = app.features.themes:getFontSizePx() or 14
    end
    
    local currentThemeIndex = themesDataModule.GetCurrentThemeIndex()
    if currentThemeIndex ~= state.themeLastThemeIndex then
        M.SyncThemeColorsToBuffers(state, themesDataModule)
        state.themeLastThemeIndex = currentThemeIndex
    end
    
    M.RenderIconSettings(state)
    imgui.Spacing()
    M.RenderThemeSelection(state, themesDataModule)
    imgui.Spacing()
    M.RenderThemeManagement(state, themesDataModule)
end

function M.SyncThemeColorsToBuffers(state, dataModule)
    if not dataModule or dataModule.IsDefaultTheme() then
        return
    end
    
    local colors = dataModule.GetCurrentThemeColors()
    if not colors then
        return
    end
    
    local function syncColor(bufferKey, colorObj)
        if colorObj then
            state.themeColorBuffers[bufferKey] = {colorObj.r, colorObj.g, colorObj.b, colorObj.a}
        end
    end
    
    syncColor("windowBg", colors.windowBgColor)
    syncColor("childBg", colors.childBgColor)
    syncColor("frameBg", colors.frameBgColor)
    syncColor("frameBgHovered", colors.frameBgHovered)
    syncColor("frameBgActive", colors.frameBgActive)
    syncColor("titleBg", colors.titleBg)
    syncColor("titleBgActive", colors.titleBgActive)
    syncColor("titleBgCollapsed", colors.titleBgCollapsed)
    syncColor("button", colors.buttonColor)
    syncColor("buttonHover", colors.buttonHoverColor)
    syncColor("buttonActive", colors.buttonActiveColor)
    syncColor("separator", colors.separatorColor)
    syncColor("separatorHovered", colors.separatorHovered)
    syncColor("separatorActive", colors.separatorActive)
    syncColor("scrollbarBg", colors.scrollbarBg)
    syncColor("scrollbarGrab", colors.scrollbarGrab)
    syncColor("scrollbarGrabHovered", colors.scrollbarGrabHovered)
    syncColor("scrollbarGrabActive", colors.scrollbarGrabActive)
    syncColor("checkMark", colors.checkMark)
    syncColor("sliderGrab", colors.sliderGrab)
    syncColor("sliderGrabActive", colors.sliderGrabActive)
    syncColor("header", colors.header)
    syncColor("headerHovered", colors.headerHovered)
    syncColor("headerActive", colors.headerActive)
    syncColor("text", colors.textColor)
    syncColor("textDisabled", colors.textDisabled)
    syncColor("border", colors.borderColor)
end

function M.SyncThemeBuffersToColors(state)
    local app = _G.FFXIFriendListApp
    if not app or not app.features or not app.features.themes then
        return
    end
    
    local themesFeature = app.features.themes
    
    local function bufferToColor(bufferKey)
        local b = state.themeColorBuffers[bufferKey]
        return {r = b[1], g = b[2], b = b[3], a = b[4]}
    end
    
    local colors = {
        windowBgColor = bufferToColor("windowBg"),
        childBgColor = bufferToColor("childBg"),
        frameBgColor = bufferToColor("frameBg"),
        frameBgHovered = bufferToColor("frameBgHovered"),
        frameBgActive = bufferToColor("frameBgActive"),
        titleBg = bufferToColor("titleBg"),
        titleBgActive = bufferToColor("titleBgActive"),
        titleBgCollapsed = bufferToColor("titleBgCollapsed"),
        buttonColor = bufferToColor("button"),
        buttonHoverColor = bufferToColor("buttonHover"),
        buttonActiveColor = bufferToColor("buttonActive"),
        separatorColor = bufferToColor("separator"),
        separatorHovered = bufferToColor("separatorHovered"),
        separatorActive = bufferToColor("separatorActive"),
        scrollbarBg = bufferToColor("scrollbarBg"),
        scrollbarGrab = bufferToColor("scrollbarGrab"),
        scrollbarGrabHovered = bufferToColor("scrollbarGrabHovered"),
        scrollbarGrabActive = bufferToColor("scrollbarGrabActive"),
        checkMark = bufferToColor("checkMark"),
        sliderGrab = bufferToColor("sliderGrab"),
        sliderGrabActive = bufferToColor("sliderGrabActive"),
        header = bufferToColor("header"),
        headerHovered = bufferToColor("headerHovered"),
        headerActive = bufferToColor("headerActive"),
        textColor = bufferToColor("text"),
        textDisabled = bufferToColor("textDisabled"),
        borderColor = bufferToColor("border")
    }
    
    themesFeature:updateCurrentThemeColors(colors)
end

function M.RenderIconSettings(state)
    if imgui.CollapsingHeader("Icon Settings", state.iconSettingsExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0) then
        state.iconSettingsExpanded = true
        
        local app = _G.FFXIFriendListApp
        local prefs = nil
        if app and app.features and app.features.preferences then
            prefs = app.features.preferences:getPrefs()
        end
        
        if not prefs then
            imgui.Text("Preferences not available")
            return
        end
        
        -- Tab Icon Settings Section
        imgui.TextColored({0.9, 0.7, 0.4, 1.0}, "Navigation Tab Icons")
        imgui.Separator()
        imgui.Spacing()
        
        local useIconsForTabs = {prefs.useIconsForTabs or false}
        if imgui.Checkbox("Use Icons for Tabs", useIconsForTabs) then
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("useIconsForTabs", useIconsForTabs[1])
                app.features.preferences:save()
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("When enabled, navigation tabs will show icons instead of text labels.")
        end
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        
        -- Initialize global color buffer first (before any buttons/widgets use it)
        if not state.themeColorBuffers.tabIcon then
            if prefs.tabIconTint then
                state.themeColorBuffers.tabIcon = {prefs.tabIconTint.r, prefs.tabIconTint.g, prefs.tabIconTint.b, prefs.tabIconTint.a}
            else
                state.themeColorBuffers.tabIcon = {1.0, 1.0, 1.0, 1.0}
            end
        end
        
        -- Global Icon Color (default for all)
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Global Icon Color:")
        imgui.SameLine()
        if imgui.SmallButton("Apply to All##global") then
            -- Apply global color to all individual icons
            local globalColor = {
                r = state.themeColorBuffers.tabIcon[1],
                g = state.themeColorBuffers.tabIcon[2],
                b = state.themeColorBuffers.tabIcon[3],
                a = state.themeColorBuffers.tabIcon[4]
            }
            if app and app.features and app.features.preferences then
                -- Save the global color itself
                app.features.preferences:setPref("tabIconTint", globalColor)
                -- Apply to all individual icons
                local tabIconColors = prefs.tabIconColors or {}
                for _, key in ipairs({"friends", "requests", "view", "privacy", "tags", "notifications", "themes", "help"}) do
                    tabIconColors[key] = {r = globalColor.r, g = globalColor.g, b = globalColor.b, a = globalColor.a}
                    -- Update buffers too
                    state.themeColorBuffers["tabIcon_" .. key] = {globalColor.r, globalColor.g, globalColor.b, globalColor.a}
                end
                app.features.preferences:setPref("tabIconColors", tabIconColors)
                app.features.preferences:save()
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Apply this color to all tab icons")
        end
        
        if imgui.ColorEdit4("##tab_icon_global", state.themeColorBuffers.tabIcon) then
            local color = state.themeColorBuffers.tabIcon
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("tabIconTint", {
                    r = color[1],
                    g = color[2],
                    b = color[3],
                    a = color[4]
                })
                app.features.preferences:save()
            end
        end
        
        imgui.SameLine()
        if imgui.Button("Reset##global") then
            state.themeColorBuffers.tabIcon = nil
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("tabIconTint", {r = 1.0, g = 1.0, b = 1.0, a = 1.0})
                app.features.preferences:save()
            end
        end
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        
        -- Individual Icon Colors
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Individual Icon Colors:")
        imgui.SameLine()
        if imgui.SmallButton("Clear All##individual") then
            -- Clear all individual icon colors (revert to global)
            if app and app.features and app.features.preferences then
                for _, key in ipairs({"friends", "requests", "view", "privacy", "tags", "notifications", "themes", "help"}) do
                    state.themeColorBuffers["tabIcon_" .. key] = nil
                end
                app.features.preferences:setPref("tabIconColors", nil)
                app.features.preferences:save()
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Clear all individual colors and use global color")
        end
        
        imgui.Spacing()
        
        local iconNames = {
            {key = "friends", label = "Friends"},
            {key = "requests", label = "Requests"},
            {key = "view", label = "View"},
            {key = "privacy", label = "Privacy"},
            {key = "tags", label = "Tags"},
            {key = "notifications", label = "Notifications"},
            {key = "themes", label = "Themes"},
            {key = "help", label = "Help"}
        }
        
        for _, iconData in ipairs(iconNames) do
            local key = iconData.key
            local label = iconData.label
            local bufferKey = "tabIcon_" .. key
            
            -- Initialize color buffer if needed
            if not state.themeColorBuffers[bufferKey] then
                if prefs.tabIconColors and prefs.tabIconColors[key] then
                    local c = prefs.tabIconColors[key]
                    state.themeColorBuffers[bufferKey] = {c.r, c.g, c.b, c.a}
                else
                    -- Use global color as default
                    local globalColor = state.themeColorBuffers.tabIcon or {1.0, 1.0, 1.0, 1.0}
                    state.themeColorBuffers[bufferKey] = {globalColor[1], globalColor[2], globalColor[3], globalColor[4]}
                end
            end
            
            imgui.Text(label .. ":")
            imgui.SameLine(100)
            imgui.PushItemWidth(180)
            if imgui.ColorEdit4("##" .. bufferKey, state.themeColorBuffers[bufferKey]) then
                local color = state.themeColorBuffers[bufferKey]
                if app and app.features and app.features.preferences then
                    local tabIconColors = prefs.tabIconColors or {}
                    tabIconColors[key] = {
                        r = color[1],
                        g = color[2],
                        b = color[3],
                        a = color[4]
                    }
                    app.features.preferences:setPref("tabIconColors", tabIconColors)
                    app.features.preferences:save()
                end
            end
            imgui.PopItemWidth()
            
            imgui.SameLine()
            if imgui.SmallButton("Clear##" .. key) then
                if app and app.features and app.features.preferences then
                    local tabIconColors = prefs.tabIconColors or {}
                    tabIconColors[key] = nil
                    -- Remove the key entirely if setting to nil
                    if next(tabIconColors) == nil then
                        -- Empty table, set whole preference to nil
                        app.features.preferences:setPref("tabIconColors", nil)
                    else
                        app.features.preferences:setPref("tabIconColors", tabIconColors)
                    end
                    state.themeColorBuffers[bufferKey] = nil
                    app.features.preferences:save()
                end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Clear this icon's color (use global)")
            end
        end
        
        imgui.Spacing()
        imgui.Spacing()
        
        -- UI Icon Settings Section
        imgui.TextColored({0.9, 0.7, 0.4, 1.0}, "UI Action Icons")
        imgui.Separator()
        imgui.Spacing()
        
        -- Global UI Icon Color (default for all)
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Global UI Icon Color:")
        imgui.SameLine()
        if imgui.SmallButton("Apply to All##uiglobal") then
            -- Apply global color to all individual UI icons
            if not state.themeColorBuffers.uiIcon then
                state.themeColorBuffers.uiIcon = {1.0, 1.0, 1.0, 1.0}
            end
            local globalColor = {
                r = state.themeColorBuffers.uiIcon[1],
                g = state.themeColorBuffers.uiIcon[2],
                b = state.themeColorBuffers.uiIcon[3],
                a = state.themeColorBuffers.uiIcon[4]
            }
            if app and app.features and app.features.preferences then
                -- Apply to all individual icons
                local uiIconColors = prefs.uiIconColors or {}
                for _, key in ipairs({"lock", "unlock", "refresh", "collapse", "expand", "discord", "github", "heart"}) do
                    uiIconColors[key] = {r = globalColor.r, g = globalColor.g, b = globalColor.b, a = globalColor.a}
                    -- Update buffers too
                    state.themeColorBuffers["uiIcon_" .. key] = {globalColor.r, globalColor.g, globalColor.b, globalColor.a}
                end
                app.features.preferences:setPref("uiIconColors", uiIconColors)
                app.features.preferences:save()
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Apply this color to all UI icons")
        end
        
        -- Initialize global color buffer if needed
        if not state.themeColorBuffers.uiIcon then
            state.themeColorBuffers.uiIcon = {1.0, 1.0, 1.0, 1.0}
        end
        
        if imgui.ColorEdit4("##ui_icon_global", state.themeColorBuffers.uiIcon) then
            -- This is just a reference color, not saved to preferences
            -- Individual colors are saved separately
        end
        
        imgui.SameLine()
        if imgui.Button("Reset##uiglobal") then
            state.themeColorBuffers.uiIcon = {1.0, 1.0, 1.0, 1.0}
        end
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        
        -- Individual UI Icon Colors
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Individual UI Icon Colors:")
        imgui.SameLine()
        if imgui.SmallButton("Clear All##uiindividual") then
            -- Clear all individual UI icon colors (revert to white)
            if app and app.features and app.features.preferences then
                for _, key in ipairs({"lock", "unlock", "refresh", "collapse", "expand", "discord", "github", "heart"}) do
                    state.themeColorBuffers["uiIcon_" .. key] = nil
                end
                app.features.preferences:setPref("uiIconColors", nil)
                app.features.preferences:save()
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip("Clear all individual UI icon colors and use default white")
        end
        
        imgui.Spacing()
        
        local uiIconNames = {
            {key = "lock", label = "Lock"},
            {key = "unlock", label = "Unlock"},
            {key = "refresh", label = "Refresh"},
            {key = "collapse", label = "Collapse"},
            {key = "expand", label = "Expand"},
            {key = "discord", label = "Discord"},
            {key = "github", label = "GitHub"},
            {key = "heart", label = "About"}
        }
        
        for _, iconData in ipairs(uiIconNames) do
            local key = iconData.key
            local label = iconData.label
            local bufferKey = "uiIcon_" .. key
            
            -- Initialize color buffer if needed
            if not state.themeColorBuffers[bufferKey] then
                if prefs.uiIconColors and prefs.uiIconColors[key] then
                    local c = prefs.uiIconColors[key]
                    state.themeColorBuffers[bufferKey] = {c.r, c.g, c.b, c.a}
                else
                    -- Use white as default
                    state.themeColorBuffers[bufferKey] = {1.0, 1.0, 1.0, 1.0}
                end
            end
            
            imgui.Text(label .. ":")
            imgui.SameLine(100)
            imgui.PushItemWidth(180)
            if imgui.ColorEdit4("##" .. bufferKey, state.themeColorBuffers[bufferKey]) then
                local color = state.themeColorBuffers[bufferKey]
                if app and app.features and app.features.preferences then
                    local uiIconColors = prefs.uiIconColors or {}
                    uiIconColors[key] = {
                        r = color[1],
                        g = color[2],
                        b = color[3],
                        a = color[4]
                    }
                    app.features.preferences:setPref("uiIconColors", uiIconColors)
                    app.features.preferences:save()
                end
            end
            imgui.PopItemWidth()
            
            imgui.SameLine()
            if imgui.SmallButton("Clear##" .. key) then
                if app and app.features and app.features.preferences then
                    local uiIconColors = prefs.uiIconColors or {}
                    uiIconColors[key] = nil
                    -- Remove the key entirely if setting to nil
                    if next(uiIconColors) == nil then
                        -- Empty table, set whole preference to nil
                        app.features.preferences:setPref("uiIconColors", nil)
                    else
                        app.features.preferences:setPref("uiIconColors", uiIconColors)
                    end
                    state.themeColorBuffers[bufferKey] = nil
                    app.features.preferences:save()
                end
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Clear this icon's color (use default white)")
            end
        end
    else
        state.iconSettingsExpanded = false
    end
end

function M.RenderThemeSelection(state, dataModule)
    if imgui.CollapsingHeader("Theme Selection", state.themeSelectionExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0) then
        state.themeSelectionExpanded = true
        
        local builtInNames = dataModule.GetBuiltInThemeNames() or {}
        local customThemes = dataModule.GetCustomThemes() or {}
        
        local allThemeNames = {}
        local themeIndices = {}
        
        for i, name in ipairs(builtInNames) do
            table.insert(allThemeNames, name)
            local themeIndex = i - 1
            table.insert(themeIndices, themeIndex)
        end
        
        for _, customTheme in ipairs(customThemes) do
            table.insert(allThemeNames, customTheme.name or "Unknown")
            table.insert(themeIndices, -1)
        end
        
        if #allThemeNames == 0 then
            imgui.Text("No themes available")
            return
        end
        
        local currentThemeIndex = dataModule.GetCurrentThemeIndex()
        local currentThemeName = dataModule.GetCurrentThemeName()
        local currentComboIndex = 0
        
        for i, themeIndex in ipairs(themeIndices) do
            if themeIndex == currentThemeIndex then
                if themeIndex == -1 then
                    if allThemeNames[i] == currentThemeName then
                        currentComboIndex = i - 1
                        break
                    end
                else
                    currentComboIndex = i - 1
                    break
                end
            end
        end
        
        local previewText = allThemeNames[currentComboIndex + 1] or "Classic"
        if imgui.BeginCombo("Theme", previewText) then
            for i = 1, #allThemeNames do
                local isSelected = (i - 1 == currentComboIndex)
                local itemText = allThemeNames[i]
                if imgui.Selectable(itemText, isSelected) then
                    if not isSelected then
                        local selectedIndex = themeIndices[i]
                        local app = _G.FFXIFriendListApp
                        if app and app.features and app.features.themes then
                            if selectedIndex == -1 then
                                local themeName = allThemeNames[i]
                                app.features.themes:setCustomTheme(themeName)
                            else
                                app.features.themes:applyTheme(selectedIndex)
                            end
                        end
                    end
                end
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndCombo()
        end
        
        imgui.Spacing()
        
        imgui.Text("Background Transparency:")
        local bgAlpha = {state.themeBackgroundAlpha}
        if imgui.SliderFloat("##bgAlpha", bgAlpha, 0.0, 1.0, "%.2f") then
            state.themeBackgroundAlpha = bgAlpha[1]
            local app = _G.FFXIFriendListApp
            if app and app.features and app.features.themes then
                app.features.themes:setBackgroundAlpha(bgAlpha[1])
            end
        end
        
        imgui.Text("Text Transparency:")
        local textAlpha = {state.themeTextAlpha}
        if imgui.SliderFloat("##textAlpha", textAlpha, 0.0, 1.0, "%.2f") then
            state.themeTextAlpha = textAlpha[1]
            local app = _G.FFXIFriendListApp
            if app and app.features and app.features.themes then
                app.features.themes:setTextAlpha(textAlpha[1])
            end
        end
        
        imgui.Spacing()
        
        imgui.Text("Font Size:")
        local fontSizes = {14, 18, 24, 32}
        local fontSizeLabels = {"14px", "18px", "24px", "32px"}
        local currentFontSize = state.themeFontSizePx or 14
        local currentFontIndex = 0
        for i, size in ipairs(fontSizes) do
            if size == currentFontSize then
                currentFontIndex = i - 1
                break
            end
        end
        
        local previewLabel = fontSizeLabels[currentFontIndex + 1] or "14px"
        if imgui.BeginCombo("##fontSizePx", previewLabel) then
            for i, label in ipairs(fontSizeLabels) do
                local isSelected = (i - 1 == currentFontIndex)
                if imgui.Selectable(label, isSelected) then
                    state.themeFontSizePx = fontSizes[i]
                    local app = _G.FFXIFriendListApp
                    if app and app.features and app.features.themes then
                        app.features.themes:setFontSizePx(fontSizes[i])
                    end
                end
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndCombo()
        end
        
        imgui.Spacing()
        
        M.RenderCustomColors(state)
    else
        state.themeSelectionExpanded = false
    end
end

function M.RenderCustomColors(state)
    if imgui.CollapsingHeader("Custom Colors", state.customColorsExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0) then
        state.customColorsExpanded = true
        
        -- ImGui color edit flags (correct values from Dear ImGui)
        local ImGuiColorEditFlags_AlphaBar = 0x00010000         -- 1 << 16: Show alpha bar
        local ImGuiColorEditFlags_AlphaPreviewHalf = 0x00040000 -- 1 << 18: Preview with checkerboard
        local colorEditFlags = ImGuiColorEditFlags_AlphaBar + ImGuiColorEditFlags_AlphaPreviewHalf
        
        local function renderColorPicker(label, bufferKey)
            local color = state.themeColorBuffers[bufferKey]
            if imgui.ColorEdit4(label, color, colorEditFlags) then
                M.SyncThemeBuffersToColors(state)
            end
        end
        
        imgui.Text("Window Colors:")
        renderColorPicker("Window Background", "windowBg")
        renderColorPicker("Child Background", "childBg")
        renderColorPicker("Frame Background", "frameBg")
        renderColorPicker("Frame Hovered", "frameBgHovered")
        renderColorPicker("Frame Active", "frameBgActive")
        
        imgui.Spacing()
        
        imgui.Text("Title Colors:")
        renderColorPicker("Title Background", "titleBg")
        renderColorPicker("Title Active", "titleBgActive")
        renderColorPicker("Title Collapsed", "titleBgCollapsed")
        
        imgui.Spacing()
        
        imgui.Text("Button Colors:")
        renderColorPicker("Button", "button")
        renderColorPicker("Button Hovered", "buttonHover")
        renderColorPicker("Button Active", "buttonActive")
        
        imgui.Spacing()
        
        imgui.Text("Separator Colors:")
        renderColorPicker("Separator", "separator")
        renderColorPicker("Separator Hovered", "separatorHovered")
        renderColorPicker("Separator Active", "separatorActive")
        
        imgui.Spacing()
        
        imgui.Text("Scrollbar Colors:")
        renderColorPicker("Scrollbar Bg", "scrollbarBg")
        renderColorPicker("Scrollbar Grab", "scrollbarGrab")
        renderColorPicker("Scrollbar Grab Hovered", "scrollbarGrabHovered")
        renderColorPicker("Scrollbar Grab Active", "scrollbarGrabActive")
        
        imgui.Spacing()
        
        imgui.Text("Check/Slider Colors:")
        renderColorPicker("Check Mark", "checkMark")
        renderColorPicker("Slider Grab", "sliderGrab")
        renderColorPicker("Slider Grab Active", "sliderGrabActive")
        
        imgui.Spacing()
        
        imgui.Text("Header Colors:")
        renderColorPicker("Header", "header")
        renderColorPicker("Header Hovered", "headerHovered")
        renderColorPicker("Header Active", "headerActive")
        
        imgui.Spacing()
        
        imgui.Text("Text Colors:")
        renderColorPicker("Text", "text")
        renderColorPicker("Text Disabled", "textDisabled")
        
        imgui.Spacing()
        
        imgui.Text("Border Color:")
        renderColorPicker("Border", "border")
    else
        state.customColorsExpanded = false
    end
end

function M.RenderThemeManagement(state, dataModule)
    if imgui.CollapsingHeader("Theme Management", state.themeManagementExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0) then
        state.themeManagementExpanded = true
        
        imgui.Text("Save Current Colors as Theme")
        imgui.Text("Theme Name:")
        if imgui.InputText("##saveThemeName", state.themeNewThemeName, 256) then
        end
        
        local canSave = state.themeNewThemeName[1] and state.themeNewThemeName[1] ~= "" and #state.themeNewThemeName[1] > 0
        if not canSave then
            imgui.PushStyleColor(ImGuiCol_Button, {0.5, 0.5, 0.5, 1.0})
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.5, 0.5, 0.5, 1.0})
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.5, 0.5, 0.5, 1.0})
        end
        
        if imgui.Button("Save Custom Theme") then
            if canSave then
                M.SyncThemeBuffersToColors(state)
                local app = _G.FFXIFriendListApp
                if app and app.features and app.features.themes then
                    local colors = dataModule.GetCurrentThemeColors()
                    if colors then
                        colors.name = state.themeNewThemeName[1]
                        app.features.themes:saveCustomTheme(state.themeNewThemeName[1], colors)
                        state.themeNewThemeName[1] = ""
                    end
                end
            end
        end
        
        if not canSave then
            imgui.PopStyleColor(3)
        end
        
        local currentCustomThemeName = dataModule.GetCurrentCustomThemeName() or ""
        if currentCustomThemeName ~= "" then
            imgui.Spacing()
            if imgui.Button("Delete Custom Theme") then
                local app = _G.FFXIFriendListApp
                if app and app.features and app.features.themes then
                    app.features.themes:deleteCustomTheme(currentCustomThemeName)
                end
            end
        end
    else
        state.themeManagementExpanded = false
    end
end

return M

