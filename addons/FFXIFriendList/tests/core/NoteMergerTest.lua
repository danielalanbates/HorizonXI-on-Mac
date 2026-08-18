-- NoteMergerTest.lua
-- Unit tests for NoteMerger

local notescore = require("core.notescore")

local function testBothNotesEmpty()
    local result = notescore.NoteMerger.merge("", 1000, "", 2000, "", "")
    assert(result == "", "Both empty notes should return empty")
    
    return true
end

local function testOnlyLocalNotePresent()
    local result = notescore.NoteMerger.merge("Local note content", 1000, "", 0, "", "")
    assert(result == "Local note content", "Only local note should return local note")
    
    return true
end

local function testOnlyServerNotePresent()
    local result = notescore.NoteMerger.merge("", 0, "Server note content", 2000, "", "")
    assert(result == "Server note content", "Only server note should return server note")
    
    return true
end

local function testIdenticalNotes()
    local note = "Same note content"
    local result = notescore.NoteMerger.merge(note, 1000, note, 2000, "", "")
    assert(result == note, "Identical notes should return one copy")
    
    return true
end

local function testIdenticalNotesWithWhitespace()
    local localNote = "  Same note content  \n"
    local serverNote = "Same note content"
    local result = notescore.NoteMerger.merge(localNote, 1000, serverNote, 2000, "", "")
    -- Should recognize as equal after trimming
    assert(result == "Same note content", "Should trim and recognize as equal")
    
    return true
end

local function testDifferentNotesGetMerged()
    local localNote = "Local version"
    local serverNote = "Server version"
    
    local result = notescore.NoteMerger.merge(localNote, 2000, serverNote, 1000, "", "")
    
    -- Newer note (local) should come first
    assert(string.find(result, "=== Local Note") ~= nil, "Should contain Local Note header")
    assert(string.find(result, "=== Server Note") ~= nil, "Should contain Server Note header")
    assert(string.find(result, "--- Merged Notes ---") ~= nil, "Should contain merge divider")
    assert(string.find(result, "Local version") ~= nil, "Should contain local version")
    assert(string.find(result, "Server version") ~= nil, "Should contain server version")
    
    -- Local should come before server since it's newer
    local localPos = string.find(result, "=== Local Note")
    local serverPos = string.find(result, "=== Server Note")
    assert(localPos < serverPos, "Local should come before server")
    
    return true
end

local function testNewerServerNoteComesFirst()
    local localNote = "Old local version"
    local serverNote = "New server version"
    
    local result = notescore.NoteMerger.merge(localNote, 1000, serverNote, 2000, "", "")
    
    -- Server note should come first since it's newer
    local localPos = string.find(result, "=== Local Note")
    local serverPos = string.find(result, "=== Server Note")
    assert(serverPos < localPos, "Server should come before local")
    
    return true
end

local function testContainsMergeMarker()
    local withDivider = "Some content\n--- Merged Notes ---\nMore content"
    local withHeader = "=== Local Note (2024-01-01 12:00) ===\nContent"
    local withServerHeader = "=== Server Note (2024-01-01 12:00) ===\nContent"
    local withoutMarker = "Regular note without any markers"
    
    assert(notescore.NoteMerger.containsMergeMarker(withDivider), "Should detect divider")
    assert(notescore.NoteMerger.containsMergeMarker(withHeader), "Should detect local header")
    assert(notescore.NoteMerger.containsMergeMarker(withServerHeader), "Should detect server header")
    assert(not notescore.NoteMerger.containsMergeMarker(withoutMarker), "Should not detect marker in regular note")
    
    return true
end

local function testAvoidsInfiniteNesting()
    -- Simulate already-merged notes
    local localMerged = "=== Local Note (2024-01-01 12:00) ===\nOld content\n--- Merged Notes ---\n=== Server Note ===\nOther content"
    local serverMerged = "=== Server Note (2024-01-02 12:00) ===\nNewer content\n--- Merged Notes ---\n=== Local Note ===\nStale content"
    
    -- When both have markers, should use the newer one to avoid exponential growth
    local result = notescore.NoteMerger.merge(localMerged, 1000, serverMerged, 2000, "", "")
    
    -- Should return the newer one (server, timestamp 2000)
    assert(result == serverMerged, "Should return newer merged note")
    
    -- Test the opposite case
    local result2 = notescore.NoteMerger.merge(localMerged, 3000, serverMerged, 2000, "", "")
    assert(result2 == localMerged, "Should return newer merged note")
    
    return true
end

local function testAreNotesEqual()
    assert(notescore.NoteMerger.areNotesEqual("  test  ", "test"), "Should ignore whitespace")
    assert(notescore.NoteMerger.areNotesEqual("test\n", "test"), "Should ignore newlines")
    assert(notescore.NoteMerger.areNotesEqual("\t\ntest\r\n", "test"), "Should ignore various whitespace")
    assert(not notescore.NoteMerger.areNotesEqual("test1", "test2"), "Should detect different notes")
    
    return true
end

local function runTests()
    local tests = {
        testBothNotesEmpty,
        testOnlyLocalNotePresent,
        testOnlyServerNotePresent,
        testIdenticalNotes,
        testIdenticalNotesWithWhitespace,
        testDifferentNotesGetMerged,
        testNewerServerNoteComesFirst,
        testContainsMergeMarker,
        testAvoidsInfiniteNesting,
        testAreNotesEqual
    }
    
    local passed = 0
    local failed = 0
    
    for _, test in ipairs(tests) do
        local success, err = pcall(test)
        if success then
            passed = passed + 1
            print("  PASS: " .. tostring(test))
        else
            failed = failed + 1
            print("  FAIL: " .. tostring(test) .. " - " .. tostring(err))
        end
    end
    
    print(string.format("NoteMergerTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

