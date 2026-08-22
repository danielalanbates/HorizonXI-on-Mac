-- tests/core/nations_test.lua
-- Unit tests for core/nations.lua module

local nations = require('core.nations')

local M = {}

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", message or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(condition, message)
    if not condition then
        error(message or "Assertion failed: expected true")
    end
end

local function assertFalse(condition, message)
    if condition then
        error(message or "Assertion failed: expected false")
    end
end

-- Test getDisplayName with numeric IDs
function M.test_getDisplayName_numericIds()
    assertEquals(nations.getDisplayName(0), "San d'Oria", "Nation 0 should be San d'Oria")
    assertEquals(nations.getDisplayName(1), "Bastok", "Nation 1 should be Bastok")
    assertEquals(nations.getDisplayName(2), "Windurst", "Nation 2 should be Windurst")
end

-- Test getDisplayName with string values (from server)
function M.test_getDisplayName_stringValues()
    assertEquals(nations.getDisplayName("San d'Oria"), "San d'Oria", "String San d'Oria should map correctly")
    assertEquals(nations.getDisplayName("Bastok"), "Bastok", "String Bastok should map correctly")
    assertEquals(nations.getDisplayName("Windurst"), "Windurst", "String Windurst should map correctly")
end

-- Test getDisplayName with case-insensitive lookup
function M.test_getDisplayName_caseInsensitive()
    assertEquals(nations.getDisplayName("san d'oria"), "San d'Oria", "Lowercase should map to proper case")
    assertEquals(nations.getDisplayName("BASTOK"), "Bastok", "Uppercase should map correctly")
    assertEquals(nations.getDisplayName("windurst"), "Windurst", "Lowercase should map correctly")
end

-- Test getDisplayName with unknown/anonymous values
function M.test_getDisplayName_anonymous()
    assertEquals(nations.getDisplayName(nil), "Anonymous", "nil should return Anonymous")
    assertEquals(nations.getDisplayName(""), "Anonymous", "empty string should return Anonymous")
    assertEquals(nations.getDisplayName(-1), "Anonymous", "negative number should return Anonymous")
    assertEquals(nations.getDisplayName(99), "Anonymous", "unknown number should return Anonymous")
end

-- Test getDisplayName with custom default
function M.test_getDisplayName_customDefault()
    assertEquals(nations.getDisplayName(nil, "Unknown"), "Unknown", "nil with custom default")
    assertEquals(nations.getDisplayName("", "Hidden"), "Hidden", "empty string with custom default")
end

-- Test getIconName with numeric IDs
function M.test_getIconName_numericIds()
    assertEquals(nations.getIconName(0), "nation_sandoria", "Nation 0 icon")
    assertEquals(nations.getIconName(1), "nation_bastok", "Nation 1 icon")
    assertEquals(nations.getIconName(2), "nation_windurst", "Nation 2 icon")
end

-- Test getIconName with string values
function M.test_getIconName_stringValues()
    assertEquals(nations.getIconName("San d'Oria"), "nation_sandoria", "String San d'Oria icon")
    assertEquals(nations.getIconName("Bastok"), "nation_bastok", "String Bastok icon")
    assertEquals(nations.getIconName("Windurst"), "nation_windurst", "String Windurst icon")
end

-- Test getIconName with unknown values
function M.test_getIconName_unknown()
    assertEquals(nations.getIconName(nil), nil, "nil should return nil icon")
    assertEquals(nations.getIconName(""), nil, "empty string should return nil icon")
    assertEquals(nations.getIconName(-1), nil, "negative should return nil icon")
end

-- Test isKnown
function M.test_isKnown()
    assertTrue(nations.isKnown(0), "Nation 0 should be known")
    assertTrue(nations.isKnown("Bastok"), "Bastok should be known")
    assertFalse(nations.isKnown(nil), "nil should not be known")
    assertFalse(nations.isKnown(-1), "-1 should not be known")
end

-- Test isAnonymous
function M.test_isAnonymous()
    assertTrue(nations.isAnonymous(nil), "nil should be anonymous")
    assertTrue(nations.isAnonymous(""), "empty string should be anonymous")
    assertTrue(nations.isAnonymous(-1), "-1 should be anonymous")
    assertFalse(nations.isAnonymous(0), "Nation 0 should not be anonymous")
    assertFalse(nations.isAnonymous("Windurst"), "Windurst should not be anonymous")
end

-- Run all tests
function M.runAll()
    local tests = {
        "test_getDisplayName_numericIds",
        "test_getDisplayName_stringValues",
        "test_getDisplayName_caseInsensitive",
        "test_getDisplayName_anonymous",
        "test_getDisplayName_customDefault",
        "test_getIconName_numericIds",
        "test_getIconName_stringValues",
        "test_getIconName_unknown",
        "test_isKnown",
        "test_isAnonymous",
    }
    
    local passed = 0
    local failed = 0
    
    for _, testName in ipairs(tests) do
        local success, err = pcall(M[testName])
        if success then
            passed = passed + 1
            print(string.format("  [PASS] %s", testName))
        else
            failed = failed + 1
            print(string.format("  [FAIL] %s: %s", testName, tostring(err)))
        end
    end
    
    print(string.format("\nNations tests: %d passed, %d failed", passed, failed))
    return failed == 0
end

return M
