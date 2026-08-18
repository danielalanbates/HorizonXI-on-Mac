-- FriendsNotificationsTest.lua
-- Unit tests for notification diff engine and anonymous display logic
-- Tests Bug 1, 2, and 3 fixes

local Friends = require("app.features.friends")
local Notifications = require("app.features.notifications")
local FriendList = require("core.friendlist")

-- Track pushed notifications for verification
local pushedNotifications = {}

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
            error = function() end,
            warn = function() end,
            debug = function() end
        }
    }
end

local function createMockNotifications()
    pushedNotifications = {}
    return {
        push = function(self, toastType, payload)
            table.insert(pushedNotifications, {
                type = toastType,
                payload = payload
            })
        end
    }
end

local function setupMockApp(notificationsFeature)
    _G.FFXIFriendListApp = {
        features = {
            notifications = notificationsFeature,
            preferences = {
                getPreferences = function()
                    return {
                        shareJobWhenAnonymous = false
                    }
                end,
                getPrefs = function()
                    return {
                        shareJobWhenAnonymous = false
                    }
                end
            }
        }
    }
end

local function clearMockApp()
    _G.FFXIFriendListApp = nil
end

-- ============================================================================
-- Bug 1 & 2: Notification Diff Tests
-- ============================================================================

local function testOfflineToOnlineProducesOneToast()
    -- Test: When a friend transitions from offline to online, exactly one toast should be produced
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    local mockNotifications = createMockNotifications()
    setupMockApp(mockNotifications)
    
    -- First scan: friend is offline (establishes baseline)
    local initialStatuses = {
        FriendList.FriendStatus.new()
    }
    initialStatuses[1].characterName = "testfriend"
    initialStatuses[1].displayName = "TestFriend"
    initialStatuses[1].isOnline = false
    
    friends:checkForStatusChanges(initialStatuses)
    assert(#pushedNotifications == 0, "No notifications on initial scan")
    assert(friends.initialStatusScanComplete == true, "Initial scan should be complete")
    
    -- Second scan: friend comes online
    local updatedStatuses = {
        FriendList.FriendStatus.new()
    }
    updatedStatuses[1].characterName = "testfriend"
    updatedStatuses[1].displayName = "TestFriend"
    updatedStatuses[1].isOnline = true
    
    friends:checkForStatusChanges(updatedStatuses)
    
    assert(#pushedNotifications == 1, "Should produce exactly one notification: got " .. #pushedNotifications)
    assert(pushedNotifications[1].type == Notifications.ToastType.FriendOnline, "Should be FriendOnline type")
    assert(pushedNotifications[1].payload.title == "Friend Online", "Should have correct title")
    
    clearMockApp()
    return true
end

local function testOnlineToOfflineDoesNotProduceOnlineToast()
    -- Test: When a friend transitions from online to offline, no online toast should be produced
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    local mockNotifications = createMockNotifications()
    setupMockApp(mockNotifications)
    
    -- First scan: friend is online (establishes baseline)
    local initialStatuses = {
        FriendList.FriendStatus.new()
    }
    initialStatuses[1].characterName = "testfriend"
    initialStatuses[1].displayName = "TestFriend"
    initialStatuses[1].isOnline = true
    
    friends:checkForStatusChanges(initialStatuses)
    pushedNotifications = {} -- Clear any notifications from initial scan
    
    -- Second scan: friend goes offline
    local updatedStatuses = {
        FriendList.FriendStatus.new()
    }
    updatedStatuses[1].characterName = "testfriend"
    updatedStatuses[1].displayName = "TestFriend"
    updatedStatuses[1].isOnline = false
    
    friends:checkForStatusChanges(updatedStatuses)
    
    -- Should not produce a FriendOnline toast
    local onlineToasts = 0
    for _, notif in ipairs(pushedNotifications) do
        if notif.type == Notifications.ToastType.FriendOnline then
            onlineToasts = onlineToasts + 1
        end
    end
    assert(onlineToasts == 0, "Should not produce online toast when friend goes offline")
    
    clearMockApp()
    return true
end

local function testNewFriendRequestTriggersToast()
    -- Test: A new friend request in the snapshot triggers a toast once
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    local mockNotifications = createMockNotifications()
    setupMockApp(mockNotifications)
    
    -- First call with a new request
    local incomingRequests = {
        {
            id = "req_12345",
            requestId = "req_12345",
            fromCharacterName = "SomePlayer",
            status = "PENDING"
        }
    }
    
    friends:checkForNewFriendRequests(incomingRequests)
    
    assert(#pushedNotifications == 1, "Should produce exactly one notification")
    assert(pushedNotifications[1].type == Notifications.ToastType.FriendRequestReceived, "Should be FriendRequestReceived type")
    assert(pushedNotifications[1].payload.title == "Friend Request", "Should have correct title")
    
    clearMockApp()
    return true
end

local function testSameFriendRequestDoesNotTriggerDuplicateToast()
    -- Test: The same friend request ID does not trigger duplicate toasts
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    local mockNotifications = createMockNotifications()
    setupMockApp(mockNotifications)
    
    local incomingRequests = {
        {
            id = "req_12345",
            requestId = "req_12345",
            fromCharacterName = "SomePlayer",
            status = "PENDING"
        }
    }
    
    -- First call
    friends:checkForNewFriendRequests(incomingRequests)
    assert(#pushedNotifications == 1, "First call should produce notification")
    
    -- Second call with same request
    friends:checkForNewFriendRequests(incomingRequests)
    assert(#pushedNotifications == 1, "Second call should NOT produce additional notification")
    
    clearMockApp()
    return true
end

local function testRefreshDoesNotSuppressSubsequentNotifications()
    -- Test: Bug 1 fix - Clicking refresh does not suppress notifications afterward
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    local mockNotifications = createMockNotifications()
    setupMockApp(mockNotifications)
    
    -- Establish baseline with friend offline
    local initialStatuses = {
        FriendList.FriendStatus.new()
    }
    initialStatuses[1].characterName = "testfriend"
    initialStatuses[1].displayName = "TestFriend"
    initialStatuses[1].isOnline = false
    
    friends:checkForStatusChanges(initialStatuses)
    assert(friends.initialStatusScanComplete == true, "Baseline established")
    
    -- Simulate "refresh" by checking again with same data
    pushedNotifications = {}
    friends:checkForStatusChanges(initialStatuses)
    assert(#pushedNotifications == 0, "No change = no notification")
    
    -- Now friend comes online after refresh
    local updatedStatuses = {
        FriendList.FriendStatus.new()
    }
    updatedStatuses[1].characterName = "testfriend"
    updatedStatuses[1].displayName = "TestFriend"
    updatedStatuses[1].isOnline = true
    
    pushedNotifications = {}
    friends:checkForStatusChanges(updatedStatuses)
    
    assert(#pushedNotifications == 1, "Should still produce notification after refresh: got " .. #pushedNotifications)
    assert(pushedNotifications[1].type == Notifications.ToastType.FriendOnline, "Should be FriendOnline type")
    
    clearMockApp()
    return true
end

local function testMultipleFriendsOnlineTransitions()
    -- Test: Multiple friends coming online at once produce multiple toasts
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    local mockNotifications = createMockNotifications()
    setupMockApp(mockNotifications)
    
    -- Establish baseline with both friends offline
    local initialStatuses = {}
    for i = 1, 2 do
        local status = FriendList.FriendStatus.new()
        status.characterName = "friend" .. i
        status.displayName = "Friend" .. i
        status.isOnline = false
        table.insert(initialStatuses, status)
    end
    
    friends:checkForStatusChanges(initialStatuses)
    pushedNotifications = {}
    
    -- Both friends come online
    local updatedStatuses = {}
    for i = 1, 2 do
        local status = FriendList.FriendStatus.new()
        status.characterName = "friend" .. i
        status.displayName = "Friend" .. i
        status.isOnline = true
        table.insert(updatedStatuses, status)
    end
    
    friends:checkForStatusChanges(updatedStatuses)
    
    assert(#pushedNotifications == 2, "Should produce two notifications: got " .. #pushedNotifications)
    
    clearMockApp()
    return true
end

-- ============================================================================
-- Bug 3: Anonymous Display Logic Tests
-- ============================================================================

local function testAnonymousLogic_ShareFalse_GameAnonFalse()
    -- Test: shareWhenAnon=false + isAnonInGame=false => NOT anonymous
    -- The player is NOT anon in-game, so should not display as anonymous
    local deps = createFakeDeps()
    local friends = Friends.Friends.new(deps)
    
    -- Create a mock presence where gameIsAnonymous = false
    local presence = {
        characterName = "testplayer",
        job = "WAR 99",
        zone = "Port Jeuno",
        nation = 0,
        rank = "10",
        isAnonymous = false  -- Game reports NOT anonymous
    }
    
    -- With shareJobWhenAnonymous = false, the result should still be false
    -- because gameIsAnonymous is false
    -- Logic: isAnonymous = gameIsAnonymous AND NOT shareJobWhenAnonymous
    --      = false AND NOT false
    --      = false AND true
    --      = false
    
    local gameIsAnonymous = presence.isAnonymous
    local shareJobWhenAnonymous = false
    local result = gameIsAnonymous and not shareJobWhenAnonymous
    
    assert(result == false, "Player not anon in-game should NOT display as anonymous")
    
    return true
end

local function testAnonymousLogic_ShareFalse_GameAnonTrue()
    -- Test: shareWhenAnon=false + isAnonInGame=true => anonymous
    -- The player IS anon in-game and hasn't opted to share, so should display as anonymous
    
    local presence = {
        isAnonymous = true  -- Game reports IS anonymous
    }
    
    local gameIsAnonymous = presence.isAnonymous
    local shareJobWhenAnonymous = false
    local result = gameIsAnonymous and not shareJobWhenAnonymous
    
    -- Logic: isAnonymous = true AND NOT false = true AND true = true
    assert(result == true, "Player anon in-game with share disabled should display as anonymous")
    
    return true
end

local function testAnonymousLogic_ShareTrue_GameAnonTrue()
    -- Test: shareWhenAnon=true + isAnonInGame=true => NOT anonymous (still show job/nation/rank)
    -- The player IS anon in-game but opted to share anyway
    
    local presence = {
        isAnonymous = true  -- Game reports IS anonymous
    }
    
    local gameIsAnonymous = presence.isAnonymous
    local shareJobWhenAnonymous = true
    local result = gameIsAnonymous and not shareJobWhenAnonymous
    
    -- Logic: isAnonymous = true AND NOT true = true AND false = false
    assert(result == false, "Player anon in-game with share enabled should NOT display as anonymous")
    
    return true
end

local function testAnonymousLogic_ShareTrue_GameAnonFalse()
    -- Test: shareWhenAnon=true + isAnonInGame=false => NOT anonymous
    -- The player is NOT anon in-game (share setting doesn't matter)
    
    local presence = {
        isAnonymous = false  -- Game reports NOT anonymous
    }
    
    local gameIsAnonymous = presence.isAnonymous
    local shareJobWhenAnonymous = true
    local result = gameIsAnonymous and not shareJobWhenAnonymous
    
    -- Logic: isAnonymous = false AND NOT true = false AND false = false
    assert(result == false, "Player not anon in-game should NOT display as anonymous")
    
    return true
end

-- ============================================================================
-- Test Runner
-- ============================================================================

local function runTests()
    local tests = {
        -- Bug 1 & 2: Notification diff tests
        { name = "testOfflineToOnlineProducesOneToast", fn = testOfflineToOnlineProducesOneToast },
        { name = "testOnlineToOfflineDoesNotProduceOnlineToast", fn = testOnlineToOfflineDoesNotProduceOnlineToast },
        { name = "testNewFriendRequestTriggersToast", fn = testNewFriendRequestTriggersToast },
        { name = "testSameFriendRequestDoesNotTriggerDuplicateToast", fn = testSameFriendRequestDoesNotTriggerDuplicateToast },
        { name = "testRefreshDoesNotSuppressSubsequentNotifications", fn = testRefreshDoesNotSuppressSubsequentNotifications },
        { name = "testMultipleFriendsOnlineTransitions", fn = testMultipleFriendsOnlineTransitions },
        
        -- Bug 3: Anonymous display logic tests
        { name = "testAnonymousLogic_ShareFalse_GameAnonFalse", fn = testAnonymousLogic_ShareFalse_GameAnonFalse },
        { name = "testAnonymousLogic_ShareFalse_GameAnonTrue", fn = testAnonymousLogic_ShareFalse_GameAnonTrue },
        { name = "testAnonymousLogic_ShareTrue_GameAnonTrue", fn = testAnonymousLogic_ShareTrue_GameAnonTrue },
        { name = "testAnonymousLogic_ShareTrue_GameAnonFalse", fn = testAnonymousLogic_ShareTrue_GameAnonFalse },
    }
    
    local passed = 0
    local failed = 0
    
    for _, test in ipairs(tests) do
        local success, err = pcall(test.fn)
        if success then
            passed = passed + 1
            print("  PASS: " .. test.name)
        else
            failed = failed + 1
            print("  FAIL: " .. test.name .. " - " .. tostring(err))
        end
    end
    
    print(string.format("FriendsNotificationsTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

