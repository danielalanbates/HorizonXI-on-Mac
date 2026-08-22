local imgui = require('imgui')
local utils = require('modules.friendlist.components.helpers.utils')

local M = {}

function M.Render(friend, state, callbacks)
    if friend.friendedAs and friend.friendedAs ~= "" and friend.friendedAs ~= friend.name then
        imgui.Text("Friended As: " .. utils.capitalizeName(friend.friendedAs))
        imgui.Separator()
    end
    
    if imgui.MenuItem("View Details") then
        state.selectedFriendForDetails = friend
    end
    
    if imgui.MenuItem("Send Tell") then
        if callbacks.onSendTell then
            callbacks.onSendTell(friend.name)
        end
    end
    
    imgui.Separator()
    
    if imgui.MenuItem("Remove Friend") then
        if callbacks.onRemoveFriend then
            callbacks.onRemoveFriend(friend.name)
        end
    end
    
    imgui.Separator()
    
    -- Mute notifications toggle
    local app = _G.FFXIFriendListApp
    local isMuted = false
    if app and app.features and app.features.preferences and friend.friendAccountId then
        isMuted = app.features.preferences:isFriendMuted(friend.friendAccountId)
    end
    
    if imgui.MenuItem("Mute Notifications", nil, isMuted) then
        if callbacks.onToggleMuteFriend then
            callbacks.onToggleMuteFriend(friend.friendAccountId)
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(isMuted and "Unmute notifications for this friend" or "Mute notifications for this friend")
    end
    
    imgui.Separator()
    
    -- Block & Remove Friend (shows persistent modal for confirmation)
    if imgui.MenuItem("Block & Remove Friend") then
        state.confirmBlockAndRemove = {
            accountId = friend.friendAccountId,
            name = friend.name
        }
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Block this player and remove them from your friends list")
    end
end

return M
