-- EnvelopeTest.lua
-- Test envelope decoding and validation (payload-only mode)

local Envelope = require("protocol.Envelope")
local ProtocolVersion = require("protocol.ProtocolVersion")
local Json = require("protocol.Json")

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function testEnvelopeDecodeValid()
    local jsonStr = Json.encode({
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = "FriendsListResponse",
        success = true,
        payload = {
            friends = {},
            serverTime = 1234567890
        }
    })
    
    local ok, envelope = Envelope.decode(jsonStr)
    assert(ok, "Should decode valid envelope")
    assert(envelope.protocolVersion == ProtocolVersion.PROTOCOL_VERSION, "Protocol version should match")
    assert(envelope.type == "FriendsListResponse", "Type should match")
    assert(envelope.success == true, "Success should be true")
    assert(type(envelope.payload) == "table", "Payload should be table")
    assert(envelope.payload.friends ~= nil, "Payload should contain friends")
    print("✓ testEnvelopeDecodeValid passed")
end

local function testEnvelopeDecodeMissingPayload()
    local jsonStr = Json.encode({
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = "FriendsListResponse",
        success = true
        -- Missing payload
    })
    
    local ok, errorType, errorMsg = Envelope.decode(jsonStr)
    assert(not ok, "Should reject missing payload")
    assert(errorType == Envelope.DecodeError.MissingPayload, "Should return MissingPayload error")
    print("✓ testEnvelopeDecodeMissingPayload passed")
end

local function testEnvelopeDecodeInvalidJson()
    local jsonStr = "{ invalid json }"
    
    local ok, errorType, errorMsg = Envelope.decode(jsonStr)
    assert(not ok, "Should reject invalid JSON")
    assert(errorType == Envelope.DecodeError.InvalidJson, "Should return InvalidJson error")
    print("✓ testEnvelopeDecodeInvalidJson passed")
end

local function testEnvelopeDecodeMissingProtocolVersion()
    local jsonStr = Json.encode({
        type = "FriendsListResponse",
        success = true,
        payload = {}
    })
    
    local ok, errorType, errorMsg = Envelope.decode(jsonStr)
    assert(not ok, "Should reject missing protocolVersion")
    assert(errorType == Envelope.DecodeError.MissingProtocolVersion, "Should return MissingProtocolVersion error")
    print("✓ testEnvelopeDecodeMissingProtocolVersion passed")
end

local function testEnvelopeDecodeMissingType()
    local jsonStr = Json.encode({
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        success = true,
        payload = {}
    })
    
    local ok, errorType, errorMsg = Envelope.decode(jsonStr)
    assert(not ok, "Should reject missing type")
    assert(errorType == Envelope.DecodeError.MissingType, "Should return MissingType error")
    print("✓ testEnvelopeDecodeMissingType passed")
end

local function testEnvelopeDecodeMissingSuccess()
    local jsonStr = Json.encode({
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = "FriendsListResponse",
        payload = {}
    })
    
    local ok, errorType, errorMsg = Envelope.decode(jsonStr)
    assert(not ok, "Should reject missing success")
    assert(errorType == Envelope.DecodeError.MissingSuccess, "Should return MissingSuccess error")
    print("✓ testEnvelopeDecodeMissingSuccess passed")
end

local function testEnvelopeDecodeErrorResponse()
    local jsonStr = Json.encode({
        protocolVersion = ProtocolVersion.PROTOCOL_VERSION,
        type = "Error",
        success = false,
        error = "Test error",
        errorCode = "TEST_ERROR",
        payload = {}
    })
    
    local ok, envelope = Envelope.decode(jsonStr)
    assert(ok, "Should decode error response")
    assert(envelope.success == false, "Success should be false")
    assert(envelope.error == "Test error", "Error message should match")
    assert(envelope.errorCode == "TEST_ERROR", "Error code should match")
    assert(type(envelope.payload) == "table", "Payload should be table (even if empty)")
    print("✓ testEnvelopeDecodeErrorResponse passed")
end

local function runAllTests()
    print("Running Envelope tests...")
    testEnvelopeDecodeValid()
    testEnvelopeDecodeMissingPayload()
    testEnvelopeDecodeInvalidJson()
    testEnvelopeDecodeMissingProtocolVersion()
    testEnvelopeDecodeMissingType()
    testEnvelopeDecodeMissingSuccess()
    testEnvelopeDecodeErrorResponse()
    print("All Envelope tests passed!")
end

if arg and arg[0] and arg[0]:match("EnvelopeTest") then
    runAllTests()
end

return {
    runAllTests = runAllTests
}

