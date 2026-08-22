local imgui = require('imgui')

local M = {}

function M.Render(state, dataModule, callbacks)
    M.RenderWelcomeSection()
    imgui.Spacing()
    M.RenderAccountInfoSection(dataModule)
    imgui.Spacing()
    M.RenderCommandsSection()
    imgui.Spacing()
    M.RenderFriendRequestsSection()
    imgui.Spacing()
    M.RenderNotificationsSection()
    imgui.Spacing()
    M.RenderPresenceStatusSection()
    imgui.Spacing()
    M.RenderFriendManagementSection()
    imgui.Spacing()
    M.RenderSettingsSection()
end

function M.RenderWelcomeSection()
    imgui.TextColored({0.4, 0.8, 1.0, 1.0}, "Welcome to FFXIFriendList!")
    imgui.Spacing()
    imgui.TextWrapped("This addon lets you manage a cross-server friend list for Final Fantasy XI. " ..
        "Stay connected with friends across different private servers, see when they're online, and send messages.")
end

function M.RenderAccountInfoSection(dataModule)
    local isExpanded = imgui.CollapsingHeader("Your Characters")
    
    if isExpanded then
        imgui.Indent()
        
        local app = _G.FFXIFriendListApp
        local currentCharName = nil
        local characters = dataModule and dataModule.GetCharacters and dataModule:GetCharacters() or {}
        
        -- Get current character name from connection
        if app and app.features and app.features.connection then
            currentCharName = app.features.connection:getCharacterName()
        end
        
        -- Display characters from data module
        if #characters > 0 then
            for _, char in ipairs(characters) do
                local displayName = char.characterName:sub(1, 1):upper() .. char.characterName:sub(2):lower()
                
                if char.isActive then
                    imgui.TextColored({0.0, 1.0, 0.0, 1.0}, "* " .. displayName)
                    imgui.SameLine()
                    imgui.TextDisabled("(current)")
                else
                    imgui.Text("  " .. displayName)
                end
            end
            imgui.Spacing()
            imgui.TextDisabled("You are viewing the friend list for this character.")
        elseif currentCharName and currentCharName ~= "" then
            -- Show at least the current character if we can't fetch the full list
            local displayName = currentCharName:sub(1, 1):upper() .. currentCharName:sub(2):lower()
            imgui.TextColored({0.0, 1.0, 0.0, 1.0}, "* " .. displayName)
            imgui.SameLine()
            imgui.TextDisabled("(current)")
            imgui.Spacing()
            imgui.TextDisabled("You are viewing the friend list for this character.")
        else
            imgui.TextDisabled("Not connected")
        end
        
        imgui.Unindent()
    end
end

function M.RenderCommandsSection()
    if imgui.CollapsingHeader("Commands", ImGuiTreeNodeFlags_DefaultOpen) then
        imgui.Indent()
        
        imgui.TextColored({0.9, 0.9, 0.6, 1.0}, "/fl")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.Text("Open the main Friend List window")  
       
        imgui.TextColored({0.9, 0.9, 0.6, 1.0}, "/flist")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.Text("Open the Compact Friend List window")

        imgui.TextColored({0.9, 0.9, 0.6, 1.0}, "/befriend <name> <tag-optional>")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.Text("Sends a friend request to the specified player with an optional tag")

        imgui.Unindent()
    end
end

function M.RenderFriendRequestsSection()
    if imgui.CollapsingHeader("Friend Requests", ImGuiTreeNodeFlags_DefaultOpen) then
        imgui.Indent()
        
        imgui.TextWrapped("To add a friend:")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Type the character name in the \"Add Friend\" box")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Optionally add a tag to organize them (e.g., \"Linkshell\", \"Static\")")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Click \"Add Friend\" to send them a friend request")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("You can also use /befriend <name> <tag> in chat")
        
        imgui.Spacing()
        
        imgui.TextWrapped("To accept incoming requests:")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Go to the \"Requests\" tab")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Click \"Accept\" next to any pending request")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Click \"Decline\" to reject a request")
        
        imgui.Spacing()
        
        imgui.TextDisabled("Note: Both players must have the addon installed on the same server.")
        
        imgui.Unindent()
    end
end

function M.RenderNotificationsSection()
    if imgui.CollapsingHeader("Notifications") then
        imgui.Indent()
        
        imgui.TextWrapped("Get notified when friends come online:")
        imgui.Spacing()
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Enable notification sounds in the Notifications tab")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Adjust volume and duration to your preference")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Test sounds with the \"Test Notification\" buttons")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Mute notifications for specific friends using the context menu (right-click)")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Hold Shift and drag notifications to reposition them on screen")
        
        imgui.Spacing()
        
        imgui.TextDisabled("Tip: Enable \"Show test notification\" to easily adjust position.")
        
        imgui.Unindent()
    end
end

function M.RenderPresenceStatusSection()
    if imgui.CollapsingHeader("Presence Status", ImGuiTreeNodeFlags_DefaultOpen) then
        imgui.Indent()
        
        imgui.TextWrapped("Control how you appear to friends in the Privacy tab:")
        imgui.Spacing()
        
        imgui.TextColored({0.0, 1.0, 0.0, 1.0}, "Online")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("You appear online with full status visible")
        
        imgui.TextColored({1.0, 0.7, 0.2, 1.0}, "Away")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("You appear online but marked as Away")
        
        imgui.TextColored({0.5, 0.5, 0.5, 1.0}, "Invisible")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("You appear offline to all friends")
        
        imgui.Unindent()
    end
end

function M.RenderFriendManagementSection()
    if imgui.CollapsingHeader("Managing Friends") then
        imgui.Indent()
        
        imgui.TextWrapped("Right-click on any friend to:")
        imgui.Spacing()
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("View detailed info and add notes")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Edit tags to organize them into groups")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Mute/unmute their notifications")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Remove from friends list")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Block & Remove to prevent future contact")
        
        imgui.Spacing()
        
        imgui.TextWrapped("Notes:")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Add personal notes to remember details about friends")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Notes are private and only visible to you")
        
        imgui.Spacing()
        
        imgui.TextWrapped("Tags:")
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Use tags to group friends (e.g., \"Linkshell\", \"Static\", \"IRL\")")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Filter by tag in the Tags tab")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Friends can have multiple tags")
        
        imgui.Unindent()
    end
end

function M.RenderSettingsSection()
    if imgui.CollapsingHeader("Settings & Tips") then
        imgui.Indent()
        
        imgui.TextWrapped("Useful settings can be found in these tabs:")
        imgui.Spacing()
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "General")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("Window columns, hover tooltips, and Lock All Windows toggle")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Privacy")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("Presence status, location sharing, alt visibility")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Tags")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("Organize friends into groups")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Notifications")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("Configure friend online alerts and sounds")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Controls")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("Keyboard and controller bindings")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextColored({0.7, 0.9, 1.0, 1.0}, "Themes")
        imgui.SameLine()
        imgui.TextDisabled(" - ")
        imgui.SameLine()
        imgui.TextWrapped("Customize the look and feel")
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        
        imgui.TextWrapped("Quick Tips:")
        imgui.Spacing()
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Use the Compact Friend List (/flist) for a minimal view")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Enable \"Lock All Windows\" to prevent accidental moves")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Go Invisible if you want to play without appearing online")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Check the Server tab if you have connection issues")
        
        imgui.Bullet()
        imgui.SameLine()
        imgui.TextWrapped("Use the Diagnostics tab to test your connection")
        
        imgui.Unindent()
    end
end

return M

