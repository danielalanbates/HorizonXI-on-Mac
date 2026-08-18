local M = {}

local function toLower(s)
    if type(s) ~= "string" then return "" end
    return string.lower(s)
end

local function normalizeName(name)
    if type(name) ~= "string" then return "" end
    return string.lower(name)
end

M.Friend = {}
M.Friend.__index = M.Friend

function M.Friend.new(name, friendedAs)
    local self = setmetatable({}, M.Friend)
    self.name = type(name) == "string" and name or ""
    self.friendedAs = type(friendedAs) == "string" and friendedAs or ""
    self.linkedCharacters = {}
    -- Initialize presence fields to prevent 'function' type errors
    self.job = ""
    self.zone = ""
    self.nation = nil
    self.rank = nil
    self.isOnline = false
    self.isAway = false
    self.lastSeenAt = 0
    self.friendAccountId = nil
    self.realmId = nil
    return self
end

function M.Friend:__eq(other)
    return toLower(self.name) == toLower(other.name)
end

function M.Friend:matchesCharacter(characterName)
    local lowerName = toLower(self.name)
    local lowerChar = toLower(characterName)
    
    if lowerName == lowerChar then
        return true
    end
    
    for _, linked in ipairs(self.linkedCharacters) do
        if toLower(linked) == lowerChar then
            return true
        end
    end
    
    return false
end

function M.Friend:hasLinkedCharacters()
    return #self.linkedCharacters > 0
end

M.FriendStatus = {}
M.FriendStatus.__index = M.FriendStatus

function M.FriendStatus.new()
    local self = setmetatable({}, M.FriendStatus)
    self.characterName = ""
    self.displayName = ""
    self.isOnline = false
    self.isAway = false
    self.job = ""
    self.rank = ""
    self.nation = -1
    self.zone = ""
    self.lastSeenAt = 0
    self.showOnlineStatus = true
    self.isLinkedCharacter = false
    self.isOnAltCharacter = false
    self.altCharacterName = ""
    self.friendedAs = ""
    self.linkedCharacters = {}
    return self
end

function M.FriendStatus:__eq(other)
    return self.characterName == other.characterName and
           self.displayName == other.displayName and
           self.isOnline == other.isOnline and
           self.job == other.job and
           self.rank == other.rank and
           self.nation == other.nation and
           self.zone == other.zone and
           self.showOnlineStatus == other.showOnlineStatus and
           self.isLinkedCharacter == other.isLinkedCharacter and
           self.isOnAltCharacter == other.isOnAltCharacter and
           self.altCharacterName == other.altCharacterName and
           self.friendedAs == other.friendedAs and
           self:linkedCharactersEqual(other.linkedCharacters)
end

function M.FriendStatus:linkedCharactersEqual(other)
    if #self.linkedCharacters ~= #other then
        return false
    end
    for i, v in ipairs(self.linkedCharacters) do
        if v ~= other[i] then
            return false
        end
    end
    return true
end

function M.FriendStatus:hasStatusChanged(other)
    return self.characterName ~= other.characterName or
           self.displayName ~= other.displayName or
           self.isOnline ~= other.isOnline or
           self.job ~= other.job or
           self.rank ~= other.rank or
           self.nation ~= other.nation or
           self.zone ~= other.zone or
           self.showOnlineStatus ~= other.showOnlineStatus or
           self.isLinkedCharacter ~= other.isLinkedCharacter or
           self.isOnAltCharacter ~= other.isOnAltCharacter or
           self.altCharacterName ~= other.altCharacterName or
           self.friendedAs ~= other.friendedAs or
           not self:linkedCharactersEqual(other.linkedCharacters)
end

function M.FriendStatus:hasOnlineStatusChanged(other)
    return self.isOnline ~= other.isOnline
end

M.FriendList = {}
M.FriendList.__index = M.FriendList

function M.FriendList.new()
    local self = setmetatable({}, M.FriendList)
    self.friends = {}
    self.friendStatuses = {}
    return self
end

function M.FriendList:addFriend(friend)
    if type(friend) == "string" then
        friend = M.Friend.new(friend, friend)
    end
    
    local normalizedName = normalizeName(friend.name)
    
    if self:findFriendIndex(normalizedName) ~= #self.friends + 1 then
        return false
    end
    
    local newFriend = M.Friend.new(friend.name, friend.friendedAs)
    newFriend.name = normalizedName
    if newFriend.friendedAs == "" then
        newFriend.friendedAs = normalizedName
    else
        newFriend.friendedAs = normalizeName(newFriend.friendedAs)
    end
    newFriend.linkedCharacters = {}
    for _, linked in ipairs(friend.linkedCharacters or {}) do
        table.insert(newFriend.linkedCharacters, linked)
    end
    
    -- Copy additional fields from server data
    newFriend.friendAccountId = friend.friendAccountId
    newFriend.isOnline = friend.isOnline
    newFriend.lastSeenAt = friend.lastSeenAt
    newFriend.job = friend.job
    newFriend.zone = friend.zone
    newFriend.nation = friend.nation
    newFriend.rank = friend.rank
    newFriend.realmId = friend.realmId
    
    table.insert(self.friends, newFriend)
    return true
end

function M.FriendList:removeFriend(name)
    local normalizedName = normalizeName(name)
    local index = self:findFriendIndex(normalizedName)
    
    if index == #self.friends + 1 then
        return false
    end
    
    table.remove(self.friends, index)
    
    local statusIndex = self:findFriendStatusIndex(normalizedName)
    if statusIndex ~= #self.friendStatuses + 1 then
        table.remove(self.friendStatuses, statusIndex)
    end
    
    return true
end

function M.FriendList:updateFriend(friend)
    local normalizedName = normalizeName(friend.name)
    local index = self:findFriendIndex(normalizedName)
    
    if index == #self.friends + 1 then
        return false
    end
    
    local updatedFriend = M.Friend.new(friend.name, friend.friendedAs)
    updatedFriend.name = normalizedName
    if updatedFriend.friendedAs ~= "" then
        updatedFriend.friendedAs = normalizeName(updatedFriend.friendedAs)
    end
    updatedFriend.linkedCharacters = {}
    for _, linked in ipairs(friend.linkedCharacters or {}) do
        table.insert(updatedFriend.linkedCharacters, linked)
    end
    
    -- Copy additional fields from server data
    updatedFriend.friendAccountId = friend.friendAccountId
    updatedFriend.isOnline = friend.isOnline
    updatedFriend.lastSeenAt = friend.lastSeenAt
    updatedFriend.job = friend.job
    updatedFriend.zone = friend.zone
    updatedFriend.nation = friend.nation
    updatedFriend.rank = friend.rank
    
    self.friends[index] = updatedFriend
    return true
end

function M.FriendList:findFriend(name)
    local index = self:findFriendIndex(normalizeName(name))
    if index == #self.friends + 1 then
        return nil
    end
    return self.friends[index]
end

function M.FriendList:hasFriend(name)
    return self:findFriendIndex(normalizeName(name)) ~= #self.friends + 1
end

function M.FriendList:clear()
    self.friends = {}
    self.friendStatuses = {}
end

function M.FriendList:getFriendNames()
    local names = {}
    for _, f in ipairs(self.friends) do
        table.insert(names, f.name)
    end
    return names
end

function M.FriendList:updateFriendStatus(status)
    local normalizedName = normalizeName(status.characterName)
    local index = self:findFriendStatusIndex(normalizedName)
    
    local updatedStatus = M.FriendStatus.new()
    updatedStatus.characterName = normalizedName
    updatedStatus.displayName = status.displayName or ""
    updatedStatus.isOnline = status.isOnline or false
    updatedStatus.isAway = status.isAway or false
    updatedStatus.job = status.job or ""
    updatedStatus.rank = status.rank or ""
    updatedStatus.nation = status.nation or -1
    updatedStatus.zone = status.zone or ""
    updatedStatus.lastSeenAt = status.lastSeenAt or 0
    updatedStatus.showOnlineStatus = status.showOnlineStatus ~= false
    updatedStatus.isLinkedCharacter = status.isLinkedCharacter or false
    updatedStatus.isOnAltCharacter = status.isOnAltCharacter or false
    updatedStatus.altCharacterName = status.altCharacterName or ""
    updatedStatus.friendedAs = status.friendedAs or ""
    updatedStatus.linkedCharacters = {}
    for _, linked in ipairs(status.linkedCharacters or {}) do
        table.insert(updatedStatus.linkedCharacters, linked)
    end
    
    if index == #self.friendStatuses + 1 then
        table.insert(self.friendStatuses, updatedStatus)
    else
        self.friendStatuses[index] = updatedStatus
    end
end

function M.FriendList:getFriendStatus(name)
    local index = self:findFriendStatusIndex(normalizeName(name))
    if index == #self.friendStatuses + 1 then
        return nil
    end
    return self.friendStatuses[index]
end

function M.FriendList:size()
    return #self.friends
end

function M.FriendList:empty()
    return #self.friends == 0
end

function M.FriendList:getFriends()
    return self.friends
end

function M.FriendList:getFriendStatuses()
    return self.friendStatuses
end

function M.FriendList:findFriendIndex(name)
    local normalized = normalizeName(name)
    for i, f in ipairs(self.friends) do
        if normalizeName(f.name) == normalized then
            return i
        end
    end
    return #self.friends + 1
end

function M.FriendList:findFriendStatusIndex(name)
    local normalized = normalizeName(name)
    for i, s in ipairs(self.friendStatuses) do
        if normalizeName(s.characterName) == normalized then
            return i
        end
    end
    return #self.friendStatuses + 1
end

local function isFriendOnline(friendName, friendStatuses)
    local normalizedName = toLower(friendName)
    
    for _, status in ipairs(friendStatuses) do
        if toLower(status.characterName) == normalizedName then
            return status.isOnline and status.showOnlineStatus
        end
    end
    
    return false
end

local function compareStringsIgnoreCase(a, b)
    local lowerA = toLower(a)
    local lowerB = toLower(b)
    
    if lowerA < lowerB then
        return -1
    elseif lowerA > lowerB then
        return 1
    else
        return 0
    end
end

function M.sortFriendsByStatus(friendNames, friendStatuses)
    table.sort(friendNames, function(a, b)
        local aOnline = isFriendOnline(a, friendStatuses)
        local bOnline = isFriendOnline(b, friendStatuses)
        
        if aOnline ~= bOnline then
            return aOnline
        end
        
        return compareStringsIgnoreCase(a, b) < 0
    end)
end

function M.sortFriendsAlphabetically(friendNames)
    table.sort(friendNames, function(a, b)
        return compareStringsIgnoreCase(a, b) < 0
    end)
end

function M.sortFriendsByStatusObjects(friends, friendStatuses)
    table.sort(friends, function(a, b)
        local aOnline = isFriendOnline(a.name, friendStatuses)
        local bOnline = isFriendOnline(b.name, friendStatuses)
        
        if aOnline ~= bOnline then
            return aOnline
        end
        
        return compareStringsIgnoreCase(a.name, b.name) < 0
    end)
end

function M.sortFriendsAlphabeticallyObjects(friends)
    table.sort(friends, function(a, b)
        return compareStringsIgnoreCase(a.name, b.name) < 0
    end)
end

function M.filterByName(friends, searchTerm)
    if not searchTerm or searchTerm == "" then
        local result = {}
        for _, f in ipairs(friends) do
            table.insert(result, f)
        end
        return result
    end
    
    local lowerSearch = toLower(searchTerm)
    local result = {}
    
    for _, f in ipairs(friends) do
        local lowerName = toLower(f.name)
        if string.find(lowerName, lowerSearch, 1, true) then
            table.insert(result, f)
        end
    end
    
    return result
end

function M.filterByOnlineStatus(friendNames, friendStatuses, onlineOnly)
    local result = {}
    
    for _, name in ipairs(friendNames) do
        local normalizedName = toLower(name)
        
        local isOnline = false
        for _, status in ipairs(friendStatuses) do
            if toLower(status.characterName) == normalizedName then
                isOnline = status.isOnline and status.showOnlineStatus
                break
            end
        end
        
        if onlineOnly == isOnline then
            table.insert(result, name)
        end
    end
    
    return result
end

function M.filter(friends, predicate)
    local result = {}
    for _, f in ipairs(friends) do
        if predicate(f) then
            table.insert(result, f)
        end
    end
    return result
end

function M.filterStatuses(friendStatuses, predicate)
    local result = {}
    for _, status in ipairs(friendStatuses) do
        if predicate(status) then
            table.insert(result, status)
        end
    end
    return result
end

function M.filterOnline(friendNames, friendStatuses)
    return M.filterByOnlineStatus(friendNames, friendStatuses, true)
end

function M.filterOffline(friendNames, friendStatuses)
    return M.filterByOnlineStatus(friendNames, friendStatuses, false)
end

local function containsName(names, name)
    local normalized = normalizeName(name)
    for _, n in ipairs(names) do
        if normalizeName(n) == normalized then
            return true
        end
    end
    return false
end

M.FriendListDiff = {}
M.FriendListDiff.__index = M.FriendListDiff

function M.FriendListDiff.new()
    local self = setmetatable({}, M.FriendListDiff)
    self.addedFriends = {}
    self.removedFriends = {}
    self.statusChangedFriends = {}
    return self
end

function M.FriendListDiff:hasChanges()
    return #self.addedFriends > 0 or
           #self.removedFriends > 0 or
           #self.statusChangedFriends > 0
end

function M.diff(oldFriends, newFriends)
    local diff = M.FriendListDiff.new()
    
    for _, newFriend in ipairs(newFriends) do
        if not containsName(oldFriends, newFriend) then
            table.insert(diff.addedFriends, newFriend)
        end
    end
    
    for _, oldFriend in ipairs(oldFriends) do
        if not containsName(newFriends, oldFriend) then
            table.insert(diff.removedFriends, oldFriend)
        end
    end
    
    return diff
end

function M.diffStatuses(oldStatuses, newStatuses)
    local changed = {}
    
    local oldMap = {}
    for _, status in ipairs(oldStatuses) do
        local key = normalizeName(status.characterName)
        oldMap[key] = status
    end
    
    for _, newStatus in ipairs(newStatuses) do
        local normalizedName = normalizeName(newStatus.characterName)
        local oldStatus = oldMap[normalizedName]
        
        if oldStatus then
            local hasChanged = false
            if newStatus.hasStatusChanged then
                hasChanged = newStatus:hasStatusChanged(oldStatus)
            else
                hasChanged = newStatus.characterName ~= oldStatus.characterName or
                           newStatus.displayName ~= oldStatus.displayName or
                           newStatus.isOnline ~= oldStatus.isOnline or
                           newStatus.job ~= oldStatus.job or
                           newStatus.rank ~= oldStatus.rank or
                           newStatus.nation ~= oldStatus.nation or
                           newStatus.zone ~= oldStatus.zone or
                           newStatus.showOnlineStatus ~= oldStatus.showOnlineStatus or
                           newStatus.isLinkedCharacter ~= oldStatus.isLinkedCharacter or
                           newStatus.isOnAltCharacter ~= oldStatus.isOnAltCharacter or
                           newStatus.altCharacterName ~= oldStatus.altCharacterName or
                           newStatus.friendedAs ~= oldStatus.friendedAs
            end
            if hasChanged then
                table.insert(changed, newStatus.characterName)
            end
        else
            table.insert(changed, newStatus.characterName)
        end
    end
    
    return changed
end

function M.diffOnlineStatus(oldStatuses, newStatuses)
    local changed = {}
    
    local oldMap = {}
    for _, status in ipairs(oldStatuses) do
        local key = normalizeName(status.characterName)
        oldMap[key] = status
    end
    
    for _, newStatus in ipairs(newStatuses) do
        local normalizedName = normalizeName(newStatus.characterName)
        local oldStatus = oldMap[normalizedName]
        
        if oldStatus then
            local hasChanged = false
            if newStatus.hasOnlineStatusChanged then
                hasChanged = newStatus:hasOnlineStatusChanged(oldStatus)
            else
                hasChanged = newStatus.isOnline ~= oldStatus.isOnline
            end
            if hasChanged then
                table.insert(changed, newStatus.characterName)
            end
        elseif newStatus.isOnline then
            table.insert(changed, newStatus.characterName)
        end
    end
    
    return changed
end

return M
