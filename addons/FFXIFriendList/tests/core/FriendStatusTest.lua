-- FriendStatusTest.lua
-- Unit tests for Core::FriendStatus

local friendlist = require("core.friendlist")

local function testFriendStatusConstruction()
    local status = friendlist.FriendStatus.new()
    assert(status.characterName == "", "FriendStatus should initialize with empty characterName")
    assert(status.isOnline == false, "FriendStatus should initialize with isOnline=false")
    assert(status.nation == -1, "FriendStatus should initialize with nation=-1")
    assert(status.lastSeenAt == 0, "FriendStatus should initialize with lastSeenAt=0")
    assert(status.showOnlineStatus == true, "FriendStatus should initialize with showOnlineStatus=true")
    assert(status.isLinkedCharacter == false, "FriendStatus should initialize with isLinkedCharacter=false")
    assert(status.isOnAltCharacter == false, "FriendStatus should initialize with isOnAltCharacter=false")
    
    return true
end

local function testFriendStatusEquality()
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "TestName"
    status1.isOnline = true
    status1.job = "WAR"
    status1.rank = "1"
    status1.nation = 1
    status1.zone = "San d'Oria"
    
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "TestName"
    status2.isOnline = true
    status2.job = "WAR"
    status2.rank = "1"
    status2.nation = 1
    status2.zone = "San d'Oria"
    
    assert(status1 == status2, "Equal statuses should be equal")
    
    status2.isOnline = false
    assert(status1 ~= status2, "Different statuses should not be equal")
    
    return true
end

local function testFriendStatusHasStatusChanged()
    local status1 = friendlist.FriendStatus.new()
    status1.characterName = "TestName"
    status1.isOnline = true
    status1.job = "WAR"
    
    local status2 = friendlist.FriendStatus.new()
    status2.characterName = "TestName"
    status2.isOnline = true
    status2.job = "WAR"
    
    assert(not status1:hasStatusChanged(status2), "Status should not have changed")
    
    status2.job = "MNK"
    assert(status1:hasStatusChanged(status2), "Status should have changed")
    
    status2 = friendlist.FriendStatus.new()
    status2.characterName = "TestName"
    status2.isOnline = true
    status2.job = "WAR"
    status2.lastSeenAt = 12345  -- Should not affect hasStatusChanged
    assert(not status1:hasStatusChanged(status2), "lastSeenAt should not affect hasStatusChanged")
    
    return true
end

local function testFriendStatusHasOnlineStatusChanged()
    local status1 = friendlist.FriendStatus.new()
    status1.isOnline = true
    
    local status2 = friendlist.FriendStatus.new()
    status2.isOnline = true
    
    assert(not status1:hasOnlineStatusChanged(status2), "Online status should not have changed")
    
    status2.isOnline = false
    assert(status1:hasOnlineStatusChanged(status2), "Online status should have changed")
    
    return true
end

local function runTests()
    local tests = {
        testFriendStatusConstruction,
        testFriendStatusEquality,
        testFriendStatusHasStatusChanged,
        testFriendStatusHasOnlineStatusChanged
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
    
    print(string.format("FriendStatusTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

