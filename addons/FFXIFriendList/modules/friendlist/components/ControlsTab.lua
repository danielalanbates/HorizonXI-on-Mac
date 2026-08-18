local imgui = require('imgui')
local controllerInputHandler = require('handlers.controller_input')

local M = {}

local KEY_OPTIONS = {
    {name = "ESC", code = 27},
    {name = "Space", code = 32},
    {name = "Enter", code = 13},
    {name = "Tab", code = 9},
    {name = "Backspace", code = 8},
    {name = "Delete", code = 46},
    {name = "Insert", code = 45},
    {name = "Home", code = 36},
    {name = "End", code = 35},
    {name = "Page Up", code = 33},
    {name = "Page Down", code = 34},
    {name = "Up Arrow", code = 38},
    {name = "Down Arrow", code = 40},
    {name = "Left Arrow", code = 37},
    {name = "Right Arrow", code = 39},
    {name = "F1", code = 112},
    {name = "F2", code = 113},
    {name = "F3", code = 114},
    {name = "F4", code = 115},
    {name = "F5", code = 116},
    {name = "F6", code = 117},
    {name = "F7", code = 118},
    {name = "F8", code = 119},
    {name = "F9", code = 120},
    {name = "F10", code = 121},
    {name = "F11", code = 122},
    {name = "F12", code = 123},
    {name = "A", code = 65},
    {name = "B", code = 66},
    {name = "C", code = 67},
    {name = "D", code = 68},
    {name = "E", code = 69},
    {name = "F", code = 70},
    {name = "G", code = 71},
    {name = "H", code = 72},
    {name = "I", code = 73},
    {name = "J", code = 74},
    {name = "K", code = 75},
    {name = "L", code = 76},
    {name = "M", code = 77},
    {name = "N", code = 78},
    {name = "O", code = 79},
    {name = "P", code = 80},
    {name = "Q", code = 81},
    {name = "R", code = 82},
    {name = "S", code = 83},
    {name = "T", code = 84},
    {name = "U", code = 85},
    {name = "V", code = 86},
    {name = "W", code = 87},
    {name = "X", code = 88},
    {name = "Y", code = 89},
    {name = "Z", code = 90},
    {name = "0", code = 48},
    {name = "1", code = 49},
    {name = "2", code = 50},
    {name = "3", code = 51},
    {name = "4", code = 52},
    {name = "5", code = 53},
    {name = "6", code = 54},
    {name = "7", code = 55},
    {name = "8", code = 56},
    {name = "9", code = 57}
}

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
    
    imgui.Text("Window Close Key")
    imgui.Separator()
    imgui.Spacing()
    
    M.RenderCloseKeySection(prefs)
    
    imgui.Spacing()
    imgui.Spacing()
    
    imgui.TextWrapped("Press the configured key to close the topmost unlocked window.")
    imgui.TextWrapped("Windows can be locked via the Lock button to prevent accidental closing.")
    
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    M.RenderControllerSection(prefs)
end

function M.RenderControllerSection(prefs)
    local app = _G.FFXIFriendListApp
    
    imgui.Text("Controller Settings")
    imgui.Separator()
    imgui.Spacing()

    -- Controller Selection
    local controllers = controllerInputHandler.GetAvailableControllers()
    local currentController = prefs.controllerLayout or 'xinput'
    
    if imgui.BeginCombo("Controller Type", currentController) then
        for _, controller in ipairs(controllers) do
            local isSelected = (controller == currentController)
            if imgui.Selectable(controller, isSelected) then
                if app and app.features and app.features.preferences then
                    app.features.preferences:setPref("controllerLayout", controller)
                    app.features.preferences:save()
                    controllerInputHandler.LoadController(controller)
                end
            end
            if isSelected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end

    imgui.Spacing()
    
    local buttons = controllerInputHandler.GetActiveControllerButtons()
    
    if #buttons > 0 then
        -- 1. Open Main Window (/flist)
        local currentButton = prefs.flistBindButton or ''
        if imgui.BeginCombo("Open Main Window", currentButton == '' and "None" or currentButton) then
            if imgui.Selectable("None", (currentButton == '')) then
                 if app and app.features and app.features.preferences then
                    app.features.preferences:setPref("flistBindButton", '')
                    app.features.preferences:save()
                end
            end

            for _, btn in ipairs(buttons) do
                local isSelected = (btn == currentButton)
                if imgui.Selectable(btn, isSelected) then
                    if app and app.features and app.features.preferences then
                        app.features.preferences:setPref("flistBindButton", btn)
                        app.features.preferences:save()
                    end
                end
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        imgui.ShowHelp("Select a button to toggle the main friend list window.")
        
        -- 2. Open Compact Friend List (/fl)
        imgui.Spacing()
        local currentFlButton = prefs.flBindButton or ''
        
        if imgui.BeginCombo("Open Compact Friend List", currentFlButton == '' and "None" or currentFlButton) then
            if imgui.Selectable("None", (currentFlButton == '')) then
                if app and app.features and app.features.preferences then
                    app.features.preferences:setPref("flBindButton", '')
                    app.features.preferences:save()
                end
            end

            for _, btn in ipairs(buttons) do
                local isSelected = (btn == currentFlButton)
                if imgui.Selectable(btn, isSelected) then
                    if app and app.features and app.features.preferences then
                        app.features.preferences:setPref("flBindButton", btn)
                        app.features.preferences:save()
                    end
                end
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        imgui.ShowHelp("Select a button to toggle the compact friend list.")
        
        -- 3. Close Window Button
        imgui.Spacing()
        local currentCloseButton = prefs.closeBindButton or ''
        
        if imgui.BeginCombo("Close Window Button", currentCloseButton == '' and "None" or currentCloseButton) then
            if imgui.Selectable("None", (currentCloseButton == '')) then
                if app and app.features and app.features.preferences then
                    app.features.preferences:setPref("closeBindButton", '')
                    app.features.preferences:save()
                end
            end

            for _, btn in ipairs(buttons) do
                local isSelected = (btn == currentCloseButton)
                if imgui.Selectable(btn, isSelected) then
                    if app and app.features and app.features.preferences then
                        app.features.preferences:setPref("closeBindButton", btn)
                        app.features.preferences:save()
                    end
                end
                if isSelected then
                    imgui.SetItemDefaultFocus()
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine()
        imgui.ShowHelp("Select a button to close the top-most unlocked window.")
    else
        imgui.TextDisabled("No buttons available (Controller not loaded?)")
    end
end

function M.RenderCloseKeySection(prefs)
    local currentKeyName = "None"
    local currentKeyCode = prefs.customCloseKeyCode or 0
    
    if currentKeyCode > 0 then
        for _, option in ipairs(KEY_OPTIONS) do
            if option.code == currentKeyCode then
                currentKeyName = option.name
                break
            end
        end
        -- Handle unknown keys
        if currentKeyName == "None" then
            currentKeyName = string.format("Key %d", currentKeyCode)
        end
    end

    if imgui.BeginCombo("Keyboard Key", currentKeyName) then
        if imgui.Selectable("None", (currentKeyCode == 0)) then
            local app = _G.FFXIFriendListApp
            if app and app.features and app.features.preferences then
                app.features.preferences:setPref("customCloseKeyCode", 0)
                app.features.preferences:save()
            end
        end
        
        for _, option in ipairs(KEY_OPTIONS) do
            local isSelected = (option.code == currentKeyCode)
            if imgui.Selectable(option.name, isSelected) then
                local app = _G.FFXIFriendListApp
                if app and app.features and app.features.preferences then
                    app.features.preferences:setPref("customCloseKeyCode", option.code)
                    app.features.preferences:save()
                end
            end
            if isSelected then
                imgui.SetItemDefaultFocus()
            end
        end
        imgui.EndCombo()
    end
    
    imgui.SameLine()
    imgui.ShowHelp("Key to close the top-most unlocked window.")
end

return M