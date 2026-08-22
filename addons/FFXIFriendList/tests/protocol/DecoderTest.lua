-- DecoderTest.lua
-- Test individual payload decoders
-- NOTE: Heartbeat decoder removed - heartbeat response is now ignored per migration plan

local FriendsListDecoder = require("protocol.Decoders.FriendsList")
local PreferencesDecoder = require("protocol.Decoders.Preferences")
local BlockedAccountsDecoder = require("protocol.Decoders.BlockedAccounts")

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function testFriendsListDecoder()
    local payload = {
        friends = {{name = "Friend1"}, {name = "Friend2"}},
        serverTime = 1234567890
    }
    
    local ok, result = FriendsListDecoder.decode(payload)
    assert(ok, "Should decode valid payload")
    assert(#result.friends == 2, "Should decode friends array")
    assert(result.serverTime == 1234567890, "Should decode serverTime")
    print("✓ testFriendsListDecoder passed")
end

local function testFriendsListDecoderMissingFields()
    local payload = {}
    
    local ok, result = FriendsListDecoder.decode(payload)
    assert(ok, "Should decode even with missing fields")
    assert(type(result.friends) == "table", "Should default friends to empty table")
    assert(result.serverTime == 0, "Should default serverTime to 0")
    print("✓ testFriendsListDecoderMissingFields passed")
end

local function testPreferencesDecoder()
    local payload = {
        preferences = {useServerNotes = true},
        privacy = {shareLocation = false}
    }
    
    local ok, result = PreferencesDecoder.decode(payload)
    assert(ok, "Should decode valid payload")
    assert(result.preferences.useServerNotes == true, "Should decode preferences")
    assert(result.privacy.shareLocation == false, "Should decode privacy")
    print("✓ testPreferencesDecoder passed")
end

local function testDecoderInvalidPayload()
    local ok, errorMsg = FriendsListDecoder.decode("not a table")
    assert(not ok, "Should reject invalid payload type")
    assert(errorMsg:match("expected table"), "Should return appropriate error")
    print("✓ testDecoderInvalidPayload passed")
end

-- BlockedAccounts decoder tests for server compatibility
local function testBlockedAccountsDecoderWithCharacterName()
    -- Server returns 'characterName' but decoder should normalize to 'displayName'
    local payload = {
        blocked = {
            {accountId = "abc-123", characterName = "TestPlayer", blockedAt = "2024-01-01T00:00:00Z"},
            {accountId = "def-456", characterName = "AnotherPlayer", blockedAt = "2024-01-02T00:00:00Z"}
        },
        count = 2
    }
    
    local ok, result = BlockedAccountsDecoder.decode(payload)
    assert(ok, "Should decode valid payload")
    assert(#result.blocked == 2, "Should decode blocked array")
    assert(result.blocked[1].displayName == "TestPlayer", "Should normalize characterName to displayName")
    assert(result.blocked[2].displayName == "AnotherPlayer", "Should normalize characterName to displayName")
    assert(result.blocked[1].accountId == "abc-123", "Should preserve accountId")
    print("✓ testBlockedAccountsDecoderWithCharacterName passed")
end

local function testBlockedAccountsDecoderFallbackToDisplayName()
    -- Legacy format with displayName should still work
    local payload = {
        blocked = {
            {accountId = "abc-123", displayName = "LegacyPlayer", blockedAt = "2024-01-01T00:00:00Z"}
        }
    }
    
    local ok, result = BlockedAccountsDecoder.decode(payload)
    assert(ok, "Should decode legacy payload")
    assert(result.blocked[1].displayName == "LegacyPlayer", "Should use displayName if characterName not present")
    print("✓ testBlockedAccountsDecoderFallbackToDisplayName passed")
end

local function testBlockedAccountsDecoderMissingName()
    -- Missing both characterName and displayName
    local payload = {
        blocked = {
            {accountId = "abc-123", blockedAt = "2024-01-01T00:00:00Z"}
        }
    }
    
    local ok, result = BlockedAccountsDecoder.decode(payload)
    assert(ok, "Should decode even with missing name")
    assert(result.blocked[1].displayName == "Unknown", "Should default to 'Unknown' if no name")
    print("✓ testBlockedAccountsDecoderMissingName passed")
end

local function runAllTests()
    print("Running Decoder tests...")
    testFriendsListDecoder()
    testFriendsListDecoderMissingFields()
    testPreferencesDecoder()
    testDecoderInvalidPayload()
    testBlockedAccountsDecoderWithCharacterName()
    testBlockedAccountsDecoderFallbackToDisplayName()
    testBlockedAccountsDecoderMissingName()
    print("All Decoder tests passed!")
end

if arg and arg[0] and arg[0]:match("DecoderTest") then
    runAllTests()
end

return {
    runAllTests = runAllTests
}

