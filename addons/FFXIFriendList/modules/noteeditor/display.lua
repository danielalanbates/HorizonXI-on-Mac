local imgui = require('imgui')
local ThemeHelper = require('libs.themehelper')
local FontManager = require('app.ui.FontManager')

local M = {}

local MAX_NOTE_SIZE = 8192
local WINDOW_ID = "##noteeditor_main"

local state = {
    initialized = false,
    hidden = false,
    windowOpen = false,
    locked = false,
    noteInputBuffer = {},
    wasInputActive = false
}

local function saveWindowState()
    if not gConfig then
        return
    end
    
    if not gConfig.windows then
        gConfig.windows = {}
    end
    
    gConfig.windows.noteEditor = {
        visible = state.windowOpen,
        locked = state.locked
    }
    
    local settings = require('libs.settings')
    if settings and settings.save then
        settings.save()
    end
end

local function formatTimestamp(timestampMs)
    if not timestampMs or timestampMs == 0 then
        return "Never"
    end
    
    local time = math.floor(timestampMs / 1000)
    local date = os.date("*t", time)
    if date then
        return string.format("%04d-%02d-%02d %02d:%02d:%02d", 
            date.year, date.month, date.day, date.hour, date.min, date.sec)
    end
    return "Unknown"
end

local function autoSaveIfNeeded(dataModule)
    if not dataModule then
        return
    end
    
    if dataModule.HasUnsavedChanges and dataModule.HasUnsavedChanges() then
        if dataModule.SaveNote then
            dataModule.SaveNote()
        end
    end
end

function M.Initialize(settings)
    state.initialized = true
    state.settings = settings or {}
    state.noteInputBuffer = {""}
    
    if gConfig and gConfig.windows and gConfig.windows.noteEditor then
        local windowState = gConfig.windows.noteEditor
        if windowState.visible ~= nil then
            state.windowOpen = windowState.visible
        else
            state.windowOpen = false
        end
        if windowState.locked ~= nil then
            state.locked = windowState.locked
        end
    else
        state.windowOpen = false
    end
end

function M.UpdateVisuals(settings)
end

function M.SetVisible(visible, dataModule)
    local newValue = visible or false
    
    if not newValue and state.windowOpen then
        if not dataModule then
            local moduleRegistry = _G.moduleRegistry
            if moduleRegistry then
                local entry = moduleRegistry.Get("noteEditor")
                if entry and entry.module and entry.module.data then
                    dataModule = entry.module.data
                end
            end
        end
        autoSaveIfNeeded(dataModule)
        if dataModule and dataModule.CloseEditor then
            dataModule.CloseEditor()
        end
    end
    
    if state.windowOpen ~= newValue then
        state.windowOpen = newValue
        saveWindowState()
    end
end

function M.IsVisible()
    return state.windowOpen or false
end

function M.SetHidden(hidden)
    state.hidden = hidden or false
end

function M.DrawWindow(settings, dataModule)
    if not state.initialized or state.hidden then
        return
    end
    
    if not dataModule then
        return
    end
    
    if not dataModule.IsEditorOpen or not dataModule.IsEditorOpen() then
        state.windowOpen = false
        return
    end
    
    if not state.windowOpen then
        return
    end
    
    local windowFlags = 0
    local app = _G.FFXIFriendListApp
    local globalLocked = false
    local globalPositionLocked = false
    if app and app.features and app.features.preferences then
        local prefs = app.features.preferences:getPrefs()
        globalLocked = prefs and prefs.windowsLocked or false
        globalPositionLocked = prefs and prefs.windowsPositionLocked or false
    end
    if globalPositionLocked or state.locked then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove)
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoResize)
    end
    
    if gConfig and gConfig.windows and gConfig.windows.noteEditor then
        local windowState = gConfig.windows.noteEditor
        if windowState.posX and windowState.posY then
            imgui.SetNextWindowPos({windowState.posX, windowState.posY}, ImGuiCond_FirstUseEver)
        end
        if windowState.sizeX and windowState.sizeY then
            imgui.SetNextWindowSize({windowState.sizeX, windowState.sizeY}, ImGuiCond_FirstUseEver)
        else
            imgui.SetNextWindowSize({500, 400}, ImGuiCond_FirstUseEver)
        end
    else
        imgui.SetNextWindowSize({500, 400}, ImGuiCond_FirstUseEver)
    end
    
    local friendName = ""
    if dataModule.GetCurrentFriendName then
        friendName = dataModule.GetCurrentFriendName() or ""
    end
    local windowTitle = "Edit Note" .. WINDOW_ID
    
    if gConfig and gConfig.windows and gConfig.windows.noteEditor then
        state.locked = gConfig.windows.noteEditor.locked or false
    end
    
    local themePushed = false
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        local success, err = pcall(function()
            local themesFeature = app.features.themes
            local themeIndex = themesFeature:getThemeIndex()
            
            if themeIndex ~= -2 then
                local themeColors = themesFeature:getCurrentThemeColors()
                local backgroundAlpha = themesFeature:getBackgroundAlpha()
                local textAlpha = themesFeature:getTextAlpha()
                
                if themeColors then
                    themePushed = ThemeHelper.pushThemeStyles(themeColors, backgroundAlpha, textAlpha)
                end
            end
        end)
    end
    
    local windowOpenTable = {state.windowOpen}
    local windowOpen = imgui.Begin(windowTitle, windowOpenTable, windowFlags)
    
    if not windowOpen then
        imgui.End()
        if themePushed then
            ThemeHelper.popThemeStyles()
        end
        
        if not windowOpenTable[1] then
            if state.locked or globalLocked then
                state.windowOpen = true
            else
                local closeGating = require('ui.close_gating')
                if closeGating.shouldDeferClose() then
                    state.windowOpen = true
                else
                    autoSaveIfNeeded(dataModule)
                    state.windowOpen = false
                    if dataModule.CloseEditor then
                        dataModule.CloseEditor()
                    end
                    saveWindowState()
                end
            end
        end
        return
    end
    
    state.windowOpen = windowOpenTable[1]
    
    local app = _G.FFXIFriendListApp
    local fontSizePx = 14
    if app and app.features and app.features.themes then
        fontSizePx = app.features.themes:getFontSizePx() or 14
    end
    
    FontManager.withFont(fontSizePx, function()
    if imgui.Button("Lock") then
        state.locked = not state.locked
        saveWindowState()
    end
    imgui.SameLine()
    
    imgui.Text("Note for " .. friendName)
    
    imgui.Separator()
    
    imgui.Text("Storage: Local")
    
    local lastSavedAt = 0
    if dataModule.GetLastSavedAt then
        lastSavedAt = dataModule.GetLastSavedAt() or 0
    end
    if lastSavedAt > 0 then
        imgui.Text("Last saved: " .. formatTimestamp(lastSavedAt))
    else
        imgui.Text("Last saved: Never")
    end
    
    local errorMsg = ""
    if dataModule.GetError then
        errorMsg = dataModule.GetError() or ""
    end
    if errorMsg ~= "" then
        imgui.TextColored({1.0, 0.0, 0.0, 1.0}, "Error: " .. errorMsg)
    end
    
    local statusMsg = ""
    if dataModule.GetStatus then
        statusMsg = dataModule.GetStatus() or ""
    end
    if statusMsg ~= "" then
        imgui.TextColored({0.0, 1.0, 0.0, 1.0}, statusMsg)
    end
    
    imgui.Separator()
    
    local currentNoteText = ""
    if dataModule.GetCurrentNoteText then
        currentNoteText = dataModule.GetCurrentNoteText() or ""
    end
    if state.noteInputBuffer[1] ~= currentNoteText then
        state.noteInputBuffer[1] = currentNoteText
    end
    
    local inputFlags = 0
    local changed = imgui.InputTextMultiline("##note_input", state.noteInputBuffer, MAX_NOTE_SIZE + 1, {0, 200}, inputFlags)
    
    if changed and dataModule.SetNoteText then
        dataModule.SetNoteText(state.noteInputBuffer[1] or "")
    end
    
    local isInputActive = imgui.IsItemActive()
    if state.wasInputActive and not isInputActive and imgui.IsItemDeactivatedAfterEdit() then
        autoSaveIfNeeded(dataModule)
    end
    state.wasInputActive = isInputActive
    
    local currentLength = string.len(state.noteInputBuffer[1] or "")
    imgui.Text(string.format("Characters: %d / %d", currentLength, MAX_NOTE_SIZE))
    
    imgui.Separator()
    
    if imgui.Button("Delete Note") then
        if dataModule.DeleteNote and dataModule.DeleteNote() then
            state.noteInputBuffer[1] = ""
        end
    end
    
    imgui.SameLine()
    
    if imgui.Button("Clear") then
        state.noteInputBuffer[1] = ""
        if dataModule.SetNoteText then
            dataModule.SetNoteText("")
        end
    end
    
    imgui.SameLine()
    
    if imgui.Button("Close") then
        autoSaveIfNeeded(dataModule)
        state.windowOpen = false
        if dataModule.CloseEditor then
            dataModule.CloseEditor()
        end
        saveWindowState()
    end
    
    if not state.windowOpen then
        local posX, posY = imgui.GetWindowPos()
        local sizeX, sizeY = imgui.GetWindowSize()
        
        if gConfig then
            if not gConfig.windows then
                gConfig.windows = {}
            end
            if not gConfig.windows.noteEditor then
                gConfig.windows.noteEditor = {}
            end
            
            gConfig.windows.noteEditor.posX = posX
            gConfig.windows.noteEditor.posY = posY
            gConfig.windows.noteEditor.sizeX = sizeX
            gConfig.windows.noteEditor.sizeY = sizeY
        end
    end
    end)
    
    imgui.End()
    
    if themePushed then
        ThemeHelper.popThemeStyles()
    end
end

function M.Cleanup()
    state.initialized = false
end

return M
