local imgui = require('imgui')
local tagcore = require('core.tagcore')

local M = {}

local inputState = {
    newTagInput = {""}
}

function M.Render(currentTag, friendKey, callbacks)
    local app = _G.FFXIFriendListApp
    local tagsFeature = app and app.features and app.features.tags
    
    if not tagsFeature then
        imgui.TextDisabled("Tags not available")
        return
    end
    
    local tagOrder = tagsFeature:getAllTags() or {}
    local displayTag = currentTag and tagcore.capitalizeTag(currentTag) or "General"
    
    imgui.Text("Tag:")
    imgui.SameLine()
    
    imgui.PushItemWidth(150)
    if imgui.BeginCombo("##tag_select", displayTag) then
        if imgui.Selectable("General##tag_general", currentTag == nil or currentTag == "") then
            if callbacks and callbacks.onTagChanged then
                callbacks.onTagChanged(friendKey, nil)
            end
        end
        
        imgui.Separator()
        
        for _, tag in ipairs(tagOrder) do
            local isSelected = tagcore.tagsEqual(tag, currentTag)
            if imgui.Selectable(tagcore.capitalizeTag(tag) .. "##tag_" .. tag, isSelected) then
                if callbacks and callbacks.onTagChanged then
                    callbacks.onTagChanged(friendKey, tag)
                end
            end
        end
        
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    
    imgui.SameLine()
    imgui.Text("or")
    imgui.SameLine()
    
    imgui.PushItemWidth(100)
    imgui.InputText("##new_tag_input", inputState.newTagInput, 32)
    imgui.PopItemWidth()
    
    imgui.SameLine()
    if imgui.Button("Create##create_tag") then
        local newTag = tagcore.normalizeTag(inputState.newTagInput[1])
        if newTag then
            tagsFeature:createTag(newTag)
            if callbacks and callbacks.onTagChanged then
                callbacks.onTagChanged(friendKey, newTag)
            end
            inputState.newTagInput[1] = ""
        end
    end
end

function M.RenderCompact(currentTag, friendKey, callbacks, uniqueId)
    local app = _G.FFXIFriendListApp
    local tagsFeature = app and app.features and app.features.tags
    
    if not tagsFeature then
        return
    end
    
    local tagOrder = tagsFeature:getAllTags() or {}
    local displayTag = currentTag and tagcore.capitalizeTag(currentTag) or "General"
    local comboId = "##tag_select_" .. (uniqueId or "default")
    
    imgui.PushItemWidth(120)
    if imgui.BeginCombo(comboId, displayTag) then
        if imgui.Selectable("General", currentTag == nil or currentTag == "") then
            if callbacks and callbacks.onTagChanged then
                callbacks.onTagChanged(friendKey, nil)
            end
        end
        
        for _, tag in ipairs(tagOrder) do
            local isSelected = tagcore.tagsEqual(tag, currentTag)
            if imgui.Selectable(tagcore.capitalizeTag(tag), isSelected) then
                if callbacks and callbacks.onTagChanged then
                    callbacks.onTagChanged(friendKey, tag)
                end
            end
        end
        
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
end

return M

