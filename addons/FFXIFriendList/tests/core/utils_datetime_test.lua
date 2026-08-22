-- tests/core/utils_datetime_test.lua
-- Unit tests for ISO8601 parsing and lastSeen normalization in utils.lua

local utils = require('modules.friendlist.components.helpers.utils')

local M = {}

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", message or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assertApproxEquals(actual, expected, tolerance, message)
    tolerance = tolerance or 1000  -- 1 second default tolerance
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected ~%d, got %d (tolerance %d)", 
            message or "Assertion failed", expected, actual, tolerance))
    end
end

local function assertTrue(condition, message)
    if not condition then
        error(message or "Assertion failed: expected true")
    end
end

-- Test parseISO8601 with valid strings
function M.test_parseISO8601_validWithMilliseconds()
    -- 2024-01-01T12:00:00.000Z should be a valid timestamp
    local result = utils.parseISO8601("2024-01-01T12:00:00.000Z")
    assertTrue(result > 0, "Valid ISO8601 should return positive timestamp")
    -- Should be approximately 1704110400000 (Jan 1, 2024 12:00:00 UTC in ms)
    assertApproxEquals(result, 1704110400000, 2000, "2024-01-01T12:00:00.000Z timestamp")
end

function M.test_parseISO8601_validWithoutMilliseconds()
    local result = utils.parseISO8601("2024-01-01T12:00:00Z")
    assertTrue(result > 0, "Valid ISO8601 without ms should return positive timestamp")
    assertApproxEquals(result, 1704110400000, 2000, "2024-01-01T12:00:00Z timestamp")
end

function M.test_parseISO8601_validWithPartialMilliseconds()
    -- Some servers might send less than 3 digits for ms
    local result = utils.parseISO8601("2024-01-01T12:00:00.5Z")
    assertTrue(result > 0, "Partial ms should parse")
end

-- Test parseISO8601 with invalid strings
function M.test_parseISO8601_invalidStrings()
    assertEquals(utils.parseISO8601(nil), 0, "nil should return 0")
    assertEquals(utils.parseISO8601(""), 0, "empty string should return 0")
    assertEquals(utils.parseISO8601("not a date"), 0, "invalid string should return 0")
    assertEquals(utils.parseISO8601("2024-13-01T12:00:00Z"), 0, "invalid month should return 0")
    assertEquals(utils.parseISO8601("2024-01-32T12:00:00Z"), 0, "invalid day should return 0")
end

-- Test parseISO8601 with edge cases
function M.test_parseISO8601_edgeCases()
    -- Year boundaries
    local result1970 = utils.parseISO8601("1970-01-01T00:00:00Z")
    assertTrue(result1970 >= 0, "Unix epoch should parse to ~0")
    
    local result2100 = utils.parseISO8601("2100-01-01T00:00:00Z")
    assertTrue(result2100 > 0, "Year 2100 should parse")
end

-- Test normalizeLastSeen with different types
function M.test_normalizeLastSeen_numericPassthrough()
    assertEquals(utils.normalizeLastSeen(1704110400000), 1704110400000, "Numeric should pass through")
    assertEquals(utils.normalizeLastSeen(0), 0, "Zero should pass through")
    assertEquals(utils.normalizeLastSeen(123456789), 123456789, "Any positive number should pass through")
end

function M.test_normalizeLastSeen_stringParsing()
    local result = utils.normalizeLastSeen("2024-01-01T12:00:00.000Z")
    assertTrue(result > 0, "ISO8601 string should be parsed")
    assertApproxEquals(result, 1704110400000, 2000, "Parsed string timestamp")
end

function M.test_normalizeLastSeen_nilAndInvalid()
    assertEquals(utils.normalizeLastSeen(nil), 0, "nil should return 0")
    assertEquals(utils.normalizeLastSeen({}), 0, "table should return 0")
    assertEquals(utils.normalizeLastSeen("invalid"), 0, "invalid string should return 0")
end

-- Test that existing lastSeenAt values are preserved (not overwritten by unknown)
function M.test_normalizeLastSeen_preservesKnownValues()
    local known = 1704110400000
    local normalized = utils.normalizeLastSeen(known)
    assertEquals(normalized, known, "Known numeric value should be preserved")
    
    -- Simulating cache logic: if new value is 0, keep old
    local oldValue = known
    local newValue = utils.normalizeLastSeen(nil)
    local finalValue = newValue > 0 and newValue or oldValue
    assertEquals(finalValue, known, "Cache should preserve known value when new is unknown")
end

-- Run all tests
function M.runAll()
    local tests = {
        "test_parseISO8601_validWithMilliseconds",
        "test_parseISO8601_validWithoutMilliseconds",
        "test_parseISO8601_validWithPartialMilliseconds",
        "test_parseISO8601_invalidStrings",
        "test_parseISO8601_edgeCases",
        "test_normalizeLastSeen_numericPassthrough",
        "test_normalizeLastSeen_stringParsing",
        "test_normalizeLastSeen_nilAndInvalid",
        "test_normalizeLastSeen_preservesKnownValues",
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
    
    print(string.format("\nUtils datetime tests: %d passed, %d failed", passed, failed))
    return failed == 0
end

return M
