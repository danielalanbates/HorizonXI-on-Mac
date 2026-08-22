-- run_all_tests.lua
-- Run all app unit tests

local addonPath = string.match(debug.getinfo(1, "S").source:sub(2), "(.*[/\\])")
if addonPath then
    package.path = addonPath .. "../?.lua;" .. addonPath .. "../?/init.lua;" .. package.path
end

print("Running App Unit Tests...")
print("=" .. string.rep("=", 50))

local tests = {
    require("tests.app.ConnectionTest"),
    require("tests.app.FriendsTest"),
    require("tests.app.FriendsNotificationsTest"),
    require("tests.app.NotesTest"),
    require("tests.app.BlocklistTest"),
    require("tests.app.WsEventHandlerTest"),
    -- TODO: Add more tests:
    -- require("tests.app.ServerListTest"),
    -- require("tests.app.PreferencesTest"),
    -- require("tests.app.NotificationsTest"),
    -- require("tests.app.MailTest"),
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

