-- ServerProfileFetcherTest.lua
-- Unit tests for ServerProfileFetcher service

local ServerProfileFetcher = require("platform.services.ServerProfileFetcher")

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

-- Mock HTTP request function
local function createMockHttpRequest(mockResponse)
    return function(options)
        if options.callback then
            if mockResponse.success then
                options.callback(true, mockResponse.body, 200)
            else
                options.callback(false, nil, mockResponse.error or "Network error")
            end
        end
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

-- Test: Constructor
function M.test_constructor()
    print("\n--- Test: Constructor ---")
    
    local mockHttp = createMockHttpRequest({ success = true, body = '{}' })
    local fetcher = ServerProfileFetcher.ServerProfileFetcher.new(mockHttp, createMockLogger())
    
    assert_not_nil("fetcher created", fetcher)
    assert_eq("initial state is idle", ServerProfileFetcher.State.IDLE, fetcher.state)
    assert_nil("initial profiles is nil", fetcher.profiles)
end

-- Test: Successful fetch
function M.test_fetch_success()
    print("\n--- Test: Successful fetch ---")
    
    local apiResponse = [[{
        "success": true,
        "data": {
            "servers": [
                {"id": "horizon", "name": "Horizon", "hostPatterns": ["horizonxi.com"]},
                {"id": "eden", "name": "Eden", "hostPatterns": ["edenxi.com"]}
            ]
        }
    }]]
    
    local mockHttp = createMockHttpRequest({ success = true, body = apiResponse })
    local fetcher = ServerProfileFetcher.ServerProfileFetcher.new(mockHttp, createMockLogger())
    
    local callbackCalled = false
    local callbackSuccess = nil
    local callbackProfiles = nil
    
    fetcher:fetch(function(success, profiles, err)
        callbackCalled = true
        callbackSuccess = success
        callbackProfiles = profiles
    end)
    
    assert_true("callback was called", callbackCalled)
    assert_true("callback success is true", callbackSuccess)
    assert_not_nil("callback received profiles", callbackProfiles)
    assert_eq("received 2 profiles", 2, callbackProfiles and #callbackProfiles)
    assert_eq("fetcher state is success", ServerProfileFetcher.State.SUCCESS, fetcher.state)
end

-- Test: Network failure
function M.test_fetch_network_failure()
    print("\n--- Test: Network failure ---")
    
    local mockHttp = createMockHttpRequest({ success = false, error = "Connection refused" })
    local fetcher = ServerProfileFetcher.ServerProfileFetcher.new(mockHttp, createMockLogger())
    
    local callbackSuccess = nil
    local callbackError = nil
    
    fetcher:fetch(function(success, profiles, err)
        callbackSuccess = success
        callbackError = err
    end)
    
    assert_eq("callback success is false", false, callbackSuccess)
    assert_not_nil("callback received error", callbackError)
    assert_eq("fetcher state is failed", ServerProfileFetcher.State.FAILED, fetcher.state)
end

-- Test: Invalid JSON response
function M.test_fetch_invalid_json()
    print("\n--- Test: Invalid JSON response ---")
    
    local mockHttp = createMockHttpRequest({ success = true, body = "not valid json" })
    local fetcher = ServerProfileFetcher.ServerProfileFetcher.new(mockHttp, createMockLogger())
    
    local callbackSuccess = nil
    
    fetcher:fetch(function(success, profiles, err)
        callbackSuccess = success
    end)
    
    assert_eq("callback success is false for invalid JSON", false, callbackSuccess)
    assert_eq("fetcher state is failed", ServerProfileFetcher.State.FAILED, fetcher.state)
end

-- Test: Empty servers array
function M.test_fetch_empty_servers()
    print("\n--- Test: Empty servers array ---")
    
    local apiResponse = [[{"success": true, "data": {"servers": []}}]]
    
    local mockHttp = createMockHttpRequest({ success = true, body = apiResponse })
    local fetcher = ServerProfileFetcher.ServerProfileFetcher.new(mockHttp, createMockLogger())
    
    local callbackSuccess = nil
    
    fetcher:fetch(function(success, profiles, err)
        callbackSuccess = success
    end)
    
    assert_eq("callback success is false for empty servers", false, callbackSuccess)
end

-- Test: getDiagnostics
function M.test_getDiagnostics()
    print("\n--- Test: getDiagnostics ---")
    
    local mockHttp = createMockHttpRequest({ success = true, body = '{"data":{"servers":[]}}' })
    local fetcher = ServerProfileFetcher.ServerProfileFetcher.new(mockHttp, createMockLogger())
    
    local diag = fetcher:getDiagnostics()
    
    assert_not_nil("diagnostics returned", diag)
    assert_eq("diagnostics has state", ServerProfileFetcher.State.IDLE, diag.state)
    assert_eq("diagnostics profileCount is 0", 0, diag.profileCount)
end

-- Run all tests
function M.runAll()
    print("\n========================================")
    print("ServerProfileFetcher Unit Tests")
    print("========================================")
    
    passed = 0
    failed = 0
    
    M.test_constructor()
    M.test_fetch_success()
    M.test_fetch_network_failure()
    M.test_fetch_invalid_json()
    M.test_fetch_empty_servers()
    M.test_getDiagnostics()
    
    print("\n========================================")
    print(string.format("Results: %d passed, %d failed", passed, failed))
    print("========================================")
    
    return failed == 0
end

return M
