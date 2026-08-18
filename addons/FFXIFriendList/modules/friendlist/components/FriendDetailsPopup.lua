local imgui = require('imgui')
local ThemeHelper = require('libs.themehelper')
local utils = require('modules.friendlist.components.helpers.utils')
local tagcore = require('core.tagcore')
local TagSelectDropdown = require('modules.friendlist.components.TagSelectDropdown')
local FontManager = require('app.ui.FontManager')
local nations = require('core.nations')

local M = {}

local detailsState = {
    noteText = {""},
    noteLoaded = false,
    lastFriendName = "",
    statusMessage = "",
    statusTime = 0,
    wasNoteInputActive = false
}

local function applyTheme()
    local themePushed = false
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.themes then
        local success = pcall(function()
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
    return themePushed
end

local function getValueOrUnknown(val, typeCheck)
    if val == nil then return "Unknown" end
    if typeCheck and type(val) ~= typeCheck then return "Unknown" end
    if type(val) == "string" and val == "" then return "Unknown" end
    if type(val) == "function" then return "Unknown" end
    return val
end

local function getValueOrAnon(val, typeCheck)
    if val == nil then return "Anon" end
    if typeCheck and type(val) ~= typeCheck then return "Anon" end
    if type(val) == "string" and val == "" then return "Anon" end
    if type(val) == "function" then return "Anon" end
    return val
end

local function loadNoteForFriend(friendName)
    local noteText = ""
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notes and friendName then
        noteText = app.features.notes:getNote(friendName) or ""
    end
    detailsState.noteText = {noteText}
    detailsState.noteLoaded = true
    detailsState.lastFriendName = friendName
end

local function saveNoteForFriend(friendName)
    local app = _G.FFXIFriendListApp
    if app and app.features and app.features.notes and friendName then
        local text = detailsState.noteText[1] or ""
        app.features.notes:setNote(friendName, text)
        app.features.notes:save()
        detailsState.statusMessage = "Saved"
        detailsState.statusTime = os.time()
        return true
    end
    return false
end

function M.Render(friend, state, callbacks)
    if not state.selectedFriendForDetails then
        detailsState.noteLoaded = false
        detailsState.lastFriendName = ""
        return
    end
    
    local friendName = friend.name or friend.friendName or ""
    
    if not detailsState.noteLoaded or detailsState.lastFriendName ~= friendName then
        loadNoteForFriend(friendName)
    end
    
    local themePushed = applyTheme()
    
    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoSavedSettings
    )
    
    imgui.SetNextWindowSize({400, 350}, ImGuiCond_FirstUseEver)
    
    local windowOpen = {true}
    if imgui.Begin("Friend Details##friend_details", windowOpen, windowFlags) then
        local app = _G.FFXIFriendListApp
        local fontSizePx = 14
        if app and app.features and app.features.themes then
            fontSizePx = app.features.themes:getFontSizePx() or 14
        end
        
        FontManager.withFont(fontSizePx, function()
        local displayName = friendName
        local isOnline = friend.isOnline
        local anonColor = {0.4, 0.65, 0.85, 1.0}  -- Dark sky blue
        
        -- Name
        imgui.Text("Name: " .. utils.capitalizeName(getValueOrUnknown(displayName, "string")))
        
        -- Friended As
        local friendedAs = friend.friendedAs
        if friendedAs and friendedAs ~= "" and friendedAs ~= friend.name then
            imgui.Text("Friended As: " .. utils.capitalizeName(friendedAs))
        else
            imgui.Text("Friended As: " .. utils.capitalizeName(getValueOrUnknown(friendedAs, "string")))
        end
        
        imgui.Separator()
        
        local presence = friend.presence or {}
        local isAway = friend.isAway or false
        
        -- Status - green if online, orange if away, gray if offline
        local statusText = isAway and "Away" or isOnline and "Online" or "Offline"
        if isAway then
            imgui.TextColored({1.0, 0.7, 0.2, 1.0}, "Status: " .. statusText)
        elseif isOnline then
            imgui.TextColored({0.0, 1.0, 0.0, 1.0}, "Status: " .. statusText)
        else
            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, "Status: " .. statusText)
        end
        
        -- Check if this is last known data (for offline friends)
        local isLastKnown = presence.isLastKnown or friend.isLastKnown
        local lastKnownSuffix = isLastKnown and " (Last Known)" or ""
        
        -- Job - dark sky blue if Anonymous
        local jobText = getValueOrAnon(presence.job, "string")
        local jobDisplay = "Job: " .. jobText .. (isLastKnown and jobText ~= "Anon" and lastKnownSuffix or "")
        if jobText == "Anon" then
            imgui.Text("Job: ")
            imgui.SameLine(0, 0)
            imgui.TextColored(anonColor, "Anonymous")
        else
            imgui.Text(jobDisplay)
        end
        
        -- Zone - dark sky blue if Anonymous
        local zoneText = getValueOrAnon(presence.zone, "string")
        local zoneDisplay = "Zone: " .. zoneText .. (isLastKnown and zoneText ~= "Anon" and lastKnownSuffix or "")
        if zoneText == "Anon" then
            imgui.Text("Zone: ")
            imgui.SameLine(0, 0)
            imgui.TextColored(anonColor, "Anonymous")
        else
            imgui.Text(zoneDisplay)
        end
        
        -- Nation - use nations module for proper display string
        -- Handles both numeric IDs and string values from server
        local nation = presence.nation
        local nationName = nations.getDisplayName(nation, "Anonymous")
        local isNationAnon = nations.isAnonymous(nation)
        local nationDisplay = "Nation: " .. nationName .. (isLastKnown and not isNationAnon and lastKnownSuffix or "")
        if isNationAnon then
            imgui.Text("Nation: ")
            imgui.SameLine(0, 0)
            imgui.TextColored(anonColor, "Anonymous")
        else
            imgui.Text(nationDisplay)
        end
        
        -- Rank - dark sky blue if Anonymous
        local rankText = getValueOrAnon(presence.rank, "string")
        if rankText == "Anon" and type(presence.rank) == "number" then
            rankText = tostring(presence.rank)
        end
        local rankDisplay = "Rank: " .. rankText .. (isLastKnown and rankText ~= "Anon" and lastKnownSuffix or "")
        if rankText == "Anon" then
            imgui.Text("Rank: ")
            imgui.SameLine(0, 0)
            imgui.TextColored(anonColor, "Anonymous")
        else
            imgui.Text(rankDisplay)
        end
        
        local lastSeenText = "Unknown"
        local lastSeenRaw = presence.lastSeenAt or friend.lastSeenAt or friend.lastSeen
        -- Normalize lastSeenAt to numeric timestamp (handles ISO8601 strings from server)
        local lastSeenAt = utils.normalizeLastSeen(lastSeenRaw)
        if lastSeenAt > 0 then
            lastSeenText = utils.formatRelativeTime(lastSeenAt)
        end
        if isOnline then
            imgui.Text("Last Seen: Now")
        else
            imgui.Text("Last Seen: " .. lastSeenText)
        end
        

        
        imgui.Separator()
        
        local app = _G.FFXIFriendListApp
        local tagsFeature = app and app.features and app.features.tags
        if tagsFeature then
            local friendKey = tagcore.getFriendKey(friend)
            local currentTag = tagsFeature:getTagForFriend(friendKey)
            
            local tagCallbacks = {
                onTagChanged = function(key, newTag)
                    tagsFeature:setTagForFriend(key, newTag)
                    tagsFeature:save()
                end
            }
            
            TagSelectDropdown.Render(currentTag, friendKey, tagCallbacks)
            imgui.Spacing()
        end
        
        imgui.Separator()
        
        imgui.Text("Note:")
        imgui.PushItemWidth(-1)
        imgui.InputTextMultiline("##note_input", detailsState.noteText, 4096, {-1, 80}, 0)
        imgui.PopItemWidth()
        
        -- Auto-save on focus loss
        local isNoteInputActive = imgui.IsItemActive()
        if detailsState.wasNoteInputActive and not isNoteInputActive and imgui.IsItemDeactivatedAfterEdit() then
            saveNoteForFriend(friendName)
        end
        detailsState.wasNoteInputActive = isNoteInputActive
        
        if imgui.Button("Save Note") then
            saveNoteForFriend(friendName)
        end
        
        imgui.SameLine()
        
        if imgui.Button("Delete Note") then
            local app = _G.FFXIFriendListApp
            if app and app.features and app.features.notes and friendName then
                app.features.notes:setNote(friendName, "")
                app.features.notes:save()
                detailsState.noteText = {""}
                detailsState.statusMessage = "Deleted"
                detailsState.statusTime = os.time()
            end
        end
        
        imgui.SameLine()
        
        if imgui.Button("Close") then
            state.selectedFriendForDetails = nil
            detailsState.noteLoaded = false
        end
        
        if detailsState.statusMessage ~= "" then
            local elapsed = os.time() - detailsState.statusTime
            if elapsed < 3 then
                imgui.SameLine()
                imgui.TextColored({0.0, 1.0, 0.0, 1.0}, detailsState.statusMessage)
            else
                detailsState.statusMessage = ""
            end
        end
        end)
    end
    imgui.End()
    
    if themePushed then
        pcall(ThemeHelper.popThemeStyles)
    end
    
    if not windowOpen[1] then
        state.selectedFriendForDetails = nil
        detailsState.noteLoaded = false
    end
end

return M
