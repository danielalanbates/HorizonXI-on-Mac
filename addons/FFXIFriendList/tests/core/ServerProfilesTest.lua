-- ServerProfilesTest.lua
-- Unit tests for ServerProfiles module

local ServerProfiles = require("core.ServerProfiles")

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

-- Test: findByHost - Horizon patterns (requires loaded profiles)
function M.test_findByHost_horizon()
    print("\n--- Test: findByHost - Horizon patterns ---")
    
    -- Load mock profiles first
    ServerProfiles.setProfiles({
        { id = "horizon", name = "Horizon", hostPatterns = { "horizonxi.com", "horizon-ffxi" } },
        { id = "eden", name = "Eden", hostPatterns = { "edenxi.com", "eden-ffxi" } }
    })
    
    local profile, pattern
    
    -- horizonxi.com
    profile, pattern = ServerProfiles.findByHost("play.horizonxi.com")
    assert_not_nil("play.horizonxi.com returns profile", profile)
    assert_eq("play.horizonxi.com matches horizon", "horizon", profile and profile.id)
    
    -- Case insensitive
    profile, pattern = ServerProfiles.findByHost("PLAY.HORIZONXI.COM")
    assert_not_nil("PLAY.HORIZONXI.COM (uppercase) returns profile", profile)
    assert_eq("PLAY.HORIZONXI.COM matches horizon", "horizon", profile and profile.id)
end

-- Test: findByHost - Eden patterns (requires loaded profiles)
function M.test_findByHost_eden()
    print("\n--- Test: findByHost - Eden patterns ---")
    
    local profile, pattern
    
    profile, pattern = ServerProfiles.findByHost("play.edenxi.com")
    assert_not_nil("play.edenxi.com returns profile", profile)
    assert_eq("play.edenxi.com matches eden", "eden", profile and profile.id)
end

-- Test: findByHost - Unknown host
function M.test_findByHost_unknown()
    print("\n--- Test: findByHost - Unknown host ---")
    
    local profile, pattern
    
    profile, pattern = ServerProfiles.findByHost("unknown.server.com")
    assert_nil("unknown.server.com returns nil", profile)
    
    profile, pattern = ServerProfiles.findByHost("")
    assert_nil("empty string returns nil", profile)
    
    profile, pattern = ServerProfiles.findByHost(nil)
    assert_nil("nil returns nil", profile)
end

-- Test: findById
function M.test_findById()
    print("\n--- Test: findById ---")
    
    local profile
    
    profile = ServerProfiles.findById("horizon")
    assert_not_nil("findById('horizon') returns profile", profile)
    assert_eq("horizon profile name", "Horizon", profile and profile.name)
    
    profile = ServerProfiles.findById("eden")
    assert_not_nil("findById('eden') returns profile", profile)
    assert_eq("eden profile name", "Eden", profile and profile.name)
    
    profile = ServerProfiles.findById("HORIZON")
    assert_not_nil("findById('HORIZON') (case insensitive)", profile)
    assert_eq("HORIZON profile id", "horizon", profile and profile.id)
    
    profile = ServerProfiles.findById("unknown")
    assert_nil("findById('unknown') returns nil", profile)
    
    profile = ServerProfiles.findById("")
    assert_nil("findById('') returns nil", profile)
    
    profile = ServerProfiles.findById(nil)
    assert_nil("findById(nil) returns nil", profile)
end

-- Test: setProfiles - Loading from API
function M.test_setProfiles()
    print("\n--- Test: setProfiles - Loading from API ---")
    
    -- Set profiles from mock API response
    local apiProfiles = {
        { id = "testserver", name = "Test Server", hostPatterns = { "test.server.com" } },
        { id = "another", name = "Another Server", hostPatterns = { "another.net" } }
    }
    
    local success = ServerProfiles.setProfiles(apiProfiles)
    assert_true("setProfiles returns true for valid data", success)
    assert_true("isLoaded is true after setProfiles", ServerProfiles.isLoaded())
    assert_nil("getLoadError is nil after success", ServerProfiles.getLoadError())
    
    -- Verify new profiles work
    local profile = ServerProfiles.findById("testserver")
    assert_not_nil("findById('testserver') works after setProfiles", profile)
    assert_eq("testserver profile name", "Test Server", profile and profile.name)
    
    profile, _ = ServerProfiles.findByHost("test.server.com")
    assert_not_nil("findByHost('test.server.com') works after setProfiles", profile)
    assert_eq("host match returns testserver", "testserver", profile and profile.id)
end

-- Test: setProfiles - Empty/nil handling
function M.test_setProfiles_edge_cases()
    print("\n--- Test: setProfiles - Edge cases ---")
    
    -- Empty array should fail
    local success = ServerProfiles.setProfiles({})
    assert_false("setProfiles({}) returns false", success)
    assert_false("isLoaded is false after empty setProfiles", ServerProfiles.isLoaded())
    assert_not_nil("getLoadError is set after failure", ServerProfiles.getLoadError())
    
    -- nil should fail
    success = ServerProfiles.setProfiles(nil)
    assert_false("setProfiles(nil) returns false", success)
    assert_false("isLoaded is false after nil setProfiles", ServerProfiles.isLoaded())
    
    -- Invalid entries should be filtered, valid one should work
    success = ServerProfiles.setProfiles({
        { id = nil, name = "No ID" },
        { id = "valid", name = nil },
        { id = "good", name = "Good Server", hostPatterns = { "good.com" } }
    })
    assert_true("setProfiles filters invalid entries", success)
    assert_true("isLoaded is true with valid entry", ServerProfiles.isLoaded())
    
    local profile = ServerProfiles.findById("good")
    assert_not_nil("valid entry 'good' is available", profile)
end

-- Test: setLoadError
function M.test_setLoadError()
    print("\n--- Test: setLoadError ---")
    
    ServerProfiles.setLoadError("Network timeout")
    assert_false("isLoaded is false after setLoadError", ServerProfiles.isLoaded())
    assert_eq("getLoadError returns error message", "Network timeout", ServerProfiles.getLoadError())
end

-- Test: getAll returns array of profiles
function M.test_getAll()
    print("\n--- Test: getAll ---")
    
    -- Load some profiles
    ServerProfiles.setProfiles({
        { id = "test1", name = "Test 1", hostPatterns = {} },
        { id = "test2", name = "Test 2", hostPatterns = {} }
    })
    
    local profiles = ServerProfiles.getAll()
    assert_not_nil("getAll returns table", profiles)
    assert_eq("getAll returns 2 profiles", 2, #profiles)
    
    -- Check first profile has required fields
    local first = profiles[1]
    assert_not_nil("first profile exists", first)
    assert_not_nil("first profile has id", first and first.id)
    assert_not_nil("first profile has name", first and first.name)
end

-- Test: getNames returns id/name pairs
function M.test_getNames()
    print("\n--- Test: getNames ---")
    
    -- Load some profiles
    ServerProfiles.setProfiles({
        { id = "server1", name = "Server One", hostPatterns = {} },
        { id = "server2", name = "Server Two", hostPatterns = {} }
    })
    
    local names = ServerProfiles.getNames()
    assert_not_nil("getNames returns table", names)
    assert_eq("getNames returns 2 entries", 2, #names)
    
    -- Check first entry
    local first = names[1]
    assert_not_nil("first entry exists", first)
    assert_not_nil("first entry has id", first and first.id)
    assert_not_nil("first entry has name", first and first.name)
end

-- Test: getCount
function M.test_getCount()
    print("\n--- Test: getCount ---")
    
    -- Empty initially
    ServerProfiles.setProfiles({})
    assert_eq("getCount is 0 when empty", 0, ServerProfiles.getCount())
    
    -- After loading
    ServerProfiles.setProfiles({
        { id = "a", name = "A", hostPatterns = {} },
        { id = "b", name = "B", hostPatterns = {} },
        { id = "c", name = "C", hostPatterns = {} }
    })
    assert_eq("getCount is 3 after loading", 3, ServerProfiles.getCount())
end

-- Run all tests
function M.runAll()
    print("\n========================================")
    print("ServerProfiles Unit Tests")
    print("========================================")
    
    passed = 0
    failed = 0
    
    M.test_findByHost_horizon()
    M.test_findByHost_eden()
    M.test_findByHost_unknown()
    M.test_findById()
    M.test_setProfiles()
    M.test_setProfiles_edge_cases()
    M.test_setLoadError()
    M.test_getAll()
    M.test_getNames()
    M.test_getCount()
    
    print("\n========================================")
    print(string.format("Results: %d passed, %d failed", passed, failed))
    print("========================================")
    
    return failed == 0
end

return M
