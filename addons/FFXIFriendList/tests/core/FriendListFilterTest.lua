-- FriendListFilterTest.lua
-- Unit tests for Core::FriendListFilter

local friendlist = require("core.friendlist")

local function testFilterByName()
    local friends = {
        friendlist.Friend.new("Alice", "Alice"),
        friendlist.Friend.new("Bob", "Bob"),
        friendlist.Friend.new("Charlie", "Charlie")
    }
    
    local filtered = friendlist.filterByName(friends, "al")
    assert(#filtered == 1, "Should filter by name")
    assert(filtered[1].name == "alice", "Should find Alice")
    
    filtered = friendlist.filterByName(friends, "B")
    assert(#filtered == 1, "Should filter by name")
    assert(filtered[1].name == "bob", "Should find Bob")
    
    filtered = friendlist.filterByName(friends, "")
    assert(#filtered == 3, "Empty search should return all")
    
    return true
end

local function testFilterByOnlineStatus()
    local names = {"Online1", "Offline1", "Online2"}
    
    local statuses = {}
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "Online1"
    status1.isOnline = true
    status1.showOnlineStatus = true
    table.insert(statuses, status1)
    
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "Offline1"
    status2.isOnline = false
    status2.showOnlineStatus = true
    table.insert(statuses, status2)
    
    local status3 = friendlist.FriendStatus.new()
    status3.characterName = "Online2"
    status3.isOnline = true
    status3.showOnlineStatus = true
    table.insert(statuses, status3)
    
    local online = friendlist.filterByOnlineStatus(names, statuses, true)
    assert(#online == 2, "Should filter online friends")
    
    local offline = friendlist.filterByOnlineStatus(names, statuses, false)
    assert(#offline == 1, "Should filter offline friends")
    
    return true
end

local function testFilterOnline()
    local names = {"Online1", "Offline1"}
    
    local statuses = {}
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "Online1"
    status1.isOnline = true
    status1.showOnlineStatus = true
    table.insert(statuses, status1)
    
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "Offline1"
    status2.isOnline = false
    status2.showOnlineStatus = true
    table.insert(statuses, status2)
    
    local online = friendlist.filterOnline(names, statuses)
    assert(#online == 1, "Should filter online friends")
    assert(online[1] == "Online1", "Should return online friend")
    
    return true
end

local function testFilterOnlineRespectsHiddenOnlineStatus()
    local names = {"HiddenOnline", "VisibleOnline"}
    
    local statuses = {}
    local hidden = friendlist.FriendStatus.new()
    hidden.characterName = "HiddenOnline"
    hidden.isOnline = true
    hidden.showOnlineStatus = false  -- privacy: should not appear as online
    table.insert(statuses, hidden)
    
    local visible = friendlist.FriendStatus.new()
    visible.characterName = "VisibleOnline"
    visible.isOnline = true
    visible.showOnlineStatus = true
    table.insert(statuses, visible)
    
    local online = friendlist.filterOnline(names, statuses)
    assert(#online == 1, "Should only show visible online friends")
    assert(online[1] == "VisibleOnline", "Should return visible online friend")
    
    return true
end

local function testFilterWithPredicate()
    local friends = {
        friendlist.Friend.new("Alice", "Alice"),
        friendlist.Friend.new("Bob", "Bob"),
        friendlist.Friend.new("Charlie", "Charlie")
    }
    
    local filtered = friendlist.filter(friends, function(f)
        return #f.name > 3
    end)
    
    assert(#filtered == 2, "Should filter by predicate")
    
    return true
end

local function runTests()
    local tests = {
        testFilterByName,
        testFilterByOnlineStatus,
        testFilterOnline,
        testFilterOnlineRespectsHiddenOnlineStatus,
        testFilterWithPredicate
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
    
    print(string.format("FriendListFilterTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

