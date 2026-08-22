local imgui = require('imgui')
local tagcore = require('core.tagcore')

local M = {}

local managerState = {
    newTagInput = {""},
    confirmDeleteTag = nil
}

function M.Render(expanded)
    local app = _G.FFXIFriendListApp
    local tagsFeature = app and app.features and app.features.tags
    
    if not tagsFeature then
        imgui.TextDisabled("Tags not available")
        return
    end
    
    local tagOrder = tagsFeature:getAllTags() or {}
    
    imgui.Text("Create Tag:")
    imgui.SameLine()
    imgui.PushItemWidth(120)
    imgui.InputText("##new_tag_manager_input", managerState.newTagInput, 32)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("Add##add_tag_btn") then
        local newTag = tagcore.normalizeTag(managerState.newTagInput[1])
        if newTag then
            if tagsFeature:createTag(newTag) then
                tagsFeature:save()
            end
            managerState.newTagInput[1] = ""
        end
    end
    
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    
    if #tagOrder == 0 then
        imgui.TextDisabled("No tags created yet")
        return
    end
    
    imgui.Text("Tag Order:")
    imgui.SameLine()
    imgui.TextDisabled("(drag sections appear in this order)")
    
    imgui.BeginChild("##tag_list_child", {0, 150}, true)
    
    for i, tag in ipairs(tagOrder) do
        imgui.PushID("tag_row_" .. i)
        
        local canMoveUp = i > 1
        local canMoveDown = i < #tagOrder
        
        imgui.Text(tagcore.capitalizeTag(tag))
        
        if managerState.confirmDeleteTag == tag then
            imgui.SameLine(imgui.GetWindowWidth() - 130)
            imgui.PushStyleColor(ImGuiCol_Button, {0.8, 0.2, 0.2, 1.0})
            if imgui.SmallButton("Confirm") then
                tagsFeature:deleteTag(tag)
                tagsFeature:save()
                managerState.confirmDeleteTag = nil
            end
            imgui.PopStyleColor()
            imgui.SameLine()
            if imgui.SmallButton("Cancel") then
                managerState.confirmDeleteTag = nil
            end
        else
            imgui.SameLine(imgui.GetWindowWidth() - 75)
            if canMoveUp then
                if imgui.SmallButton("^##up") then
                    tagsFeature:moveTagUp(tag)
                    tagsFeature:save()
                end
            else
                imgui.Dummy({16, 0})
            end
            imgui.SameLine()
            
            if canMoveDown then
                if imgui.SmallButton("v##down") then
                    tagsFeature:moveTagDown(tag)
                    tagsFeature:save()
                end
            else
                imgui.Dummy({16, 0})
            end
            imgui.SameLine()
            
            if imgui.SmallButton("X##del") then
                managerState.confirmDeleteTag = tag
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Delete tag (friends will become Untagged)")
            end
        end
        
        imgui.PopID()
    end
    
    imgui.EndChild()
end

function M.RenderCompact()
    local app = _G.FFXIFriendListApp
    local tagsFeature = app and app.features and app.features.tags
    
    if not tagsFeature then
        return
    end
    
    local tagOrder = tagsFeature:getAllTags() or {}
    
    imgui.PushItemWidth(100)
    imgui.InputText("##quick_tag_input", managerState.newTagInput, 32)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.SmallButton("+##quick_add") then
        local newTag = tagcore.normalizeTag(managerState.newTagInput[1])
        if newTag then
            if tagsFeature:createTag(newTag) then
                tagsFeature:save()
            end
            managerState.newTagInput[1] = ""
        end
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip("Create new tag")
    end
end

return M

