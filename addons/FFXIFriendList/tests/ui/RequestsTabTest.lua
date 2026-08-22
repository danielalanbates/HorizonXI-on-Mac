local M = {}

local function createMockDataModule(incomingRequests, outgoingRequests)
    local state = {
        incomingRequests = incomingRequests or {},
        outgoingRequests = outgoingRequests or {}
    }
    
    return {
        GetIncomingRequests = function()
            return state.incomingRequests
        end,
        GetOutgoingRequests = function()
            return state.outgoingRequests
        end,
        GetIncomingRequestsCount = function()
            return #state.incomingRequests
        end
    }
end

local function formatRequestsTabLabel(incomingCount)
    if incomingCount > 0 then
        return "Requests (" .. incomingCount .. ")"
    end
    return "Requests"
end

local function testTabLabelWithZeroIncoming()
    local label = formatRequestsTabLabel(0)
    assert(label == "Requests", "Tab label should be 'Requests' when count is 0, got: " .. label)
    return true
end

local function testTabLabelWithPositiveIncoming()
    local label = formatRequestsTabLabel(3)
    assert(label == "Requests (3)", "Tab label should be 'Requests (3)' when count is 3, got: " .. label)
    return true
end

local function testTabLabelWithOneIncoming()
    local label = formatRequestsTabLabel(1)
    assert(label == "Requests (1)", "Tab label should be 'Requests (1)' when count is 1, got: " .. label)
    return true
end

local function testGetIncomingRequestsCountEmpty()
    local dataModule = createMockDataModule({}, {})
    local count = dataModule.GetIncomingRequestsCount()
    assert(count == 0, "Should return 0 for empty incoming requests")
    return true
end

local function testGetIncomingRequestsCountNonEmpty()
    local incoming = {
        {id = "1", name = "player1"},
        {id = "2", name = "player2"},
        {id = "3", name = "player3"}
    }
    local dataModule = createMockDataModule(incoming, {})
    local count = dataModule.GetIncomingRequestsCount()
    assert(count == 3, "Should return 3 for 3 incoming requests, got: " .. count)
    return true
end

local function testIncomingListContainsOnlyIncoming()
    local incoming = {
        {id = "1", name = "incomingPlayer1"},
        {id = "2", name = "incomingPlayer2"}
    }
    local outgoing = {
        {id = "3", name = "outgoingPlayer1"}
    }
    local dataModule = createMockDataModule(incoming, outgoing)
    
    local incomingRequests = dataModule.GetIncomingRequests()
    assert(#incomingRequests == 2, "Incoming list should have 2 items")
    assert(incomingRequests[1].name == "incomingPlayer1", "First incoming should be incomingPlayer1")
    assert(incomingRequests[2].name == "incomingPlayer2", "Second incoming should be incomingPlayer2")
    return true
end

local function testOutgoingListContainsOnlyOutgoing()
    local incoming = {
        {id = "1", name = "incomingPlayer1"}
    }
    local outgoing = {
        {id = "2", name = "outgoingPlayer1"},
        {id = "3", name = "outgoingPlayer2"}
    }
    local dataModule = createMockDataModule(incoming, outgoing)
    
    local outgoingRequests = dataModule.GetOutgoingRequests()
    assert(#outgoingRequests == 2, "Outgoing list should have 2 items")
    assert(outgoingRequests[1].name == "outgoingPlayer1", "First outgoing should be outgoingPlayer1")
    assert(outgoingRequests[2].name == "outgoingPlayer2", "Second outgoing should be outgoingPlayer2")
    return true
end

local function testOutgoingCountDoesNotAffectBadge()
    local incoming = {}
    local outgoing = {
        {id = "1", name = "player1"},
        {id = "2", name = "player2"}
    }
    local dataModule = createMockDataModule(incoming, outgoing)
    
    local incomingCount = dataModule.GetIncomingRequestsCount()
    local label = formatRequestsTabLabel(incomingCount)
    
    assert(label == "Requests", "Badge should be 'Requests' even with outgoing requests, got: " .. label)
    return true
end

function M.run()
    local tests = {
        {name = "testTabLabelWithZeroIncoming", fn = testTabLabelWithZeroIncoming},
        {name = "testTabLabelWithPositiveIncoming", fn = testTabLabelWithPositiveIncoming},
        {name = "testTabLabelWithOneIncoming", fn = testTabLabelWithOneIncoming},
        {name = "testGetIncomingRequestsCountEmpty", fn = testGetIncomingRequestsCountEmpty},
        {name = "testGetIncomingRequestsCountNonEmpty", fn = testGetIncomingRequestsCountNonEmpty},
        {name = "testIncomingListContainsOnlyIncoming", fn = testIncomingListContainsOnlyIncoming},
        {name = "testOutgoingListContainsOnlyOutgoing", fn = testOutgoingListContainsOnlyOutgoing},
        {name = "testOutgoingCountDoesNotAffectBadge", fn = testOutgoingCountDoesNotAffectBadge}
    }
    
    local passed = 0
    local failed = 0
    
    for _, test in ipairs(tests) do
        local success, err = pcall(test.fn)
        if success then
            passed = passed + 1
            print("  PASS: " .. test.name)
        else
            failed = failed + 1
            print("  FAIL: " .. test.name .. " - " .. tostring(err))
        end
    end
    
    print(string.format("RequestsTabTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return M

