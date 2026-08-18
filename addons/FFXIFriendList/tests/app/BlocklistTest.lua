-- BlocklistTest.lua
-- Unit tests for app/features/blocklist.lua

local Blocklist = require("app.features.blocklist")

local function createFakeDeps()
    local requests = {}
    local time = 1000
    
    return {
        net = {
            request = function(req)
                table.insert(requests, req)
                return #requests
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
            warn = function() end,
            debug = function() end,
            error = function() end
        }
    }
end

local function testBlocklistInitialState()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    assert(#blocklist:getBlockedList() == 0, "Should have no blocked players initially")
    assert(blocklist:getBlockedCount() == 0, "Count should be 0 initially")
    assert(blocklist.isLoading == false, "Should not be loading initially")
    assert(blocklist.lastError == nil, "Should have no error initially")
    
    return true
end

local function testBlocklistGetState()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    local state = blocklist:getState()
    
    assert(state.blocked ~= nil, "State should include blocked list")
    assert(state.isLoading ~= nil, "State should include isLoading")
    assert(state.lastError == nil, "State should include lastError")
    assert(state.lastUpdateTime ~= nil, "State should include lastUpdateTime")
    
    return true
end

local function testBlocklistIsBlocked()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    blocklist.blocked = {
        { accountId = 123, displayName = "BlockedPlayer1" },
        { accountId = 456, displayName = "BlockedPlayer2" }
    }
    blocklist.blockedByAccountId = { [123] = true, [456] = true }
    
    assert(blocklist:isBlocked(123), "Should return true for blocked account")
    assert(blocklist:isBlocked(456), "Should return true for blocked account")
    assert(not blocklist:isBlocked(789), "Should return false for unblocked account")
    
    return true
end

local function testBlocklistFindByName()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    blocklist.blocked = {
        { accountId = 123, displayName = "Player1" },
        { accountId = 456, displayName = "Player2" }
    }
    
    local found = blocklist:findByName("player1")
    assert(found ~= nil, "Should find player by name (case insensitive)")
    assert(found.accountId == 123, "Should return correct account ID")
    
    local notFound = blocklist:findByName("nonexistent")
    assert(notFound == nil, "Should return nil for unknown player")
    
    return true
end

local function testBlocklistRefresh()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    deps.net.clearRequests()
    local success = blocklist:refresh()
    
    assert(success, "Should successfully start refresh")
    assert(blocklist.isLoading, "Should be loading")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    local req = deps.net.getRequests()[1]
    assert(req.method == "GET", "Should use GET method")
    assert(string.find(req.url, "/api/blocked"), "Should call blocked endpoint")
    
    return true
end

local function testBlocklistRefreshResponse()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    local responseJson = '{"protocolVersion":"2.0.0","type":"BlockedAccountsResponse","success":true,"blocked":[{"accountId":123,"displayName":"Player1","blockedAt":1234567890}],"count":1}'
    
    blocklist:refresh()
    local requests = deps.net.getRequests()
    
    requests[1].callback(true, responseJson)
    
    assert(not blocklist.isLoading, "Should not be loading after response")
    assert(blocklist.lastError == nil, "Should have no error after success")
    assert(#blocklist:getBlockedList() == 1, "Should have one blocked player")
    assert(blocklist:isBlocked(123), "Should have accountId 123 blocked")
    
    return true
end

local function testBlocklistBlock()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    deps.net.clearRequests()
    local success = blocklist:block("targetplayer", function() end)
    
    assert(success, "Should start block request")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    local req = deps.net.getRequests()[1]
    assert(req.method == "POST", "Should use POST method")
    assert(string.find(req.url, "/api/block"), "Should call block endpoint")
    assert(string.find(req.body, "targetplayer"), "Should include target name in body")
    
    return true
end

local function testBlocklistUnblock()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    deps.net.clearRequests()
    local success = blocklist:unblock(123, function() end)
    
    assert(success, "Should start unblock request")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    local req = deps.net.getRequests()[1]
    assert(req.method == "DELETE", "Should use DELETE method")
    assert(string.find(req.url, "/api/block/123"), "Should call unblock endpoint with accountId")
    
    return true
end

local function testBlocklistUnblockByName()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    blocklist.blocked = {
        { accountId = 123, displayName = "Player1" }
    }
    blocklist.blockedByAccountId = { [123] = true }
    
    deps.net.clearRequests()
    local success = blocklist:unblockByName("player1", function() end)
    
    assert(success, "Should start unblock request")
    assert(#deps.net.getRequests() == 1, "Should have made one request")
    
    local req = deps.net.getRequests()[1]
    assert(string.find(req.url, "123"), "Should use account ID from lookup")
    
    return true
end

local function testBlocklistUnblockByNameNotFound()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    blocklist.blocked = {}
    blocklist.blockedByAccountId = {}
    
    local callbackCalled = false
    local callbackSuccess = true
    
    deps.net.clearRequests()
    local success = blocklist:unblockByName("nonexistent", function(s, err)
        callbackCalled = true
        callbackSuccess = s
    end)
    
    assert(not success, "Should return false for unknown player")
    assert(callbackCalled, "Should call callback")
    assert(not callbackSuccess, "Callback should indicate failure")
    assert(#deps.net.getRequests() == 0, "Should not make request for unknown player")
    
    return true
end

local function testBlocklistRefreshSkipsDuplicateRequest()
    local deps = createFakeDeps()
    local blocklist = Blocklist.Blocklist.new(deps)
    
    deps.net.clearRequests()
    
    local success1 = blocklist:refresh()
    local success2 = blocklist:refresh()
    
    assert(success1, "First refresh should succeed")
    assert(not success2, "Second refresh should be skipped")
    assert(#deps.net.getRequests() == 1, "Should only make one request")
    
    return true
end

local function testBlocklistNotConnected()
    local deps = createFakeDeps()
    deps.connection.isConnected = function() return false end
    
    local blocklist = Blocklist.Blocklist.new(deps)
    
    deps.net.clearRequests()
    local success = blocklist:refresh()
    
    assert(not success, "Should fail when not connected")
    assert(#deps.net.getRequests() == 0, "Should not make request when not connected")
    
    return true
end

-- Run all tests
local tests = {
    { name = "Initial state", fn = testBlocklistInitialState },
    { name = "Get state", fn = testBlocklistGetState },
    { name = "Is blocked", fn = testBlocklistIsBlocked },
    { name = "Find by name", fn = testBlocklistFindByName },
    { name = "Refresh", fn = testBlocklistRefresh },
    { name = "Refresh response", fn = testBlocklistRefreshResponse },
    { name = "Block", fn = testBlocklistBlock },
    { name = "Unblock", fn = testBlocklistUnblock },
    { name = "Unblock by name", fn = testBlocklistUnblockByName },
    { name = "Unblock by name not found", fn = testBlocklistUnblockByNameNotFound },
    { name = "Refresh skips duplicate", fn = testBlocklistRefreshSkipsDuplicateRequest },
    { name = "Not connected", fn = testBlocklistNotConnected }
}

local passed = 0
local failed = 0

for _, test in ipairs(tests) do
    local success, err = pcall(test.fn)
    if success then
        print("[PASS] " .. test.name)
        passed = passed + 1
    else
        print("[FAIL] " .. test.name .. ": " .. tostring(err))
        failed = failed + 1
    end
end

print(string.format("\nBlocklist tests: %d passed, %d failed", passed, failed))

return {
    passed = passed,
    failed = failed,
    total = #tests
}

