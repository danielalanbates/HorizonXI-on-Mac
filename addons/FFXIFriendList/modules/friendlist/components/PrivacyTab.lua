local imgui = require('imgui')
local PresenceStatusPicker = require('ui.widgets.PresenceStatusPicker')
local nations = require('core.nations')

local M = {}

-- Local state for fetching character status from server
local state = {
    characterStatus = nil,
    lastFetchedCharacterId = nil
}

function M.Render(state, dataModule, callbacks)
    M.RenderPrivacyControlsSection(state, callbacks)
    imgui.Spacing()
    M.RenderBlockedPlayersSection(state, dataModule, callbacks)
end

function M.RenderMenuDetectionSection(state, callbacks)
    local headerLabel = "Menu Detection"
    local isOpen = imgui.CollapsingHeader(headerLabel, state.menuDetectionExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0)
    
    if isOpen ~= state.menuDetectionExpanded then
        state.menuDetectionExpanded = isOpen
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    
    if not isOpen then return end
    
    local menuDetectionEnabled = gConfig and gConfig.menuDetectionEnabled ~= false
    local checked = {menuDetectionEnabled}
    
    if imgui.Checkbox("Enable Menu Detection", checked) then
        if gConfig then
            gConfig.menuDetectionEnabled = checked[1]
            local settings = require('libs.settings')
            if settings and settings.save then
                settings.save()
            end
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When enabled, Compact Friend List window automatically opens when\nyou open the in-game Friend List menu (To List).\n\nDisable if you prefer to open windows manually.")
    end
end

function M.RenderFriendViewSettingsSection(state, callbacks)
    local headerLabel = "Friend View Settings"
    local isOpen = imgui.CollapsingHeader(headerLabel, state.friendViewSettingsExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0)
    
    if isOpen ~= state.friendViewSettingsExpanded then
        state.friendViewSettingsExpanded = isOpen
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    
    if not isOpen then return end
    
    imgui.Text("Main Window Columns:")
    
    if imgui.Checkbox("Show Job", {state.columnVisible.job}) then
        state.columnVisible.job = not state.columnVisible.job
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show the Job column (current job of online friends).")
    end
    
    if imgui.Checkbox("Show Zone", {state.columnVisible.zone}) then
        state.columnVisible.zone = not state.columnVisible.zone
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show the Zone column (current zone of online friends).")
    end
    
    if imgui.Checkbox("Show Nation/Rank", {state.columnVisible.nationRank}) then
        state.columnVisible.nationRank = not state.columnVisible.nationRank
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show the Nation and Rank column.")
    end
    
    if imgui.Checkbox("Show Last Seen", {state.columnVisible.lastSeen}) then
        state.columnVisible.lastSeen = not state.columnVisible.lastSeen
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show the Last Seen column (when the friend was last online).\nDisplays 'Now' for online friends.")
    end
    
    if imgui.Checkbox("Show Added As", {state.columnVisible.addedAs}) then
        state.columnVisible.addedAs = not state.columnVisible.addedAs
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Show the Added As column (the character name used when adding this friend).")
    end
    

end

function M.RenderHoverTooltipSettings(state, callbacks)
    local headerLabel = "Hover Tooltip Settings"
    local isOpen = imgui.CollapsingHeader(headerLabel, state.hoverTooltipSettingsExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0)
    
    if isOpen ~= state.hoverTooltipSettingsExpanded then
        state.hoverTooltipSettingsExpanded = isOpen
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    
    if not isOpen then return end
    
    local app = _G.FFXIFriendListApp
    local prefs = nil
    if app and app.features and app.features.preferences then
        prefs = app.features.preferences:getPrefs()
    end
    
    if not prefs then
        imgui.Text("Preferences not available")
        return
    end
    
    imgui.TextWrapped("Configure what appears when hovering over a friend's name.")
    imgui.TextDisabled("Hold SHIFT while hovering to show all fields.")
    imgui.Spacing()
    
    imgui.Text("Main Window Hover:")
    imgui.Indent()
    
    local mainHover = prefs.mainHoverTooltip
    if mainHover then
        local changed = false
        
        local showJob = {mainHover.showJob}
        if imgui.Checkbox("Job##main_hover", showJob) then
            mainHover.showJob = showJob[1]
            changed = true
        end
        imgui.SameLine()
        
        local showZone = {mainHover.showZone}
        if imgui.Checkbox("Zone##main_hover", showZone) then
            mainHover.showZone = showZone[1]
            changed = true
        end
        imgui.SameLine()
        
        local showNationRank = {mainHover.showNationRank}
        if imgui.Checkbox("Nation/Rank##main_hover", showNationRank) then
            mainHover.showNationRank = showNationRank[1]
            changed = true
        end
        
        local showLastSeen = {mainHover.showLastSeen}
        if imgui.Checkbox("Last Seen##main_hover", showLastSeen) then
            mainHover.showLastSeen = showLastSeen[1]
            changed = true
        end
        imgui.SameLine()
        
        local showFriendedAs = {mainHover.showFriendedAs}
        if imgui.Checkbox("Added As##main_hover", showFriendedAs) then
            mainHover.showFriendedAs = showFriendedAs[1]
            changed = true
        end
        imgui.SameLine()
        

        
        if changed and app.features.preferences then
            app.features.preferences:save()
        end
    end
    
    imgui.Unindent()
    imgui.Spacing()
    
    imgui.Text("Compact Friend List Hover:")
    imgui.Indent()
    
    local quickHover = prefs.quickOnlineHoverTooltip
    if quickHover then
        local changed = false
        
        local showJob = {quickHover.showJob}
        if imgui.Checkbox("Job##quick_hover", showJob) then
            quickHover.showJob = showJob[1]
            changed = true
        end
        imgui.SameLine()
        
        local showZone = {quickHover.showZone}
        if imgui.Checkbox("Zone##quick_hover", showZone) then
            quickHover.showZone = showZone[1]
            changed = true
        end
        imgui.SameLine()
        
        local showNationRank = {quickHover.showNationRank}
        if imgui.Checkbox("Nation/Rank##quick_hover", showNationRank) then
            quickHover.showNationRank = showNationRank[1]
            changed = true
        end
        
        local showLastSeen = {quickHover.showLastSeen}
        if imgui.Checkbox("Last Seen##quick_hover", showLastSeen) then
            quickHover.showLastSeen = showLastSeen[1]
            changed = true
        end
        imgui.SameLine()
        
        local showFriendedAs = {quickHover.showFriendedAs}
        if imgui.Checkbox("Added As##quick_hover", showFriendedAs) then
            quickHover.showFriendedAs = showFriendedAs[1]
            changed = true
        end
        imgui.SameLine()
        

        
        if changed and app.features.preferences then
            app.features.preferences:save()
        end
    end
    
    imgui.Unindent()
end

function M.RenderPrivacyControlsSection(state, callbacks)
    local headerLabel = "Privacy"
    local isOpen = imgui.CollapsingHeader(headerLabel, state.privacyControlsExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0)
    
    if isOpen ~= state.privacyControlsExpanded then
        state.privacyControlsExpanded = isOpen
        if callbacks.onSaveState then callbacks.onSaveState() end
        
        -- Auto-refresh preview when tab is first opened
        if isOpen then
            local app = _G.FFXIFriendListApp
            if app then
                state.lastFetchedCharacterId = nil  -- Force re-fetch
                M._fetchCharacterStatus(app)
            end
        end
    end
    
    if not isOpen then return end
    
    local app = _G.FFXIFriendListApp
    local prefs = nil
    if app and app.features and app.features.preferences then
        prefs = app.features.preferences:getPrefs()
    end
    
    if not prefs then
        imgui.Text("Preferences not available")
        return
    end
    
    local shareJobWhenAnonymous = {prefs.shareJobWhenAnonymous or false}
    if imgui.Checkbox("Share Job, Nation, and Rank when Anonymous", shareJobWhenAnonymous) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("shareJobWhenAnonymous", shareJobWhenAnonymous[1])
            app.features.preferences:save()
            app.features.preferences:syncToServer()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When enabled, your job, nation, and rank are shared even when\nyou're set to anonymous mode in-game.\n\n[Account-wide: Synced to server for all characters]")
    end
    
    imgui.Spacing()
    
    local shareLocation = {prefs.shareLocation ~= false}
    if imgui.Checkbox("Share Location", shareLocation) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("shareLocation", shareLocation[1])
            app.features.preferences:save()
            app.features.preferences:syncToServer()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When enabled, your current zone is shared with friends.\nWhen disabled, friends will only see that you're online.\n\n[Account-wide: Synced to server for all characters]")
    end
    
    imgui.Spacing()
    
    imgui.Text("Presence Status:")
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Controls how your online status appears to friends.\n\n[Account-wide: Synced to server for all characters]")
    end
    
    PresenceStatusPicker.RenderRadioButtons("_privacy_tab", true)
    
    imgui.Spacing()
    imgui.Spacing()
    
    -- Notification muting
    local dontSendNotifications = {prefs.dontSendNotificationsGlobal or false}
    if imgui.Checkbox("Prevent Friend Notifications", dontSendNotifications) then
        if app and app.features and app.features.preferences then
            app.features.preferences:setPref("dontSendNotificationsGlobal", dontSendNotifications[1])
            app.features.preferences:save()
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("When enabled, you won't receive notifications when friends come online.\n\n[Character-specific: Stored locally]")
    end
    
    imgui.Spacing()
    imgui.Spacing()
    
    -- Show preview of how friends see your information
    M.RenderPresencePreview(prefs)
end

--- Render a preview showing how friends see your information
function M.RenderPresencePreview(prefs)
    local app = _G.FFXIFriendListApp
    
    -- Get CURRENT presence from local client (always up-to-date with packet detection + memory fallback)
    local charStatus = nil
    if app and app.features and app.features.friends then
        charStatus = app.features.friends:queryPlayerPresence()
    end
    
    -- Use SERVER preferences - these are what matter to friends
    local presenceStatus = prefs.presenceStatus or "online"
    local shareLocation = prefs.shareLocation ~= false
    local shareJobWhenAnonymous = prefs.shareJobWhenAnonymous or false
    
    imgui.TextDisabled("Preview: How friends see you (live)")
    imgui.Separator()
    
    -- Determine status and color
    local statusColor = {0.4, 0.9, 0.4, 1.0}  -- Green for online
    local statusText = "Online"
    local isInvisible = presenceStatus == "invisible"
    
    if isInvisible then
        statusColor = {0.5, 0.5, 0.5, 1.0}  -- Gray for offline
        statusText = "Offline"
    elseif presenceStatus == "away" then
        statusColor = {1.0, 0.7, 0.2, 1.0}  -- Orange for away
        statusText = "Away"
    end
    
    imgui.BeginGroup()
    imgui.TextDisabled("Status:")
    imgui.SameLine(100)
    imgui.TextColored(statusColor, statusText)
    imgui.EndGroup()
    
    if isInvisible then
        imgui.TextDisabled("You appear offline - all information hidden from friends")
        imgui.Spacing()
    end
    
    -- Character name
    local charName = "Unknown"
    if charStatus and charStatus.characterName and charStatus.characterName ~= "" then
        charName = charStatus.characterName:sub(1,1):upper() .. charStatus.characterName:sub(2)
    end
    
    imgui.TextDisabled("Character:")
    imgui.SameLine(100)
    if isInvisible then
        imgui.TextDisabled(charName)
    else
        imgui.Text(charName)
    end
    
    -- Job
    imgui.TextDisabled("Job:")
    imgui.SameLine(100)
    if shareJobWhenAnonymous or (charStatus and not charStatus.isAnonymous) then
        local jobText = "Unknown"
        -- Use the already-formatted job string from queryPlayerPresence()
        if charStatus and charStatus.job and charStatus.job ~= "" then
            jobText = charStatus.job
        end
        if isInvisible then
            imgui.TextDisabled(jobText)
        else
            imgui.Text(jobText)
        end
    else
        if isInvisible then
            imgui.TextDisabled("Hidden")
        else
            imgui.TextColored({0.4, 0.65, 0.85, 1.0}, "Hidden")
            end
        end
        
        -- Nation/Rank
        imgui.TextDisabled("Nation:")
        imgui.SameLine(100)
        if shareJobWhenAnonymous or (charStatus and not charStatus.isAnonymous) then
            local nationText = "Unknown"
            if charStatus and charStatus.nation then
                local nationName = nations.getDisplayName(charStatus.nation, "Unknown")
                -- charStatus.rank is a formatted string like "Rank 10" or a number
                if charStatus.rank then
                    if type(charStatus.rank) == "string" and charStatus.rank ~= "" then
                        nationText = nationName .. " " .. charStatus.rank
                    elseif type(charStatus.rank) == "number" and charStatus.rank > 0 then
                        nationText = nationName .. " Rank " .. tostring(charStatus.rank)
                    else
                        nationText = nationName
                    end
                else
                    nationText = nationName
                end
            end
            if isInvisible then
                imgui.TextDisabled(nationText)
            else
                imgui.Text(nationText)
            end
        else
            if isInvisible then
                imgui.TextDisabled("Hidden")
            else
                imgui.TextColored({0.4, 0.65, 0.85, 1.0}, "Hidden")
            end
        end
        
        -- Zone
        imgui.TextDisabled("Zone:")
        imgui.SameLine(100)
        if shareLocation then
            local zoneText = "Unknown"
            if charStatus and charStatus.zone then
                zoneText = tostring(charStatus.zone)
            end
            if isInvisible then
                imgui.TextDisabled(zoneText)
            else
                imgui.Text(zoneText)
            end
        else
            if isInvisible then
                imgui.TextDisabled("Hidden")
            else
                imgui.TextColored({0.4, 0.65, 0.85, 1.0}, "Hidden")
            end
        end
end

function M._fetchCharacterStatus(app)
    if not app or not app.deps or not app.deps.net then
        return
    end
    
    -- Need connection for baseUrl and headers
    if not app.features or not app.features.connection then
        return
    end
    
    local connection = app.features.connection
    if not connection:isConnected() then
        return
    end
    
    local Endpoints = require('protocol.Endpoints')
    local Envelope = require('protocol.Envelope')
    
    -- Build full URL with base
    local baseUrl = connection:getBaseUrl()
    local url = baseUrl .. Endpoints.PRESENCE.ME
    local headers = connection:getHeaders(connection:getCharacterName())
    
    app.deps.net.request({
        url = url,
        method = 'GET',
        headers = headers,
        body = "",
        callback = function(success, response)
            if not success then
                if app.deps.logger and app.deps.logger.warn then
                    app.deps.logger.warn("[PrivacyTab] Failed to fetch character status")
                end
                return
            end
            
            local ok, envelope, errorMsg = Envelope.decode(response)
            if not ok then
                if app.deps.logger and app.deps.logger.warn then
                    app.deps.logger.warn("[PrivacyTab] Failed to decode response: " .. tostring(errorMsg))
                end
                return
            end
            
            if envelope.data then
                state.characterStatus = envelope.data
            end
        end
    })
end

function M.RenderBlockedPlayersSection(state, dataModule, callbacks)
    local headerLabel = "Blocked Players"
    local blockedCount = dataModule.GetBlockedPlayersCount()
    if blockedCount > 0 then
        headerLabel = headerLabel .. " (" .. blockedCount .. ")"
    end
    
    local isOpen = imgui.CollapsingHeader(headerLabel, state.blockedPlayersExpanded and ImGuiTreeNodeFlags_DefaultOpen or 0)
    
    if isOpen ~= state.blockedPlayersExpanded then
        state.blockedPlayersExpanded = isOpen
        if callbacks.onSaveState then callbacks.onSaveState() end
    end
    
    if not isOpen then return end
    
    local blocked = dataModule.GetBlockedPlayers()
    
    if #blocked == 0 then
        imgui.TextDisabled("No blocked players.")
        imgui.TextWrapped("You can block players from the Requests tab when they send you a friend request.")
    else
        imgui.TextWrapped("Blocked players cannot send you friend requests.")
        imgui.Spacing()
        
        imgui.BeginChild("##blocked_players_list", {0, 150}, true)
        
        for i, entry in ipairs(blocked) do
            imgui.PushID("blocked_" .. i)
            
            local displayName = entry.displayName or "Unknown"
            if #displayName > 0 then
                displayName = string.upper(string.sub(displayName, 1, 1)) .. string.sub(displayName, 2)
            end
            
            imgui.AlignTextToFramePadding()
            imgui.Text(displayName)
            
            imgui.SameLine()
            if imgui.Button("Unblock") then
                if callbacks.onUnblockPlayer then
                    callbacks.onUnblockPlayer(entry.accountId)
                end
            end
            
            imgui.PopID()
        end
        
        imgui.EndChild()
    end
end

return M

