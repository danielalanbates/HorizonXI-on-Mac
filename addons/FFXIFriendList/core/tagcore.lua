local M = {}

function M.normalizeTag(tag)
    if type(tag) ~= "string" then
        return nil
    end
    local trimmed = tag:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

function M.tagsEqual(a, b)
    local normA = M.normalizeTag(a)
    local normB = M.normalizeTag(b)
    if normA == nil and normB == nil then
        return true
    end
    if normA == nil or normB == nil then
        return false
    end
    return string.lower(normA) == string.lower(normB)
end

function M.isValidTag(tag)
    return M.normalizeTag(tag) ~= nil
end

function M.isUntagged(tag)
    return not M.isValidTag(tag)
end

function M.getFriendKey(friend)
    if not friend then
        return nil
    end
    if friend.friendAccountId and friend.friendAccountId ~= "" then
        return tostring(friend.friendAccountId)
    end
    local name = friend.name or friend.friendName or ""
    if name == "" then
        return nil
    end
    return string.lower(name)
end

function M.findTagIndex(tagOrder, tag)
    local normTag = M.normalizeTag(tag)
    if not normTag then
        return nil
    end
    for i, t in ipairs(tagOrder) do
        if M.tagsEqual(t, normTag) then
            return i
        end
    end
    return nil
end

function M.tagExistsInOrder(tagOrder, tag)
    return M.findTagIndex(tagOrder, tag) ~= nil
end

function M.findExistingTag(tagOrder, tag)
    local normTag = M.normalizeTag(tag)
    if not normTag then
        return nil
    end
    for _, t in ipairs(tagOrder) do
        if M.tagsEqual(t, normTag) then
            return t
        end
    end
    return nil
end

function M.capitalizeTag(tag)
    if type(tag) ~= "string" or tag == "" then
        return tag
    end
    return tag:gsub("(%a)([%w]*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

return M

