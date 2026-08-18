-- FriendListTest.lua
-- Unit tests for Core::FriendList

local friendlist = require("core.friendlist")

local function testFriendListConstruction()
    local list = friendlist.FriendList.new()
    assert(list:empty(), "FriendList should be empty initially")
    assert(list:size() == 0, "FriendList size should be 0")
    
    return true
end

local function testFriendListAddFriend()
    local list = friendlist.FriendList.new()
    
    assert(list:addFriend("Friend1", "Friend1"), "Should add friend")
    assert(list:size() == 1, "FriendList size should be 1")
    assert(list:hasFriend("Friend1"), "Should have friend")
    assert(list:hasFriend("friend1"), "Should be case-insensitive")
    
    assert(not list:addFriend("Friend1"), "Should not add duplicate friend")
    assert(list:size() == 1, "FriendList size should still be 1")
    
    assert(list:addFriend("Friend2"), "Should add second friend")
    assert(list:size() == 2, "FriendList size should be 2")
    
    return true
end

local function testFriendListRemoveFriend()
    local list = friendlist.FriendList.new()
    list:addFriend("Friend1")
    list:addFriend("Friend2")
    
    assert(list:removeFriend("Friend1"), "Should remove friend")
    assert(list:size() == 1, "FriendList size should be 1")
    assert(not list:hasFriend("Friend1"), "Should not have removed friend")
    assert(list:hasFriend("Friend2"), "Should still have other friend")
    
    assert(not list:removeFriend("Friend1"), "Should not remove non-existent friend")
    assert(list:size() == 1, "FriendList size should still be 1")
    
    return true
end

local function testFriendListUpdateFriend()
    local list = friendlist.FriendList.new()
    list:addFriend("Friend1", "Original")
    
    local updated = friendlist.Friend.new("Friend1", "Updated")
    updated.linkedCharacters = {"Alt1"}
    
    assert(list:updateFriend(updated), "Should update friend")
    local f = list:findFriend("Friend1")
    assert(f ~= nil, "Should find friend")
    assert(f.friendedAs == "updated", "friendedAs should be normalized to lowercase")
    assert(#f.linkedCharacters == 1, "Should have linked character")
    
    local nonExistent = friendlist.Friend.new("NonExistent", "")
    assert(not list:updateFriend(nonExistent), "Should not update non-existent friend")
    
    return true
end

local function testFriendListFindFriend()
    local list = friendlist.FriendList.new()
    list:addFriend("Friend1", "Original")
    
    local friend1 = list:findFriend("Friend1")
    assert(friend1 ~= nil, "Should find friend")
    assert(friend1.name == "friend1", "Name should be normalized to lowercase")
    assert(friend1.friendedAs == "original", "friendedAs should be normalized to lowercase")
    
    local friend2 = list:findFriend("friend1")  -- Case-insensitive
    assert(friend2 ~= nil, "Should find friend (case-insensitive)")
    
    local friend3 = list:findFriend("NonExistent")
    assert(friend3 == nil, "Should not find non-existent friend")
    
    return true
end

local function testFriendListGetFriendNames()
    local list = friendlist.FriendList.new()
    list:addFriend("Friend1")
    list:addFriend("Friend2")
    list:addFriend("Friend3")
    
    local names = list:getFriendNames()
    assert(#names == 3, "Should have 3 friend names")
    
    local found1, found2, found3 = false, false, false
    for _, name in ipairs(names) do
        if name == "friend1" then found1 = true
        elseif name == "friend2" then found2 = true
        elseif name == "friend3" then found3 = true
        end
    end
    assert(found1 and found2 and found3, "Should have all friend names")
    
    return true
end

local function testFriendListUpdateFriendStatus()
    local list = friendlist.FriendList.new()
    
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "Friend1"
    status1.isOnline = true
    status1.job = "WAR"
    
    list:updateFriendStatus(status1)
    local status = list:getFriendStatus("Friend1")
    assert(status ~= nil, "Should have friend status")
    assert(status.isOnline, "Status should be online")
    assert(status.job == "WAR", "Status should have job")
    
    -- Update existing status
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "Friend1"
    status2.isOnline = false
    status2.job = "MNK"
    
    list:updateFriendStatus(status2)
    status = list:getFriendStatus("Friend1")
    assert(status ~= nil, "Should still have friend status")
    assert(not status.isOnline, "Status should be offline")
    assert(status.job == "MNK", "Status should have updated job")
    
    return true
end

local function testFriendListClear()
    local list = friendlist.FriendList.new()
    list:addFriend("Friend1")
    list:addFriend("Friend2")
    
    local status = friendlist.FriendStatus.new()
    status.characterName = "Friend1"
    list:updateFriendStatus(status)
    
    list:clear()
    assert(list:empty(), "FriendList should be empty after clear")
    assert(#list:getFriendStatuses() == 0, "Friend statuses should be empty after clear")
    
    return true
end

local function runTests()
    local tests = {
        testFriendListConstruction,
        testFriendListAddFriend,
        testFriendListRemoveFriend,
        testFriendListUpdateFriend,
        testFriendListFindFriend,
        testFriendListGetFriendNames,
        testFriendListUpdateFriendStatus,
        testFriendListClear
    }
    
    local passed = 0
    local failed = 0
    
    for _, test in ipairs(tests) do
        local success, err = pcall(test)
        if success then
            passed = passed + 1
            print("  PASS: " .. tostring(test))
        else
            failed = failed + 1
            print("  FAIL: " .. tostring(test) .. " - " .. tostring(err))
        end
    end
    
    print(string.format("FriendListTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

