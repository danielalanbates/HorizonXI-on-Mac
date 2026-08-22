-- Vanaguide :: core/progress.lua
-- Which step you are on, and the record of what you have finished — per character, because
-- two characters on one account are two different playthroughs.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local C = require('core.conditions')

local P = {
    guide = nil,        -- the active guide table
    index = 1,          -- 1-based step index
    skipped = {},       -- [step index] = true
    checked = {},       -- [step index] = true, ticked by hand
}

--- Start (or resume) a guide.  Resuming keeps whatever was already recorded for it.
function P.set_guide(guide, saved)
    P.guide = guide
    P.index = (saved and saved.index) or 1
    P.skipped = (saved and saved.skipped) or {}
    P.checked = (saved and saved.checked) or {}
    return P.guide
end

function P.step(i)
    if P.guide == nil then return nil end
    return P.guide.steps[i or P.index]
end

function P.count()
    if P.guide == nil then return 0 end
    return #P.guide.steps
end

local function satisfied(i, w)
    if P.checked[i] or P.skipped[i] then return true end
    local step = P.guide.steps[i]
    if step == nil then return true end
    if step.fixed and not P.checked[i] then return false end
    return C.done(step, w)
end

--- Move the cursor past everything that is already true.  Returns the number of steps
--- crossed, so the caller can announce "3 steps completed" rather than silently jumping.
function P.advance(w)
    if P.guide == nil then return 0 end
    w = w or C.world()
    local moved = 0
    while P.index <= #P.guide.steps and satisfied(P.index, w) do
        P.index = P.index + 1
        moved = moved + 1
    end
    return moved
end

--- The next few steps that still need doing, for the guide window.
function P.upcoming(n, w)
    local out = {}
    if P.guide == nil then return out end
    w = w or C.world()
    local i = P.index
    while i <= #P.guide.steps and #out < (n or 6) do
        if not satisfied(i, w) then out[#out + 1] = P.guide.steps[i] end
        i = i + 1
    end
    return out
end

function P.check(i)  P.checked[i or P.index] = true end
function P.uncheck(i) P.checked[i or P.index] = nil end
function P.skip(i)   P.skipped[i or P.index] = true end

--- Step back to the last thing that is not finished, undoing a hand tick if that is what
--- put the cursor where it is.
function P.back()
    if P.guide == nil then return end
    local i = P.index - 1
    while i >= 1 do
        if P.checked[i] then P.checked[i] = nil; P.index = i; return end
        if P.skipped[i] then P.skipped[i] = nil; P.index = i; return end
        i = i - 1
    end
    P.index = math.max(1, P.index - 1)
end

function P.complete()
    return P.guide ~= nil and P.index > #P.guide.steps
end

function P.save_state()
    return { index = P.index, skipped = P.skipped, checked = P.checked }
end

return P
