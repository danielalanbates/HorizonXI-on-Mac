-- FriendListSorterTest.lua
-- Unit tests for Core::FriendListSorter

local friendlist = require("core.friendlist")

local function testSortFriendsAlphabetically()
    local names = {"Charlie", "Alice", "Bob"}
    friendlist.sortFriendsAlphabetically(names)
    
    assert(names[1] == "Alice", "Should sort alphabetically")
    assert(names[2] == "Bob", "Should sort alphabetically")
    assert(names[3] == "Charlie", "Should sort alphabetically")
    
    return true
end

local function testSortFriendsByStatus()
    local names = {"Offline1", "Online1", "Offline2", "Online2"}
    
    local statuses = {}
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "Online1"
    status1.isOnline = true
    status1.showOnlineStatus = true
    table.insert(statuses, status1)
    
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "Online2"
    status2.isOnline = true
    status2.showOnlineStatus = true
    table.insert(statuses, status2)
    
    local status3 = friendlist.FriendStatus.new()
    status3.characterName = "Offline1"
    status3.isOnline = false
    status3.showOnlineStatus = true
    table.insert(statuses, status3)
    
    local status4 = friendlist.FriendStatus.new()
    status4.characterName = "Offline2"
    status4.isOnline = false
    status4.showOnlineStatus = true
    table.insert(statuses, status4)
    
    friendlist.sortFriendsByStatus(names, statuses)
    
    -- Online friends first
    assert((names[1] == "Online1" or names[1] == "Online2"), "Online friends should come first")
    assert((names[2] == "Online1" or names[2] == "Online2"), "Online friends should come first")
    -- Then offline
    assert((names[3] == "Offline1" or names[3] == "Offline2"), "Offline friends should come after")
    assert((names[4] == "Offline1" or names[4] == "Offline2"), "Offline friends should come after")
    
    return true
end

local function testSortFriendsAlphabeticallyObjects()
    local friends = {
        friendlist.Friend.new("Charlie", "Charlie"),
        friendlist.Friend.new("Alice", "Alice"),
        friendlist.Friend.new("Bob", "Bob")
    }
    
    friendlist.sortFriendsAlphabeticallyObjects(friends)
    
    assert(friends[1].name == "Alice", "Should sort alphabetically")
    assert(friends[2].name == "Bob", "Should sort alphabetically")
    assert(friends[3].name == "Charlie", "Should sort alphabetically")
    
    return true
end

local function runTests()
    local tests = {
        testSortFriendsAlphabetically,
        testSortFriendsByStatus,
        testSortFriendsAlphabeticallyObjects
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
    
    print(string.format("FriendListSorterTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

