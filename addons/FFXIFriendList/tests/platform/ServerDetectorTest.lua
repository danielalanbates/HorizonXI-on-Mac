-- ServerDetectorTest.lua
-- Unit tests for ServerDetector module (pure Lua tests, no Ashita dependency)

local M = {}

-- Test counter
local passed = 0
local failed = 0

local function assert_eq(name, expected, actual)
    if expected == actual then
        passed = passed + 1
        print("  ✓ " .. name)
        return true
    else
        failed = failed + 1
        print("  ✗ " .. name .. " - Expected: " .. tostring(expected) .. ", Got: " .. tostring(actual))
        return false
    end
end

local function assert_not_nil(name, value)
    if value ~= nil then
        passed = passed + 1
        print("  ✓ " .. name)
        return true
    else
        failed = failed + 1
        print("  ✗ " .. name .. " - Expected non-nil, got nil")
        return false
    end
end

local function assert_nil(name, value)
    if value == nil then
        passed = passed + 1
        print("  ✓ " .. name)
        return true
    else
        failed = failed + 1
        print("  ✗ " .. name .. " - Expected nil, got: " .. tostring(value))
        return false
    end
end

local function assert_true(name, value)
    if value == true then
        passed = passed + 1
        print("  ✓ " .. name)
        return true
    else
        failed = failed + 1
        print("  ✗ " .. name .. " - Expected true, got: " .. tostring(value))
        return false
    end
end

local function assert_false(name, value)
    if value == false then
        passed = passed + 1
        print("  ✓ " .. name)
        return true
    else
        failed = failed + 1
        print("  ✗ " .. name .. " - Expected false, got: " .. tostring(value))
        return false
    end
end

-- Mock logger
local function createMockLogger()
    return {
        debug = function() end,
        info = function() end,
        warn = function() end,
        error = function() end
    }
end

-- Test: _parseHostFromCommand
function M.test_parseHostFromCommand()
    print("\n--- Test: _parseHostFromCommand ---")
    
    local ServerDetector = require("platform.services.ServerDetector")
    local detector = ServerDetector.ServerDetector.new(nil, createMockLogger())
    
    local host
    
    -- Pattern 1: --server <host> (space separated)
    host = detector:_parseHostFromCommand("--server play.horizonxi.com")
    assert_eq("--server space separated", "play.horizonxi.com", host)
    
    -- Pattern 1 with extra args
    host = detector:_parseHostFromCommand("--server play.horizonxi.com --user test")
    assert_eq("--server with extra args", "play.horizonxi.com", host)
    
    -- Pattern 1 with password
    host = detector:_parseHostFromCommand("--server play.horizonxi.com --user test --password secret123")
    assert_eq("--server with password", "play.horizonxi.com", host)
    
    -- Pattern 2: --server=<host> (equals separated)
    host = detector:_parseHostFromCommand("--server=betabox.horizonxi.com")
    assert_eq("--server=host format", "betabox.horizonxi.com", host)
    
    -- Pattern 3: -s <host> (short form)
    host = detector:_parseHostFromCommand("-s edenxi.com")
    assert_eq("-s short form", "edenxi.com", host)
    
    -- No server flag
    host = detector:_parseHostFromCommand("/game eAZcFcB")
    assert_nil("no server flag returns nil", host)
    
    -- Empty string
    host = detector:_parseHostFromCommand("")
    assert_nil("empty string returns nil", host)
    
    -- Nil input
    host = detector:_parseHostFromCommand(nil)
    assert_nil("nil input returns nil", host)
end

-- Test: Detection result structure
function M.test_detectionResultStructure()
    print("\n--- Test: Detection result structure ---")
    
    local ServerDetector = require("platform.services.ServerDetector")
    local detector = ServerDetector.ServerDetector.new(nil, createMockLogger())
    
    -- Without AshitaCore, detection should fail gracefully
    local result = detector:detect()
    
    assert_not_nil("detect returns result", result)
    assert_not_nil("result has success field", result.success ~= nil)
    assert_not_nil("result has method field", result.method)
    assert_not_nil("result has timestamp field", result.timestamp)
    assert_not_nil("result has cached field", result.cached ~= nil)
    
    -- Without Ashita, should fail
    assert_false("detect without Ashita fails", result.success)
    assert_not_nil("error message present", result.error)
end

-- Test: Manual override
function M.test_manualOverride()
    print("\n--- Test: Manual override ---")
    
    local ServerDetector = require("platform.services.ServerDetector")
    local detector = ServerDetector.ServerDetector.new(nil, createMockLogger())
    
    -- Set manual override
    detector:setManualOverride("horizon")
    
    local result = detector:detect()
    
    assert_true("manual override succeeds", result.success)
    assert_eq("method is manual", "manual", result.method)
    assert_not_nil("profile is set", result.profile)
    assert_eq("profile id is horizon", "horizon", result.profile and result.profile.id)
    
    -- Clear override
    detector:clearManualOverride()
    result = detector:detect()
    
    -- Without Ashita and without override, should fail
    assert_false("after clearing override, detect fails", result.success)
end

-- Test: Caching behavior
function M.test_cachingBehavior()
    print("\n--- Test: Caching behavior ---")
    
    local ServerDetector = require("platform.services.ServerDetector")
    local detector = ServerDetector.ServerDetector.new(nil, createMockLogger())
    
    -- Set manual override so detection succeeds
    detector:setManualOverride("eden")
    
    -- First detection
    local result1 = detector:detect()
    assert_false("first detect is not cached", result1.cached)
    
    -- Second detection should be cached (within cooldown)
    local result2 = detector:detect()
    assert_true("second detect is cached", result2.cached)
    
    -- Force refresh should bypass cache
    local result3 = detector:detect(true)  -- forceRefresh = true
    assert_false("forced detect is not cached", result3.cached)
end

-- Test: getDiagnostics
function M.test_getDiagnostics()
    print("\n--- Test: getDiagnostics ---")
    
    local ServerDetector = require("platform.services.ServerDetector")
    local detector = ServerDetector.ServerDetector.new(nil, createMockLogger())
    
    detector:setManualOverride("catseye")
    local _ = detector:detect()
    
    local diag = detector:getDiagnostics()
    
    assert_not_nil("getDiagnostics returns table", diag)
    assert_not_nil("diag has detectionMethod", diag.detectionMethod)
    assert_not_nil("diag has success", diag.success ~= nil)
    assert_eq("diag shows manual method", "manual", diag.detectionMethod)
    assert_eq("diag shows catseye profile", "catseye", diag.serverProfile)
    assert_eq("diag shows manual override", "catseye", diag.manualOverride)
end

-- Test: DetectionMethod constants
function M.test_detectionMethodConstants()
    print("\n--- Test: DetectionMethod constants ---")
    
    local ServerDetector = require("platform.services.ServerDetector")
    
    assert_eq("ASHITA_CONFIG constant", "ashita_config", ServerDetector.DetectionMethod.ASHITA_CONFIG)
    assert_eq("LOG_FILE constant", "log_file", ServerDetector.DetectionMethod.LOG_FILE)
    assert_eq("BOOT_INI constant", "boot_ini", ServerDetector.DetectionMethod.BOOT_INI)
    assert_eq("MANUAL constant", "manual", ServerDetector.DetectionMethod.MANUAL)
    assert_eq("NONE constant", "none", ServerDetector.DetectionMethod.NONE)
end

-- Run all tests
function M.runAll()
    print("\n========================================")
    print("ServerDetector Unit Tests")
    print("========================================")
    
    passed = 0
    failed = 0
    
    M.test_parseHostFromCommand()
    M.test_detectionResultStructure()
    M.test_manualOverride()
    M.test_cachingBehavior()
    M.test_getDiagnostics()
    M.test_detectionMethodConstants()
    
    print("\n========================================")
    print(string.format("Results: %d passed, %d failed", passed, failed))
    print("========================================")
    
    return failed == 0
end

return M
