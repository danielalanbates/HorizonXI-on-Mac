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
    
    local function assertNil(value, msg)
        if value ~= nil then
            error((msg or "Assertion failed") .. ": expected nil, got " .. tostring(value))
        end
    end
    
    test("normalizeTag trims whitespace", function()
        assertEqual("Favorite", tagcore.normalizeTag("  Favorite  "))
        assertEqual("Test", tagcore.normalizeTag("Test"))
        assertEqual("Multi Word", tagcore.normalizeTag("  Multi Word  "))
    end)
    
    test("normalizeTag returns nil for empty or invalid", function()
        assertNil(tagcore.normalizeTag(""))
        assertNil(tagcore.normalizeTag("   "))
        assertNil(tagcore.normalizeTag(nil))
        assertNil(tagcore.normalizeTag(123))
    end)
    
    test("tagsEqual compares case-insensitively", function()
        assertTrue(tagcore.tagsEqual("Favorite", "favorite"))
        assertTrue(tagcore.tagsEqual("FAVORITE", "favorite"))
        assertTrue(tagcore.tagsEqual("Test Tag", "test tag"))
        assertFalse(tagcore.tagsEqual("Favorite", "Other"))
    end)
    
    test("tagsEqual handles nil", function()
        assertTrue(tagcore.tagsEqual(nil, nil))
        assertFalse(tagcore.tagsEqual("Favorite", nil))
        assertFalse(tagcore.tagsEqual(nil, "Favorite"))
    end)
    
    test("isValidTag returns true for valid tags", function()
        assertTrue(tagcore.isValidTag("Favorite"))
        assertTrue(tagcore.isValidTag("  Valid  "))
        assertTrue(tagcore.isValidTag("Multi Word Tag"))
    end)
    
    test("isValidTag returns false for invalid tags", function()
        assertFalse(tagcore.isValidTag(""))
        assertFalse(tagcore.isValidTag("   "))
        assertFalse(tagcore.isValidTag(nil))
    end)
    
    test("isUntagged is inverse of isValidTag", function()
        assertTrue(tagcore.isUntagged(""))
        assertTrue(tagcore.isUntagged(nil))
        assertTrue(tagcore.isUntagged("   "))
        assertFalse(tagcore.isUntagged("Favorite"))
    end)
    
    test("getFriendKey returns friendAccountId when available", function()
        local friend = { friendAccountId = "12345", name = "TestUser" }
        assertEqual("12345", tagcore.getFriendKey(friend))
    end)
    
    test("getFriendKey returns lowercase name as fallback", function()
        local friend = { name = "TestUser" }
        assertEqual("testuser", tagcore.getFriendKey(friend))
    end)
    
    test("getFriendKey handles friendName field", function()
        local friend = { friendName = "OtherUser" }
        assertEqual("otheruser", tagcore.getFriendKey(friend))
    end)
    
    test("getFriendKey returns nil for invalid friend", function()
        assertNil(tagcore.getFriendKey(nil))
        assertNil(tagcore.getFriendKey({}))
        assertNil(tagcore.getFriendKey({ name = "" }))
    end)
    
    test("findTagIndex finds existing tag", function()
        local tagOrder = { "Favorite", "Friends", "Guild" }
        assertEqual(1, tagcore.findTagIndex(tagOrder, "Favorite"))
        assertEqual(2, tagcore.findTagIndex(tagOrder, "Friends"))
        assertEqual(3, tagcore.findTagIndex(tagOrder, "Guild"))
    end)
    
    test("findTagIndex is case-insensitive", function()
        local tagOrder = { "Favorite", "Friends" }
        assertEqual(1, tagcore.findTagIndex(tagOrder, "FAVORITE"))
        assertEqual(2, tagcore.findTagIndex(tagOrder, "friends"))
    end)
    
    test("findTagIndex returns nil for missing tag", function()
        local tagOrder = { "Favorite", "Friends" }
        assertNil(tagcore.findTagIndex(tagOrder, "Missing"))
    end)
    
    test("tagExistsInOrder returns true/false appropriately", function()
        local tagOrder = { "Favorite", "Friends" }
        assertTrue(tagcore.tagExistsInOrder(tagOrder, "Favorite"))
        assertTrue(tagcore.tagExistsInOrder(tagOrder, "favorite"))
        assertFalse(tagcore.tagExistsInOrder(tagOrder, "Missing"))
    end)
    
    print(string.format("\nTagCore Tests: %d passed, %d failed", passed, failed))
    return failed == 0
end

return M

