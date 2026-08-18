-- ProtocolVersionTest.lua
-- Test version parsing, comparison, compatibility

local ProtocolVersion = require("protocol.ProtocolVersion")

local function assert(condition, message)
    if not condition then
        error("ASSERTION FAILED: " .. (message or "unknown"))
    end
end

local function testVersionParse()
    local v = ProtocolVersion.Version.parse("2.0.0")
    assert(v ~= nil, "Should parse valid version")
    assert(v.major == 2, "Major should be 2")
    assert(v.minor == 0, "Minor should be 0")
    assert(v.patch == 0, "Patch should be 0")
    print("✓ testVersionParse passed")
end

local function testVersionParseInvalid()
    local v = ProtocolVersion.Version.parse("invalid")
    assert(v == nil, "Should reject invalid version")
    print("✓ testVersionParseInvalid passed")
end

local function testVersionToString()
    local v = ProtocolVersion.Version.new(2, 1, 3)
    assert(v:toString() == "2.1.3", "Should format version string")
    print("✓ testVersionToString passed")
end

local function testVersionComparison()
    local v1 = ProtocolVersion.Version.new(2, 0, 0)
    local v2 = ProtocolVersion.Version.new(2, 0, 0)
    local v3 = ProtocolVersion.Version.new(2, 1, 0)
    
    assert(v1 == v2, "Equal versions should compare equal")
    assert(v1 < v3, "v1 should be less than v3")
    assert(v3 > v1, "v3 should be greater than v1")
    print("✓ testVersionComparison passed")
end

local function testVersionCompatibility()
    local current = ProtocolVersion.getCurrentVersion()
    local compatible = ProtocolVersion.Version.parse("2.0.0")
    local incompatible = ProtocolVersion.Version.parse("1.0.0")
    
    assert(compatible:isCompatibleWith(current), "Same major version should be compatible")
    assert(not incompatible:isCompatibleWith(current), "Different major version should be incompatible")
    print("✓ testVersionCompatibility passed")
end

local function runAllTests()
    print("Running ProtocolVersion tests...")
    testVersionParse()
    testVersionParseInvalid()
    testVersionToString()
    testVersionComparison()
    testVersionCompatibility()
    print("All ProtocolVersion tests passed!")
end

if arg and arg[0] and arg[0]:match("ProtocolVersionTest") then
    runAllTests()
end

return {
    runAllTests = runAllTests
}

