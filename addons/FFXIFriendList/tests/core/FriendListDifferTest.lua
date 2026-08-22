-- FriendListDifferTest.lua
-- Unit tests for Core::FriendListDiffer

local friendlist = require("core.friendlist")

local function testDiff()
    local oldFriends = {"Friend1", "Friend2", "Friend3"}
    local newFriends = {"Friend2", "Friend3", "Friend4"}
    
    local diff = friendlist.diff(oldFriends, newFriends)
    
    assert(#diff.addedFriends == 1, "Should detect added friend")
    assert(diff.addedFriends[1] == "Friend4", "Should detect Friend4 as added")
    
    assert(#diff.removedFriends == 1, "Should detect removed friend")
    assert(diff.removedFriends[1] == "Friend1", "Should detect Friend1 as removed")
    
    assert(diff:hasChanges(), "Should have changes")
    
    return true
end

local function testDiffStatuses()
    local oldStatuses = {}
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "Friend1"
    status1.job = "WAR"
    table.insert(oldStatuses, status1)
    
    local newStatuses = {}
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "Friend1"
    status2.job = "MNK"  -- Changed
    table.insert(newStatuses, status2)
    
    local changed = friendlist.diffStatuses(oldStatuses, newStatuses)
    assert(#changed == 1, "Should detect changed status")
    assert(changed[1] == "Friend1", "Should detect Friend1 as changed")
    
    return true
end

local function testDiffOnlineStatus()
    local oldStatuses = {}
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "Friend1"
    status1.isOnline = false
    table.insert(oldStatuses, status1)
    
    local newStatuses = {}
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "Friend1"
    status2.isOnline = true  -- Changed
    table.insert(newStatuses, status2)
    
    local changed = friendlist.diffOnlineStatus(oldStatuses, newStatuses)
    assert(#changed == 1, "Should detect online status change")
    assert(changed[1] == "Friend1", "Should detect Friend1 as changed")
    
    return true
end

local function testNoChanges()
    local friends = {"Friend1", "Friend2"}
    local diff = friendlist.diff(friends, friends)
    
    assert(not diff:hasChanges(), "Should not have changes")
    assert(#diff.addedFriends == 0, "Should have no added friends")
    assert(#diff.removedFriends == 0, "Should have no removed friends")
    
    return true
end

local function runTests()
    local tests = {
        testDiff,
        testDiffStatuses,
        testDiffOnlineStatus,
        testNoChanges
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
    
    print(string.format("FriendListDifferTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

