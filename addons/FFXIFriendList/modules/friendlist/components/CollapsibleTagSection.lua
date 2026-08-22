local imgui = require('imgui')
local tagcore = require('core.tagcore')
local taggrouper = require('core.taggrouper')
local FriendsTable = require('modules.friendlist.components.FriendsTable')

local M = {}

function M.Render(tagGroup, state, callbacks, renderFriendsTable, idSuffix, overlayEnabled, disableInteraction)
    if not tagGroup then
        return
    end
    
    idSuffix = idSuffix or ""
    overlayEnabled = overlayEnabled or false
    disableInteraction = disableInteraction or false
    
    local tag = tagGroup.tag
    local displayTag = tagGroup.displayTag or tag
    local friends = tagGroup.friends or {}
    local count = #friends
    
    local isUntagged = (tag == "__untagged__")
    local capitalizedTag = isUntagged and displayTag or tagcore.capitalizeTag(displayTag)
    local headerLabel = capitalizedTag .. " (" .. count .. ")"
    
    local app = _G.FFXIFriendListApp
    local tagsFeature = app and app.features and app.features.tags
    local isCollapsed = tagsFeature and tagsFeature:isCollapsed(tag .. idSuffix)
    
    local flags = 0
    if not isCollapsed then
        flags = ImGuiTreeNodeFlags_DefaultOpen
    end
    
    if disableInteraction then
        imgui.SetNextItemOpen(not isCollapsed, ImGuiCond_Always)
    end
    
    local tagHeaderBgEnabled = false
    if overlayEnabled and gConfig and gConfig.quickOnlineSettings then
        tagHeaderBgEnabled = gConfig.quickOnlineSettings.compact_overlay_tag_header_bg or false
    end
    
    if overlayEnabled and not tagHeaderBgEnabled then
        imgui.PushStyleColor(ImGuiCol_Header, {0.0, 0.0, 0.0, 0.0})
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0.0, 0.0, 0.0, 0.0})
        imgui.PushStyleColor(ImGuiCol_HeaderActive, {0.0, 0.0, 0.0, 0.0})
    end
    
    local dragState = FriendsTable.getDragState()
    
    local headerOpen = imgui.CollapsingHeader(headerLabel .. "##tag_" .. tag .. idSuffix, flags)
    
    if overlayEnabled and not tagHeaderBgEnabled then
        imgui.PopStyleColor(3)
    end
    
    if overlayEnabled or disableInteraction then
        headerOpen = not isCollapsed
    end
    
    local hoverFlags = ImGuiHoveredFlags_AllowWhenBlockedByActiveItem
    if not overlayEnabled and not disableInteraction and dragState.isDragging and imgui.IsItemHovered(hoverFlags) then
        if isUntagged then
            FriendsTable.setHoveredTag("__clear__")
        else
            FriendsTable.setHoveredTag(tag)
        end
    end
    
    local wasOpen = not isCollapsed
    local nowOpen = headerOpen
    if not overlayEnabled and not disableInteraction and wasOpen ~= nowOpen and tagsFeature then
        tagsFeature:setCollapsed(tag .. idSuffix, not nowOpen)
    end
    
    if headerOpen then
        if count > 0 then
            imgui.BeginGroup()
            
            if renderFriendsTable then
                renderFriendsTable(friends, state, callbacks, tag)
            end
            
            imgui.EndGroup()
            
            if dragState.isDragging and imgui.IsItemHovered(hoverFlags) then
                if isUntagged then
                    FriendsTable.setHoveredTag("__clear__")
                else
                    FriendsTable.setHoveredTag(tag)
                end
            end
        else
            imgui.TextDisabled("  No friends in this group")
        end
    end
end

function M.RenderAllSections(groups, state, callbacks, renderFriendsTable, idSuffix, overlayEnabled, disableInteraction, hideEmpty)
    overlayEnabled = overlayEnabled or false
    disableInteraction = disableInteraction or false
    hideEmpty = hideEmpty or false
    for _, tagGroup in ipairs(groups or {}) do
        local friends = tagGroup.friends or {}
        if not hideEmpty or #friends > 0 then
            M.Render(tagGroup, state, callbacks, renderFriendsTable, idSuffix, overlayEnabled, disableInteraction)
            imgui.Spacing()
        end
    end
    
    if not overlayEnabled and not disableInteraction then
        local friendKey, targetTag = FriendsTable.consumePendingDrop()
        if friendKey then
            if targetTag == "__clear__" then
                targetTag = nil
            end
            if callbacks and callbacks.onQueueRetag then
                callbacks.onQueueRetag(friendKey, targetTag)
            end
        end
    end
end

return M
