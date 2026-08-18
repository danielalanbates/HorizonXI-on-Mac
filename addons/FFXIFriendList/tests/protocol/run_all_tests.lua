-- run_all_tests.lua
-- Run all protocol tests

print("=" .. string.rep("=", 60))
print("Running Protocol Layer Tests")
print("=" .. string.rep("=", 60))
print()

local tests = {
    require("tests.protocol.JsonTest"),
    require("tests.protocol.ProtocolVersionTest"),
    require("tests.protocol.EnvelopeTest"),
    require("tests.protocol.DecoderTest"),
    require("tests.protocol.RequestEncoderTest"),
    require("tests.protocol.WsEnvelopeTest")
}

local passed = 0
local failed = 0

for i, test in ipairs(tests) do
    local success, err = pcall(function()
        test.runAllTests()
    end)
    
    if success then
        passed = passed + 1
    else
        failed = failed + 1
        print("ERROR: " .. tostring(err))
    end
    print()
end

print("=" .. string.rep("=", 60))
print(string.format("Tests: %d passed, %d failed", passed, failed))
print("=" .. string.rep("=", 60))

if failed > 0 then
    os.exit(1)
end

