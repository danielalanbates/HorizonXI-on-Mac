local Tags = require("app.features.Tags")

local M = {}

local function createMockStorage()
    local data = {}
    return {
        save = function(key, value)
            data[key] = value
            return true
        end,
        load = function(key)
            return data[key]
        end,
        getData = function()
            return data
        end
    }
end

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
    
    test("Tags.new creates instance with default Favorite tag", function()
        local tags = Tags.Tags.new({})
        assertEqual(1, #tags.tagOrder)
        assertEqual("Favorite", tags.tagOrder[1])
    end)
    
    test("createTag adds new tag to end of tagOrder", function()
        local tags = Tags.Tags.new({})
        assertTrue(tags:createTag("Friends"))
        assertEqual(2, #tags.tagOrder)
        assertEqual("Friends", tags.tagOrder[2])
    end)
    
    test("createTag normalizes tag name", function()
        local tags = Tags.Tags.new({})
        assertTrue(tags:createTag("  Guild  "))
        assertEqual("Guild", tags.tagOrder[2])
    end)
    
    test("createTag rejects duplicate tags (case-insensitive)", function()
        local tags = Tags.Tags.new({})
        assertFalse(tags:createTag("FAVORITE"))
        assertEqual(1, #tags.tagOrder)
    end)
    
    test("setTagForFriend assigns tag to friend", function()
        local tags = Tags.Tags.new({})
        assertTrue(tags:setTagForFriend("testuser", "Favorite"))
        assertEqual("Favorite", tags:getTagForFriend("testuser"))
    end)
    
    test("setTagForFriend auto-creates missing tag", function()
        local tags = Tags.Tags.new({})
        tags:setTagForFriend("testuser", "NewTag")
        assertEqual(2, #tags.tagOrder)
        assertEqual("NewTag", tags:getTagForFriend("testuser"))
    end)
    
    test("setTagForFriend clears tag when nil passed", function()
        local tags = Tags.Tags.new({})
        tags:setTagForFriend("testuser", "Favorite")
        tags:setTagForFriend("testuser", nil)
        assertNil(tags:getTagForFriend("testuser"))
    end)
    
    test("deleteTag removes tag from tagOrder", function()
        local tags = Tags.Tags.new({})
        tags:createTag("ToDelete")
        assertTrue(tags:deleteTag("ToDelete"))
        assertEqual(1, #tags.tagOrder)
    end)
    
    test("deleteTag clears tag from affected friends", function()
        local tags = Tags.Tags.new({})
        tags:createTag("ToDelete")
        tags:setTagForFriend("user1", "ToDelete")
        tags:deleteTag("ToDelete")
        assertNil(tags:getTagForFriend("user1"))
    end)
    
    test("moveTagUp swaps with previous tag", function()
        local tags = Tags.Tags.new({})
        tags:createTag("Second")
        assertTrue(tags:moveTagUp("Second"))
        assertEqual("Second", tags.tagOrder[1])
        assertEqual("Favorite", tags.tagOrder[2])
    end)
    
    test("moveTagUp returns false for first tag", function()
        local tags = Tags.Tags.new({})
        assertFalse(tags:moveTagUp("Favorite"))
    end)
    
    test("moveTagDown swaps with next tag", function()
        local tags = Tags.Tags.new({})
        tags:createTag("Second")
        assertTrue(tags:moveTagDown("Favorite"))
        assertEqual("Second", tags.tagOrder[1])
        assertEqual("Favorite", tags.tagOrder[2])
    end)
    
    test("moveTagDown returns false for last tag", function()
        local tags = Tags.Tags.new({})
        assertFalse(tags:moveTagDown("Favorite"))
    end)
    
    test("isCollapsed/setCollapsed manage collapsed state", function()
        local tags = Tags.Tags.new({})
        assertFalse(tags:isCollapsed("Favorite"))
        tags:setCollapsed("Favorite", true)
        assertTrue(tags:isCollapsed("Favorite"))
        tags:setCollapsed("Favorite", false)
        assertFalse(tags:isCollapsed("Favorite"))
    end)
    
    test("queueRetag adds to pending queue", function()
        local tags = Tags.Tags.new({})
        assertTrue(tags:queueRetag("user1", "Favorite"))
        assertTrue(tags:hasPendingRetags())
    end)
    
    test("flushRetagQueue applies all queued retags", function()
        local storage = createMockStorage()
        local tags = Tags.Tags.new({ storage = storage })
        tags:queueRetag("user1", "Favorite")
        tags:queueRetag("user2", "Favorite")
        assertTrue(tags:flushRetagQueue())
        assertFalse(tags:hasPendingRetags())
        assertEqual("Favorite", tags:getTagForFriend("user1"))
        assertEqual("Favorite", tags:getTagForFriend("user2"))
    end)
    
    test("flushRetagQueue returns false when queue empty", function()
        local tags = Tags.Tags.new({})
        assertFalse(tags:flushRetagQueue())
    end)
    
    test("setPendingTag/consumePendingTag for befriend flow", function()
        local tags = Tags.Tags.new({})
        tags:setPendingTag("NewFriend", "Friends")
        assertEqual("Friends", tags:consumePendingTag("NewFriend"))
        assertNil(tags:consumePendingTag("NewFriend"))
    end)
    
    -- BUG 1 FIX TESTS: Pending tag persistence
    
    test("setPendingTag persists to storage immediately", function()
        local storage = createMockStorage()
        local tags = Tags.Tags.new({ storage = storage })
        tags:load()
        
        tags:setPendingTag("NewFriend", "Linkshell")
        
        -- Check that pendingTags is saved to gConfig
        assertEqual("Linkshell", tags:getPendingTag("NewFriend"))
        
        -- After reload, pending tag should persist
        local tags2 = Tags.Tags.new({ storage = storage })
        tags2:load()
        assertEqual("Linkshell", tags2:getPendingTag("NewFriend"))
    end)
    
    test("consumePendingTag removes from persistence", function()
        local storage = createMockStorage()
        local tags = Tags.Tags.new({ storage = storage })
        tags:load()
        
        tags:setPendingTag("NewFriend", "Linkshell")
        local consumed = tags:consumePendingTag("NewFriend")
        assertEqual("Linkshell", consumed)
        
        -- After consume and reload, should be gone
        local tags2 = Tags.Tags.new({ storage = storage })
        tags2:load()
        assertNil(tags2:getPendingTag("NewFriend"))
    end)
    
    test("getState includes pendingCount", function()
        local tags = Tags.Tags.new({})
        tags:setPendingTag("Pending1", "Tag1")
        tags:setPendingTag("Pending2", "Tag2")
        
        local state = tags:getState()
        assertEqual(2, state.pendingCount)
    end)
    
    test("save/load persists state correctly", function()
        local storage = createMockStorage()
        local tags1 = Tags.Tags.new({ storage = storage })
        tags1:createTag("Guild")
        tags1:setTagForFriend("user1", "Favorite")
        tags1:setCollapsed("Favorite", true)
        tags1:save()
        
        local tags2 = Tags.Tags.new({ storage = storage })
        tags2:load()
        assertEqual(2, #tags2.tagOrder)
        assertEqual("Favorite", tags2:getTagForFriend("user1"))
        assertTrue(tags2:isCollapsed("Favorite"))
    end)
    
    test("getState returns proper structure", function()
        local tags = Tags.Tags.new({})
        tags:createTag("Test")
        local state = tags:getState()
        assertEqual(2, state.tagCount)
        assertEqual(2, #state.tagOrder)
    end)
    
    print(string.format("\nTags Feature Tests: %d passed, %d failed", passed, failed))
    return failed == 0
end

return M

