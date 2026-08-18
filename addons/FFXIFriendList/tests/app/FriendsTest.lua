-- FriendsTest.lua
-- Unit tests for app/features/friends.lua

local Friends = require("app.features.friends")
local FriendList = require("core.friendlist")

local function createFakeDeps()
    local requests = {}
    local time = 1000
    
    return {
        net = {
            request = function(req)
                table.insert(requests, req)
                return #requests  -- Return request ID
            end,
            getRequests = function() return requests end,
            clearRequests = function() requests = {} end
        },
        connection = {
            isConnected = function() return true end,
            getBaseUrl = function() return "https://api.example.com" end,
            getHeaders = function() return {["Content-Type"] = "application/json"} end
        },
        time = function() 
            time = time + 100
            return time 
        end,
        logger = {
            info = function() end,
            error = function() end
        }
    }
end

local function testFriendsInitialState()
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    assert(friends.state == "idle", "Should start in idle state")
    assert(#friends:getFriends() == 0, "Should have no friends initially")
    assert(friends.lastError == nil, "Should have no error initially")
    
    return true
end

local function testFriendsRefresh()
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    deps.net.clearRequests()
    local success = friends:refresh()
    
    assert(success, "Should successfully start refresh")
    assert(friends.state == "syncing", "Should be in syncing state")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    return true
end

local function testFriendsRefreshResponse()
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    -- Simulate successful refresh response
    local responseJson = '{"protocolVersion":"2.0.0","type":"FriendsListResponse","success":true,"payload":{"friends":[{"name":"Friend1","friendedAs":"Friend1"}],"serverTime":1234567890}}'
    
    friends:refresh()
    local requests = deps.net.getRequests()
    assert(#requests == 1, "Should have one request")
    
    -- Call the callback with success
    requests[1].callback(true, responseJson)
    
    assert(friends.state == "idle", "Should be in idle state after success")
    assert(friends.lastError == nil, "Should have no error after success")
    assert(#friends:getFriends() == 1, "Should have one friend after refresh")
    
    return true
end

local function testFriendsRefreshError()
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    friends:refresh()
    local requests = deps.net.getRequests()
    
    -- Simulate network error
    requests[1].callback(false, "Network error")
    
    assert(friends.state == "error", "Should be in error state")
    assert(friends.lastError ~= nil, "Should have error")
    assert(friends.lastError.type == "NetworkError", "Should have NetworkError type")
    
    return true
end

local function testFriendsAddFriend()
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    deps.net.clearRequests()
    local success = friends:addFriend("NewFriend")
    
    assert(success, "Should successfully start add friend")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    return true
end

local function testFriendsRemoveFriend()
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    deps.net.clearRequests()
    local success = friends:removeFriend("Friend1")
    
    assert(success, "Should successfully start remove friend")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    return true
end

local function runTests()
    local tests = {
        testFriendsInitialState,
        testFriendsRefresh,
        testFriendsRefreshResponse,
        testFriendsRefreshError,
        testFriendsAddFriend,
        testFriendsRemoveFriend
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
    
    print(string.format("FriendsTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

