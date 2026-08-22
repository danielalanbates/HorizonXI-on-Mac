-- WsEnvelopeTest.lua
-- Unit tests for WebSocket envelope decoding
-- Tests the contract between server WS events and addon parsing

local WsEnvelope = require("protocol.WsEnvelope")
local Json = require("protocol.Json")

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s\nExpected: %s\nActual: %s", 
            message or "values not equal", 
            tostring(expected), 
            tostring(actual)))
    end
end

-- =============================================================================
-- Valid Event Parsing
-- =============================================================================

local function testDecodeConnectedEvent()
    local jsonStr = Json.encode({
        type = "connected",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 1,
        payload = {
            accountId = "test-account-id",
            characterName = "TestPlayer",
            realmId = "horizon"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode connected event")
    assertEq(event.type, "connected", "Type should be 'connected'")
    assertEq(event.seq, 1, "Seq should be 1")
    assertEq(event.payload.accountId, "test-account-id", "Account ID should match")
    assertEq(event.payload.characterName, "TestPlayer", "Character name should match")
    print("✓ testDecodeConnectedEvent passed")
end

local function testDecodeFriendsSnapshotEvent()
    local jsonStr = Json.encode({
        type = "friends_snapshot",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 2,
        payload = {
            friends = {
                {
                    accountId = "friend-1",
                    characterName = "FriendOne",
                    realmId = "horizon",
                    isOnline = true,
                    lastSeen = nil,
                    state = {
                        job = "WAR",
                        subJob = "MNK",
                        jobLevel = 75,
                        subJobLevel = 37,
                        zone = "Jeuno",
                        nation = "San d'Oria",
                        rank = 10,
                        isAnonymous = false
                    },
                    createdAt = "2024-01-01T00:00:00.000Z"
                }
            },
            pendingRequests = 3
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode friends_snapshot event")
    assertEq(event.type, "friends_snapshot", "Type should be 'friends_snapshot'")
    assert(event.payload.friends ~= nil, "Should have friends array")
    assertEq(#event.payload.friends, 1, "Should have one friend")
    assertEq(event.payload.friends[1].characterName, "FriendOne", "Friend name should match")
    assertEq(event.payload.friends[1].state.job, "WAR", "Friend job should match")
    assertEq(event.payload.pendingRequests, 3, "Pending requests count should match")
    print("✓ testDecodeFriendsSnapshotEvent passed")
end

local function testDecodeFriendOnlineEvent()
    local jsonStr = Json.encode({
        type = "friend_online",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 3,
        payload = {
            accountId = "friend-account",
            characterName = "OnlineFriend",
            realmId = "horizon",
            state = {
                job = "RDM",
                zone = "Windurst"
            }
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode friend_online event")
    assertEq(event.type, "friend_online", "Type should be 'friend_online'")
    assertEq(event.payload.characterName, "OnlineFriend", "Character name should match")
    assertEq(event.payload.state.job, "RDM", "Job should match")
    print("✓ testDecodeFriendOnlineEvent passed")
end

local function testDecodeFriendOfflineEvent()
    local jsonStr = Json.encode({
        type = "friend_offline",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 4,
        payload = {
            accountId = "friend-account",
            lastSeen = "2024-01-01T00:00:00.000Z"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode friend_offline event")
    assertEq(event.type, "friend_offline", "Type should be 'friend_offline'")
    assertEq(event.payload.accountId, "friend-account", "Account ID should match")
    assert(event.payload.lastSeen ~= nil, "Should have lastSeen timestamp")
    print("✓ testDecodeFriendOfflineEvent passed")
end

local function testDecodeFriendRequestReceivedEvent()
    local jsonStr = Json.encode({
        type = "friend_request_received",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 5,
        payload = {
            requestId = "request-uuid-123",
            fromAccountId = "requester-account",
            fromCharacterName = "RequesterPlayer",
            createdAt = "2024-01-01T00:00:00.000Z"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode friend_request_received event")
    assertEq(event.type, "friend_request_received", "Type should match")
    assertEq(event.payload.requestId, "request-uuid-123", "Request ID should match")
    assertEq(event.payload.fromCharacterName, "RequesterPlayer", "From character should match")
    print("✓ testDecodeFriendRequestReceivedEvent passed")
end

local function testDecodeBlockedEvent()
    local jsonStr = Json.encode({
        type = "blocked",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 6,
        payload = {
            blockedByAccountId = "blocker-account-id"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode blocked event")
    assertEq(event.type, "blocked", "Type should be 'blocked'")
    assertEq(event.payload.blockedByAccountId, "blocker-account-id", "Blocker ID should match")
    print("✓ testDecodeBlockedEvent passed")
end

local function testDecodeErrorEvent()
    local jsonStr = Json.encode({
        type = "error",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 7,
        payload = {
            code = "RATE_LIMITED",
            message = "Too many requests"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode error event")
    assertEq(event.type, "error", "Type should be 'error'")
    assertEq(event.payload.code, "RATE_LIMITED", "Error code should match")
    assertEq(event.payload.message, "Too many requests", "Error message should match")
    print("✓ testDecodeErrorEvent passed")
end

-- =============================================================================
-- Error Cases
-- =============================================================================

local function testDecodeEmptyMessage()
    local ok, errorCode, errorMsg = WsEnvelope.decode("")
    assert(not ok, "Should reject empty message")
    assertEq(errorCode, WsEnvelope.DecodeError.InvalidJson, "Should return InvalidJson error")
    print("✓ testDecodeEmptyMessage passed")
end

local function testDecodeNilMessage()
    local ok, errorCode, errorMsg = WsEnvelope.decode(nil)
    assert(not ok, "Should reject nil message")
    assertEq(errorCode, WsEnvelope.DecodeError.InvalidJson, "Should return InvalidJson error")
    print("✓ testDecodeNilMessage passed")
end

local function testDecodeInvalidJson()
    local ok, errorCode, errorMsg = WsEnvelope.decode("{ not valid json }")
    assert(not ok, "Should reject invalid JSON")
    assertEq(errorCode, WsEnvelope.DecodeError.InvalidJson, "Should return InvalidJson error")
    print("✓ testDecodeInvalidJson passed")
end

local function testDecodeMissingType()
    local jsonStr = Json.encode({
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 1,
        payload = {}
    })
    
    local ok, errorCode, errorMsg = WsEnvelope.decode(jsonStr)
    assert(not ok, "Should reject missing type")
    assertEq(errorCode, WsEnvelope.DecodeError.MissingType, "Should return MissingType error")
    print("✓ testDecodeMissingType passed")
end

local function testDecodeNonObjectType()
    local jsonStr = Json.encode({
        type = 123,  -- Should be string
        timestamp = "2024-01-01T00:00:00.000Z",
        payload = {}
    })
    
    local ok, errorCode, errorMsg = WsEnvelope.decode(jsonStr)
    assert(not ok, "Should reject non-string type")
    assertEq(errorCode, WsEnvelope.DecodeError.MissingType, "Should return MissingType error")
    print("✓ testDecodeNonObjectType passed")
end

-- =============================================================================
-- Edge Cases
-- =============================================================================

local function testDecodeWithOptionalRequestId()
    local jsonStr = Json.encode({
        type = "connected",
        timestamp = "2024-01-01T00:00:00.000Z",
        protocolVersion = "2.0.0",
        seq = 1,
        requestId = "original-request-123",
        payload = {
            accountId = "test"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode with requestId")
    assertEq(event.requestId, "original-request-123", "RequestId should be preserved")
    print("✓ testDecodeWithOptionalRequestId passed")
end

local function testDecodeWithMissingOptionalFields()
    local jsonStr = Json.encode({
        type = "connected",
        payload = {
            accountId = "test"
        }
    })
    
    local ok, event = WsEnvelope.decode(jsonStr)
    assert(ok, "Should decode with missing optional fields")
    assertEq(event.timestamp, "", "Timestamp should default to empty")
    assertEq(event.seq, 0, "Seq should default to 0")
    print("✓ testDecodeWithMissingOptionalFields passed")
end

local function testEventTypeConstants()
    -- Verify event type constants match server definitions
    assertEq(WsEnvelope.EventType.Connected, "connected", "Connected constant")
    assertEq(WsEnvelope.EventType.FriendsSnapshot, "friends_snapshot", "FriendsSnapshot constant")
    assertEq(WsEnvelope.EventType.FriendOnline, "friend_online", "FriendOnline constant")
    assertEq(WsEnvelope.EventType.FriendOffline, "friend_offline", "FriendOffline constant")
    assertEq(WsEnvelope.EventType.FriendStateChanged, "friend_state_changed", "FriendStateChanged constant")
    assertEq(WsEnvelope.EventType.FriendAdded, "friend_added", "FriendAdded constant")
    assertEq(WsEnvelope.EventType.FriendRemoved, "friend_removed", "FriendRemoved constant")
    assertEq(WsEnvelope.EventType.FriendRequestReceived, "friend_request_received", "FriendRequestReceived constant")
    assertEq(WsEnvelope.EventType.FriendRequestAccepted, "friend_request_accepted", "FriendRequestAccepted constant")
    assertEq(WsEnvelope.EventType.FriendRequestDeclined, "friend_request_declined", "FriendRequestDeclined constant")
    assertEq(WsEnvelope.EventType.Blocked, "blocked", "Blocked constant")
    assertEq(WsEnvelope.EventType.Unblocked, "unblocked", "Unblocked constant")
    assertEq(WsEnvelope.EventType.PreferencesUpdated, "preferences_updated", "PreferencesUpdated constant")
    assertEq(WsEnvelope.EventType.Error, "error", "Error constant")
    print("✓ testEventTypeConstants passed")
end

-- =============================================================================
-- Run All Tests
-- =============================================================================

local function runAllTests()
    print("Running WsEnvelope tests...")
    
    -- Valid events
    testDecodeConnectedEvent()
    testDecodeFriendsSnapshotEvent()
    testDecodeFriendOnlineEvent()
    testDecodeFriendOfflineEvent()
    testDecodeFriendRequestReceivedEvent()
    testDecodeBlockedEvent()
    testDecodeErrorEvent()
    
    -- Error cases
    testDecodeEmptyMessage()
    testDecodeNilMessage()
    testDecodeInvalidJson()
    testDecodeMissingType()
    testDecodeNonObjectType()
    
    -- Edge cases
    testDecodeWithOptionalRequestId()
    testDecodeWithMissingOptionalFields()
    testEventTypeConstants()
    
    print("All WsEnvelope tests passed!")
end

-- Run if executed directly
if arg and arg[0] and arg[0]:match("WsEnvelopeTest") then
    runAllTests()
end

return {
    runAllTests = runAllTests
}
