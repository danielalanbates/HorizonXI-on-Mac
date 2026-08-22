-- Vanaguide :: ui/window.lua
-- The guide window: what to do now, what is next, and one line about how to get there.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local U = require('core.util')
local G = require('core.guide')
local P = require('core.progress')
local R = require('routing.router')

local W = { open = { true }, picker = { false }, upcoming = 4 }

local VERB_LABEL = {
    accept = 'Accept', turnin = 'Turn in', complete = 'Do', kill = 'Kill', buy = 'Buy',
    talk = 'Talk', run = 'Go to', use = 'Use', travel = 'Travel', note = 'Note',
    level = 'Level',
}

-- Step text is a sentence, not a label, so it has to wrap: ImGui will happily draw it off
-- the edge of the window otherwise.  TextWrapped is used where it exists, and the coloured
-- lines set a wrap position around the plain coloured call, which has no wrapped variant.
local function wrapped(s)
    local imgui = _G.imgui
    if imgui.TextWrapped ~= nil then imgui.TextWrapped(s) else imgui.Text(s) end
end

local function text_colored(colour, s)
    local imgui = _G.imgui
    if imgui.TextColored == nil then return wrapped(s) end
    if imgui.PushTextWrapPos ~= nil then
        imgui.PushTextWrapPos(0)
        imgui.TextColored(colour, s)
        imgui.PopTextWrapPos()
    else
        imgui.TextColored(colour, s)
    end
end

--- One frame.  `w` is a world snapshot; `on_pick` is called with a guide name.
function W.draw(w, on_pick)
    local imgui = _G.imgui
    if imgui == nil or not W.open[1] then return end

    imgui.SetNextWindowSize({ 380, 260 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('Vanaguide', W.open) then
        local guide = P.guide
        if guide == nil then
            imgui.Text('No guide loaded.')
            if imgui.Button('Choose a guide') then W.picker[1] = true end
        else
            text_colored({ 1.0, 0.82, 0.2, 1.0 }, guide.name)
            imgui.SameLine()
            imgui.Text(('(%d/%d)'):format(math.min(P.index, P.count()), P.count()))

            local step = P.step()
            if step == nil then
                text_colored({ 0.4, 1.0, 0.4, 1.0 }, 'Guide complete.')
            else
                imgui.Separator()
                text_colored({ 0.9, 0.9, 1.0, 1.0 },
                    ('%s: %s'):format(VERB_LABEL[step.kind] or '?', step.text))
                if step.note ~= nil and step.note ~= '' then
                    text_colored({ 0.7, 0.7, 0.7, 1.0 }, step.note)
                end

                local rec = R.recommend(step, w)
                text_colored({ 0.55, 0.8, 1.0, 1.0 }, rec.text or '')
                if rec.mode == 'travel' and rec.hops ~= nil then
                    imgui.Text(('%d zones to %s'):format(rec.hops, U.zone_name(rec.destination)))
                end

                if imgui.Button('Done') then P.check() end
                imgui.SameLine()
                if imgui.Button('Skip') then P.skip() end
                imgui.SameLine()
                if imgui.Button('Back') then P.back() end
                imgui.SameLine()
                if imgui.Button('Guides') then W.picker[1] = true end

                imgui.Separator()
                imgui.Text('Next:')
                local next_steps = P.upcoming(W.upcoming + 1, w)
                for i = 2, #next_steps do
                    local s = next_steps[i]
                    wrapped((' %s %s'):format(VERB_LABEL[s.kind] or '-', s.text))
                end
            end
        end
    end
    imgui.End()

    if W.picker[1] then
        imgui.SetNextWindowSize({ 340, 240 }, ImGuiCond_FirstUseEver)
        if imgui.Begin('Vanaguide — guides', W.picker) then
            for _, g in ipairs(G.list()) do
                if imgui.Button(g.name) then
                    if on_pick ~= nil then on_pick(g.name) end
                    W.picker[1] = false
                end
                if g.levels ~= nil then
                    imgui.SameLine()
                    imgui.Text('levels ' .. g.levels)
                end
            end
        end
        imgui.End()
    end
end

function W.toggle() W.open[1] = not W.open[1] end

return W
