-- Vanagear :: which sets apply to what is happening, and in what order.
-- Copyright (c) 2026 Daniel Bates / Bates LLC. All rights reserved.
--
-- Everything here is pure: an event plus the player's mode state in, an ordered
-- list of set names out. Sets are merged generic-first, so a specific set only
-- has to name the slots it actually changes.

local M = {};

local function push(list, name)
    if name == nil then return; end
    name = tostring(name):lower():gsub('%s+', ' ');
    if #name == 0 then return; end
    list[#list + 1] = name;
end

-- The set that holds while nothing is being cast or swung.
local function baseChain(ctx)
    local list = {};
    push(list, 'idle');
    if ctx.resting then push(list, 'resting'); end
    if ctx.engaged then push(list, 'tp'); end
    return list;
end
M.baseChain = baseChain;

-- Generic -> specific. The last name that exists wins each slot.
function M.chain(event, ctx)
    ctx = ctx or {};
    event = event or {};
    local kind = event.kind or 'base';
    local list = baseChain(ctx);

    local function layer(prefix)
        push(list, prefix);
        if event.skill then push(list, prefix .. '.' .. event.skill); end
        if event.name then push(list, prefix .. '.' .. event.name); end
    end

    if kind == 'base' then
        -- baseChain is the whole story.
    elseif kind == 'precast' then
        layer('precast');
    elseif kind == 'midcast' then
        layer('midcast');
    elseif kind == 'ws' then
        layer('ws');
    elseif kind == 'ja' then
        push(list, 'ja');
        if event.name then push(list, 'ja.' .. event.name); end
    elseif kind == 'preshot' then
        push(list, 'preshot');
    elseif kind == 'midshot' then
        push(list, 'midshot');
        if event.name then push(list, 'midshot.' .. event.name); end
    elseif kind == 'item' then
        push(list, 'item');
        if event.name then push(list, 'item.' .. event.name); end
    else
        layer(kind);
    end

    return list;
end

-- Every mode subset, smallest first, so "tp:acc:dt" beats "tp:acc" beats "tp".
local function modeSuffixes(active, order)
    local values = {};
    local names = {};
    if type(order) == 'table' and #order > 0 then
        for _, name in ipairs(order) do names[#names + 1] = name; end
    else
        for name in pairs(active or {}) do names[#names + 1] = name; end
        table.sort(names);
    end
    for _, name in ipairs(names) do
        local value = (active or {})[name];
        if type(value) == 'string' and #value > 0 and value ~= 'normal' then
            values[#values + 1] = value:lower();
        end
    end

    local subsets = { {} };
    for _, value in ipairs(values) do
        local grown = {};
        for _, subset in ipairs(subsets) do
            local copy = { table.unpack and table.unpack(subset) or unpack(subset) };
            copy[#copy + 1] = value;
            grown[#grown + 1] = copy;
        end
        for _, subset in ipairs(grown) do subsets[#subsets + 1] = subset; end
    end

    table.sort(subsets, function(a, b)
        if #a ~= #b then return #a < #b; end
        return table.concat(a, ':') < table.concat(b, ':');
    end);

    local out = {};
    for _, subset in ipairs(subsets) do
        out[#out + 1] = (#subset == 0) and '' or (':' .. table.concat(subset, ':'));
    end
    return out;
end
M.modeSuffixes = modeSuffixes;

-- The chain with mode variants folded in. This is what the engine walks.
function M.expand(event, ctx)
    ctx = ctx or {};
    local suffixes = modeSuffixes(ctx.active, ctx.modeOrder);
    local out = {};
    for _, name in ipairs(M.chain(event, ctx)) do
        for _, suffix in ipairs(suffixes) do
            out[#out + 1] = name .. suffix;
        end
    end
    return out;
end

return M;
