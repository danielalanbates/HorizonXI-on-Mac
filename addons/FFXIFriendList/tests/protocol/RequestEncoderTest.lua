-- RequestEncoderTest.lua
-- Test request encoding

local RequestEncoder = require("protocol.Encoding.RequestEncoder")
local MessageTypes = require("protocol.MessageTypes")
local Json = require("protocol.Json")

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function testEncodeGetFriendList()
    local encoded = RequestEncoder.encodeGetFriendList()
    assert(type(encoded) == "string", "Should return JSON string")
    
    local ok, decoded = Json.decode(encoded)
    assert(ok, "Should be valid JSON")
    assert(decoded.type == MessageTypes.RequestType.GetFriendList, "Should encode type")
    assert(decoded.protocolVersion ~= nil, "Should include protocol version")
    print("✓ testEncodeGetFriendList passed")
end

local function testEncodeSetFriendList()
    local friends = {
        {name = "Friend1", friendedAs = "Friend1"},
        {name = "Friend2"}
    }
    
    local encoded = RequestEncoder.encodeSetFriendList(friends)
    assert(type(encoded) == "string", "Should return JSON string")
    
    local ok, decoded = Json.decode(encoded)
    assert(ok, "Should be valid JSON")
    assert(decoded.type == MessageTypes.RequestType.SetFriendList, "Should encode type")
    
    local ok2, payload = Json.decode(decoded.payload)
    assert(ok2, "Payload should be valid JSON")
    assert(payload.statuses ~= nil, "Should include statuses")
    assert(#payload.statuses == 2, "Should encode all friends")
    print("✓ testEncodeSetFriendList passed")
end

local function testEncodeUpdatePresence()
    local presence = {
        characterName = "TestChar",
        job = "WAR",
        rank = "10",
        nation = 1,
        zone = "San d'Oria",
        isAnonymous = false,
        timestamp = 1234567890
    }
    
    local encoded = RequestEncoder.encodeUpdatePresence(presence)
    assert(type(encoded) == "string", "Should return JSON string")
    
    local ok, decoded = Json.decode(encoded)
    assert(ok, "Should be valid JSON")
    assert(decoded.type == MessageTypes.RequestType.UpdatePresence, "Should encode type")
    
    local ok2, payload = Json.decode(decoded.payload)
    assert(ok2, "Payload should be valid JSON")
    assert(payload.characterName == "TestChar", "Should encode characterName")
    assert(payload.job == "WAR", "Should encode job")
    print("✓ testEncodeUpdatePresence passed")
end

local function runAllTests()
    print("Running RequestEncoder tests...")
    testEncodeGetFriendList()
    testEncodeSetFriendList()
    testEncodeUpdatePresence()
    print("All RequestEncoder tests passed!")
end

if arg and arg[0] and arg[0]:match("RequestEncoderTest") then
    runAllTests()
end

return {
    runAllTests = runAllTests
}

