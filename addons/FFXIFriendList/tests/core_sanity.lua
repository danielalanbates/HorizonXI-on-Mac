local friendlist = require("core.friendlist")
local models = require("core.models")
local notescore = require("core.notescore")
local sanitize = require("core.sanitize")
local versioncore = require("core.versioncore")
local serverlistcore = require("core.serverlistcore")
local util = require("core.util")
local notificationsoundpolicy = require("core.notificationsoundpolicy")

local function testFriendList()
    local list = friendlist.FriendList.new()
    
    assert(list:empty(), "FriendList should be empty initially")
    assert(list:size() == 0, "FriendList size should be 0")
    
    assert(list:addFriend("TestFriend"), "Should add friend")
    assert(list:size() == 1, "FriendList size should be 1")
    assert(list:hasFriend("TestFriend"), "Should have friend")
    assert(list:hasFriend("testfriend"), "Should be case-insensitive")
    
    local friend = list:findFriend("TestFriend")
    assert(friend ~= nil, "Should find friend")
    assert(friend.name == "testfriend", "Name should be normalized")
    
    local names = list:getFriendNames()
    assert(#names == 1, "Should have 1 friend name")
    assert(names[1] == "testfriend", "Name should be normalized")
    
    assert(list:removeFriend("TestFriend"), "Should remove friend")
    assert(list:size() == 0, "FriendList should be empty after removal")
    
    return true
end

local function testFriendListSort()
    local names = {"Charlie", "Alice", "Bob"}
    friendlist.sortFriendsAlphabetically(names)
    
    assert(names[1] == "Alice", "Should sort alphabetically")
    assert(names[2] == "Bob", "Should sort alphabetically")
    assert(names[3] == "Charlie", "Should sort alphabetically")
    
    return true
end

local function testFriendListFilter()
    local friends = {
        friendlist.Friend.new("Alice"),
        friendlist.Friend.new("Bob"),
        friendlist.Friend.new("Charlie")
    }
    
    local filtered = friendlist.filterByName(friends, "b")
    assert(#filtered == 1, "Should filter by name")
    assert(filtered[1].name == "bob", "Should find Bob")
    
    return true
end

local function testFriendListDiff()
    local oldFriends = {"Alice", "Bob"}
    local newFriends = {"Bob", "Charlie"}
    
    local diff = friendlist.diff(oldFriends, newFriends)
    assert(#diff.addedFriends == 1, "Should detect added friend")
    assert(#diff.removedFriends == 1, "Should detect removed friend")
    assert(diff.addedFriends[1] == "Charlie", "Should detect Charlie as added")
    assert(diff.removedFriends[1] == "Alice", "Should detect Alice as removed")
    
    return true
end

local function testModels()
    local presence = models.Presence.new()
    assert(presence.characterName == "", "Presence should initialize empty")
    
    local color = models.Color.new(0.5, 0.6, 0.7, 0.8)
    assert(color.r == 0.5, "Color should initialize correctly")
    assert(color.g == 0.6, "Color should initialize correctly")
    
    local prefs = models.Preferences.new()
    assert(prefs.useServerNotes == false, "Preferences should initialize correctly")
    assert(prefs.mainFriendView ~= nil, "Preferences should have mainFriendView")
    
    return true
end

local function testNotesCore()
    local note = notescore.Note.new("Friend", "Note text", 12345)
    assert(note.friendName == "Friend", "Note should initialize correctly")
    assert(note.note == "Note text", "Note should initialize correctly")
    assert(not note:isEmpty(), "Note should not be empty")
    
    local merged = notescore.NoteMerger.merge("Local", 1000, "Server", 2000, "2024-01-01 12:00", "2024-01-02 12:00")
    assert(merged ~= "", "Should merge notes")
    assert(string.find(merged, "Server Note") ~= nil, "Should contain server note")
    
    return true
end

local function testSanitize()
    local result = sanitize.validateCharacterName("TestName")
    assert(result.valid, "Should validate character name")
    assert(result.sanitized == "testname", "Should normalize name")
    
    local invalid = sanitize.validateCharacterName("")
    assert(not invalid.valid, "Should reject empty name")
    
    return true
end

local function testVersionCore()
    local v1 = versioncore.Version.parse("1.2.3")
    assert(v1 ~= nil, "Should parse version")
    assert(v1.major == 1, "Should parse major")
    assert(v1.minor == 2, "Should parse minor")
    assert(v1.patch == 3, "Should parse patch")
    
    local v2 = versioncore.Version.parse("2.0.0")
    assert(v1 < v2, "Should compare versions")
    
    return true
end

local function testUtil()
    assert(util.Limits.CHARACTER_NAME_MAX == 16, "Should have limits")
    assert(util.Limits.NOTE_MAX == 8192, "Should have limits")
    
    local result = util.ValidationResult.new(true, "", "test")
    assert(result.valid, "Should create validation result")
    assert(result.sanitized == "test", "Should have sanitized value")
    
    return true
end

local function runTests()
    print("Running Core sanity tests...")
    
    local tests = {
        testFriendList,
        testFriendListSort,
        testFriendListFilter,
        testFriendListDiff,
        testModels,
        testNotesCore,
        testSanitize,
        testVersionCore,
        testUtil
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
    
    print(string.format("\nResults: %d passed, %d failed", passed, failed))
    
    if failed == 0 then
        print("All tests passed!")
        return true
    else
        print("Some tests failed!")
        return false
    end
end

if not pcall(runTests) then
    print("Error running tests")
    os.exit(1)
end

