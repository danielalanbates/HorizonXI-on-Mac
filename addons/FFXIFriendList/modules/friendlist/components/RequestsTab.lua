local imgui = require('imgui')
local utils = require('modules.friendlist.components.helpers.utils')

local M = {}

local function renderIncomingSection(dataModule, callbacks)
    imgui.Text("Incoming Requests")
    
    local _, availHeight = imgui.GetContentRegionAvail()
    local childHeight = (availHeight or 200) * 0.5 - 30
    imgui.BeginChild("##incoming_requests_child", {0, childHeight}, true)
    
    local incomingRequests = dataModule.GetIncomingRequests()
    
    if #incomingRequests == 0 then
        imgui.TextDisabled("No incoming requests.")
    else
        for i, request in ipairs(incomingRequests) do
            imgui.PushID("incoming_" .. i)
            
            imgui.AlignTextToFramePadding()
            imgui.Text(utils.capitalizeName(request.name or "Unknown"))
            
            imgui.SameLine()
            if imgui.Button("Accept") then
                if callbacks.onAcceptRequest then
                    callbacks.onAcceptRequest(request.id or request.name)
                end
            end
            
            imgui.SameLine()
            if imgui.Button("Deny") then
                if callbacks.onRejectRequest then
                    callbacks.onRejectRequest(request.id or request.name)
                end
            end
            
            imgui.SameLine()
            imgui.PushStyleColor(ImGuiCol_Button, {0.6, 0.2, 0.2, 1.0})
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.7, 0.3, 0.3, 1.0})
            imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.5, 0.1, 0.1, 1.0})
            if imgui.Button("Block") then
                if callbacks.onBlockPlayer then
                    callbacks.onBlockPlayer(request.accountId, request.name, request.id)
                end
            end
            imgui.PopStyleColor(3)
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Block this player from sending you friend requests")
            end
            
            imgui.PopID()
        end
    end
    
    imgui.EndChild()
end

local function renderOutgoingSection(dataModule, callbacks)
    imgui.Text("Outgoing Requests")
    
    imgui.BeginChild("##outgoing_requests_child", {0, 0}, true)
    
    local outgoingRequests = dataModule.GetOutgoingRequests()
    
    if #outgoingRequests == 0 then
        imgui.TextDisabled("No outgoing requests.")
    else
        for i, request in ipairs(outgoingRequests) do
            imgui.PushID("outgoing_" .. i)
            
            imgui.AlignTextToFramePadding()
            imgui.Text(utils.capitalizeName(request.name or "Unknown"))
            
            imgui.SameLine()
            if imgui.Button("Cancel") then
                if callbacks.onCancelRequest then
                    callbacks.onCancelRequest(request.id or request.name)
                end
            end
            
            imgui.PopID()
        end
    end
    
    imgui.EndChild()
end

function M.Render(state, dataModule, callbacks)
    renderIncomingSection(dataModule, callbacks)
    imgui.Spacing()
    renderOutgoingSection(dataModule, callbacks)
end

return M

