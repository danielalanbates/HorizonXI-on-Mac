local addonPath = string.match(debug.getinfo(1, "S").source:sub(2), "(.*[/\\])")
if addonPath then
    package.path = addonPath .. "../?.lua;" .. addonPath .. "../?/init.lua;" .. package.path
end

print("Running UI Unit Tests...")
print("=" .. string.rep("=", 50))

local tests = {
    require("tests.ui.RequestsTabTest"),
}

local totalPassed = 0
local totalFailed = 0

for _, testModule in ipairs(tests) do
    print("")
    local success = testModule.run()
    if success then
        totalPassed = totalPassed + 1
    else
        totalFailed = totalFailed + 1
    end
end

print("")
print("=" .. string.rep("=", 50))
print(string.format("Total: %d test suites passed, %d failed", totalPassed, totalFailed))

if totalFailed == 0 then
    print("All tests passed!")
    return true
else
    print("Some tests failed!")
    return false
end

