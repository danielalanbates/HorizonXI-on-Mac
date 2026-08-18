local tagcore = require("core.tagcore")

local M = {}

local UNTAGGED_KEY = "__untagged__"
M.UNTAGGED_DISPLAY = "General"

function M.isOnlineish(friend)
    if not friend then
        return false
    end
    local isOnline = friend.isOnline
    if isOnline then
        return true
    end
    local presence = friend.presence or {}
    local status = presence.status or friend.status
    if type(status) == "string" then
        local lower = string.lower(status)
        if lower == "online" or lower == "away" then
            return true
        end
    end
    return false
end

function M.groupFriendsByTag(friends, tagOrder, getFriendTag)
    local groups = {}
    local groupMap = {}
    
    for _, tagName in ipairs(tagOrder) do
        local normalized = tagcore.normalizeTag(tagName)
        if normalized then
            local group = { tag = normalized, displayTag = tagName, friends = {} }
            table.insert(groups, group)
            groupMap[string.lower(normalized)] = group
        end
    end
    
    local untaggedGroup = { tag = UNTAGGED_KEY, displayTag = M.UNTAGGED_DISPLAY, friends = {} }
    
    for _, friend in ipairs(friends or {}) do
        local friendTag = getFriendTag(friend)
        local normalized = tagcore.normalizeTag(friendTag)
        
        if normalized then
            local group = groupMap[string.lower(normalized)]
            if group then
                table.insert(group.friends, friend)
            else
                table.insert(untaggedGroup.friends, friend)
            end
        else
            table.insert(untaggedGroup.friends, friend)
        end
    end
    
    if #untaggedGroup.friends > 0 then
        table.insert(groups, untaggedGroup)
    end
    
    return groups
end

local function compareStringsIgnoreCase(a, b)
    local lowerA = string.lower(a or "")
    local lowerB = string.lower(b or "")
    if lowerA < lowerB then
        return -1
    elseif lowerA > lowerB then
        return 1
    end
    return 0
end

local function getFriendName(friend)
    return friend.name or friend.friendName or ""
end

local function getFriendLastSeen(friend)
    local presence = friend.presence or {}
    return presence.lastSeenAt or friend.lastSeenAt or 0
end

function M.sortWithinGroup(friends, sortMode, sortDirection)
    if not friends or #friends == 0 then
        return friends
    end
    
    local ascending = (sortDirection ~= "desc")
    
    table.sort(friends, function(a, b)
        local result = 0
        
        if sortMode == "status" then
            local aOnline = M.isOnlineish(a)
            local bOnline = M.isOnlineish(b)
            if aOnline and not bOnline then
                result = -1
            elseif not aOnline and bOnline then
                result = 1
            else
                result = compareStringsIgnoreCase(getFriendName(a), getFriendName(b))
            end
        elseif sortMode == "lastSeen" then
            local aTime = getFriendLastSeen(a)
            local bTime = getFriendLastSeen(b)
            if aTime > bTime then
                result = -1
            elseif aTime < bTime then
                result = 1
            else
                result = compareStringsIgnoreCase(getFriendName(a), getFriendName(b))
            end
        else
            result = compareStringsIgnoreCase(getFriendName(a), getFriendName(b))
        end
        
        if not ascending then
            result = -result
        end
        
        return result < 0
    end)
    
    return friends
end

function M.sortAllGroups(groups, sortMode, sortDirection)
    for _, group in ipairs(groups) do
        M.sortWithinGroup(group.friends, sortMode, sortDirection)
    end
    return groups
end

return M

