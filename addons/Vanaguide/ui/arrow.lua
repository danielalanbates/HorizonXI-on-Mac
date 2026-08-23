-- Vanaguide :: ui/arrow.lua
-- The arrow.  It points at whatever the router recommends and says how far away it is.
--
-- It is drawn with plain lines on ImGui's foreground draw list rather than a texture,
-- because that is the one drawing primitive every Ashita build on every renderer this
-- project supports has been seen to do (the Mac port runs the client through DXVK, where
-- fancier paths are not guaranteed).  Everything below is guarded: if a call is missing,
-- the arrow quietly stops drawing instead of throwing once per frame.
--
-- Copyright (c) 2026 Bates LLC.  All rights reserved.

local A = {
    screen = { w = 1280, h = 720 },
    calibration = 1,     -- see docs/ARROW.md: +1 or -1, whichever makes it point right
    offset = 0,          -- radians added to the bearing, for the same reason
}

local COL_NEAR  = 0xFF33DD33
local COL_MID   = 0xFF33DDDD
local COL_FAR   = 0xFF3399FF
local COL_SHELL = 0x88000000

local function colour_for(distance)
    if distance == nil then return COL_FAR end
    if distance <= 15 then return COL_NEAR end
    if distance <= 60 then return COL_MID end
    return COL_FAR
end

local function rotate(cx, cy, x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return cx + x * c - y * s, cy + x * s + y * c
end

--- Draw the arrow.  `bearing` is radians relative to the way the player faces, 0 = ahead.
--- Returns false when it could not draw, so the caller can stop asking.
function A.draw(bearing, distance, label, sub)
    local imgui = _G.imgui
    if imgui == nil or imgui.GetForegroundDrawList == nil then return false end

    local ok = pcall(function()
        local dl = imgui.GetForegroundDrawList()
        local cx, cy = A.pos_x or (A.screen.w / 2), A.pos_y or (A.screen.h * 0.28)

        -- Screen angle.  Zero bearing draws straight up.  The screen's y grows *downward*,
        -- so a positive (leftward) bearing has to become a negative screen rotation or the
        -- arrow comes out mirrored — verified by tools/render_arrow.lua.
        local a = -(bearing or 0) * A.calibration + A.offset
        local colour = colour_for(distance)

        local tipx, tipy = rotate(cx, cy, 0, -34, a)
        local lx, ly     = rotate(cx, cy, -20, 16, a)
        local rx, ry     = rotate(cx, cy, 20, 16, a)
        local bx, by     = rotate(cx, cy, 0, 4, a)

        dl:AddLine({ tipx, tipy }, { lx, ly }, COL_SHELL, 6)
        dl:AddLine({ tipx, tipy }, { rx, ry }, COL_SHELL, 6)
        dl:AddLine({ lx, ly }, { bx, by }, COL_SHELL, 6)
        dl:AddLine({ rx, ry }, { bx, by }, COL_SHELL, 6)

        dl:AddLine({ tipx, tipy }, { lx, ly }, colour, 3)
        dl:AddLine({ tipx, tipy }, { rx, ry }, colour, 3)
        dl:AddLine({ lx, ly }, { bx, by }, colour, 3)
        dl:AddLine({ rx, ry }, { bx, by }, colour, 3)

        if dl.AddText ~= nil then
            if label ~= nil then dl:AddText({ cx - 60, cy + 26 }, colour, label) end
            if sub ~= nil then dl:AddText({ cx - 60, cy + 42 }, 0xFFCCCCCC, sub) end
        end
    end)
    return ok
end

--- Remember the viewport so the arrow sits in the same place at any resolution.
function A.set_viewport(w, h)
    if w ~= nil and w > 0 then A.screen.w = w end
    if h ~= nil and h > 0 then A.screen.h = h end
    A.pos_x = A.rel_x and (A.rel_x * A.screen.w) or (A.screen.w / 2)
    A.pos_y = A.rel_y and (A.rel_y * A.screen.h) or (A.screen.h * 0.28)
end

return A
