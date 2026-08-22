local taggrouper = require("core.taggrouper")
local tagcore = require("core.tagcore")

local M = {}

function M.runTests()
    local passed = 0
    local failed = 0
    
    local function test(name, fn)
        local success, err = pcall(fn)
        if success then
            passed = passed + 1
            print("[PASS] " .. name)
        else
            failed = failed + 1
            print("[FAIL] " .. name .. ": " .. tostring(err))
        end
    end
    
    local function assertEqual(expected, actual, msg)
        if expected ~= actual then
            error((msg or "Assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        end
    end
    
    local function assertTrue(value, msg)
        if not value then
            error((msg or "Assertion failed") .. ": expected true, got " .. tostring(value))
        end
    end
    
    local function assertFalse(value, msg)
        if value then
            error((msg or "Assertion failed") .. ": expected false, got " .. tostring(value))
        end
    end
    
    local function makeFriend(name, isOnline, tag)
        return {
            name = name,
            isOnline = isOnline,
            presence = { status = isOnline and "online" or "offline" },
            _testTag = tag
        }
    end
    
    test("isOnlineish returns true for online friends", function()
        assertTrue(taggrouper.isOnlineish({ isOnline = true }))
        assertTrue(taggrouper.isOnlineish({ presence = { status = "online" } }))
        assertTrue(taggrouper.isOnlineish({ presence = { status = "away" } }))
    end)
    
    test("isOnlineish returns false for offline friends", function()
        assertFalse(taggrouper.isOnlineish({ isOnline = false }))
        assertFalse(taggrouper.isOnlineish({ presence = { status = "offline" } }))
        assertFalse(taggrouper.isOnlineish(nil))
        assertFalse(taggrouper.isOnlineish({}))
    end)
    
    test("groupFriendsByTag respects tagOrder", function()
        local friends = {
            makeFriend("Alice", true, "Friends"),
            makeFriend("Bob", true, "Favorite"),
            makeFriend("Charlie", false, "Guild")
        }
        local tagOrder = { "Favorite", "Friends", "Guild" }
        local getFriendTag = function(f) return f._testTag end
        
        local groups = taggrouper.groupFriendsByTag(friends, tagOrder, getFriendTag)
        
        assertEqual(3, #groups)
        assertEqual("Favorite", groups[1].tag)
        assertEqual("Friends", groups[2].tag)
        assertEqual("Guild", groups[3].tag)
    end)
    
    test("groupFriendsByTag puts untagged last", function()
        local friends = {
            makeFriend("Alice", true, nil),
            makeFriend("Bob", true, "Favorite")
        }
        local tagOrder = { "Favorite" }
        local getFriendTag = function(f) return f._testTag end
        
        local groups = taggrouper.groupFriendsByTag(friends, tagOrder, getFriendTag)
        
        assertEqual(2, #groups)
        assertEqual("Favorite", groups[1].tag)
        assertEqual("__untagged__", groups[2].tag)
        assertEqual("Untagged", groups[2].displayTag)
    end)
    
    test("groupFriendsByTag places friends in correct groups", function()
        local friends = {
            makeFriend("Alice", true, "Favorite"),
            makeFriend("Bob", false, "Favorite"),
            makeFriend("Charlie", true, "Guild")
        }
        local tagOrder = { "Favorite", "Guild" }
        local getFriendTag = function(f) return f._testTag end
        
        local groups = taggrouper.groupFriendsByTag(friends, tagOrder, getFriendTag)
        
        assertEqual(2, #groups[1].friends)
        assertEqual(1, #groups[2].friends)
        assertEqual("Alice", groups[1].friends[1].name)
        assertEqual("Charlie", groups[2].friends[1].name)
    end)
    
    test("groupFriendsByTag handles missing tags as untagged", function()
        local friends = {
            makeFriend("Alice", true, "NonExistent")
        }
        local tagOrder = { "Favorite" }
        local getFriendTag = function(f) return f._testTag end
        
        local groups = taggrouper.groupFriendsByTag(friends, tagOrder, getFriendTag)
        
        assertEqual(2, #groups)
        assertEqual(0, #groups[1].friends)
        assertEqual(1, #groups[2].friends)
    end)
    
    test("sortWithinGroup by status puts online first", function()
        local friends = {
            makeFriend("Zack", false),
            makeFriend("Alice", true),
            makeFriend("Bob", false),
            makeFriend("Charlie", true)
        }
        
        taggrouper.sortWithinGroup(friends, "status", "asc")
        
        assertTrue(friends[1].isOnline)
        assertTrue(friends[2].isOnline)
        assertFalse(friends[3].isOnline)
        assertFalse(friends[4].isOnline)
    end)
    
    test("sortWithinGroup by name sorts alphabetically", function()
        local friends = {
            makeFriend("Zack", true),
            makeFriend("Alice", true),
            makeFriend("Bob", true)
        }
        
        taggrouper.sortWithinGroup(friends, "name", "asc")
        
        assertEqual("Alice", friends[1].name)
        assertEqual("Bob", friends[2].name)
        assertEqual("Zack", friends[3].name)
    end)
    
    test("sortWithinGroup descending reverses order", function()
        local friends = {
            makeFriend("Alice", true),
            makeFriend("Bob", true),
            makeFriend("Zack", true)
        }
        
        taggrouper.sortWithinGroup(friends, "name", "desc")
        
        assertEqual("Zack", friends[1].name)
        assertEqual("Bob", friends[2].name)
        assertEqual("Alice", friends[3].name)
    end)
    
    test("sortAllGroups sorts each group independently", function()
        local groups = {
            { tag = "Favorite", friends = { makeFriend("Zack", true), makeFriend("Alice", true) } },
            { tag = "Guild", friends = { makeFriend("Charlie", true), makeFriend("Bob", true) } }
        }
        
        taggrouper.sortAllGroups(groups, "name", "asc")
        
        assertEqual("Alice", groups[1].friends[1].name)
        assertEqual("Zack", groups[1].friends[2].name)
        assertEqual("Bob", groups[2].friends[1].name)
        assertEqual("Charlie", groups[2].friends[2].name)
    end)
    
    print(string.format("\nTagGrouper Tests: %d passed, %d failed", passed, failed))
    return failed == 0
end

return M

