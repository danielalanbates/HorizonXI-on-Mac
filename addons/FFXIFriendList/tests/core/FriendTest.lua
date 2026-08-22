-- FriendTest.lua
-- Unit tests for Core::Friend

local friendlist = require("core.friendlist")

local function testFriendConstruction()
    local friend1 = friendlist.Friend.new()
    assert(friend1.name == "", "Friend should initialize with empty name")
    assert(friend1.friendedAs == "", "Friend should initialize with empty friendedAs")
    assert(#friend1.linkedCharacters == 0, "Friend should initialize with empty linkedCharacters")
    
    local friend2 = friendlist.Friend.new("TestName", "FriendedAs")
    assert(friend2.name == "TestName", "Friend should set name")
    assert(friend2.friendedAs == "FriendedAs", "Friend should set friendedAs")
    
    return true
end

local function testFriendEquality()
    local friend1 = friendlist.Friend.new("TestName", "FriendedAs")
    local friend2 = friendlist.Friend.new("testname", "friendedas")  -- Case-insensitive
    local friend3 = friendlist.Friend.new("OtherName", "FriendedAs")
    
    assert(friend1 == friend2, "Friends should be equal (case-insensitive)")
    assert(friend1 ~= friend3, "Different friends should not be equal")
    
    return true
end

local function testFriendMatchesCharacter()
    local f = friendlist.Friend.new("TestName", "FriendedAs")
    f.linkedCharacters = {"AltChar1", "AltChar2"}
    
    assert(f:matchesCharacter("TestName"), "Should match main character name")
    assert(f:matchesCharacter("testname"), "Should match main character name (case-insensitive)")
    assert(f:matchesCharacter("AltChar1"), "Should match linked character")
    assert(f:matchesCharacter("altchar1"), "Should match linked character (case-insensitive)")
    assert(f:matchesCharacter("AltChar2"), "Should match linked character")
    assert(not f:matchesCharacter("OtherName"), "Should not match other name")
    
    return true
end

local function testFriendHasLinkedCharacters()
    local friend1 = friendlist.Friend.new("TestName", "FriendedAs")
    assert(not friend1:hasLinkedCharacters(), "Friend without linked characters should return false")
    
    local friend2 = friendlist.Friend.new("TestName", "FriendedAs")
    friend2.linkedCharacters = {"AltChar"}
    assert(friend2:hasLinkedCharacters(), "Friend with linked characters should return true")
    
    return true
end

local function runTests()
    local tests = {
        testFriendConstruction,
        testFriendEquality,
        testFriendMatchesCharacter,
        testFriendHasLinkedCharacters
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
    
    print(string.format("FriendTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

