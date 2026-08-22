-- JsonTest.lua
-- Test JSON encode/decode

local Json = require("protocol.Json")

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function testJsonEncodeDecode()
    local original = {
        name = "Test",
        value = 123,
        nested = {
            array = {1, 2, 3},
            bool = true
        }
    }
    
    local encoded = Json.encode(original)
    assert(type(encoded) == "string", "Encode should return string")
    
    local ok, decoded = Json.decode(encoded)
    assert(ok, "Decode should succeed")
    assert(decoded.name == "Test", "Should decode name")
    assert(decoded.value == 123, "Should decode value")
    assert(decoded.nested.bool == true, "Should decode nested bool")
    assert(#decoded.nested.array == 3, "Should decode array")
    print("✓ testJsonEncodeDecode passed")
end

local function testJsonDecodeInvalid()
    local ok, errorMsg = Json.decode("{ invalid json }")
    assert(not ok, "Should reject invalid JSON")
    assert(type(errorMsg) == "string", "Should return error message")
    print("✓ testJsonDecodeInvalid passed")
end

local function testJsonDecodeEmpty()
    local ok, errorMsg = Json.decode("")
    assert(not ok, "Should reject empty string")
    print("✓ testJsonDecodeEmpty passed")
end

local function testJsonEncodeNull()
    local encoded = Json.encode(nil)
    assert(encoded == "null", "Should encode nil as null")
    print("✓ testJsonEncodeNull passed")
end

local function runAllTests()
    print("Running Json tests...")
    testJsonEncodeDecode()
    testJsonDecodeInvalid()
    testJsonDecodeEmpty()
    testJsonEncodeNull()
    print("All Json tests passed!")
end

if arg and arg[0] and arg[0]:match("JsonTest") then
    runAllTests()
end

return {
    runAllTests = runAllTests
}

