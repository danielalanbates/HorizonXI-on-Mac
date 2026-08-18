-- NotesTest.lua
-- Unit tests for app/features/notes.lua (local-only persistence)

local Notes = require("app.features.notes")

local function createFakeDeps()
    local storage = {}
    local time = 1000
    
    return {
        storage = {
            load = function(key)
                return storage[key]
            end,
            save = function(key, data)
                storage[key] = data
            end
        },
        time = function()
            time = time + 100
            return time
        end
    }
end

local function testNotesInitialState()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    assert(notes:getNote("Friend1") == "", "Should return empty string for non-existent note")
    assert(not notes:hasNote("Friend1"), "Should not have note initially")
    
    return true
end

local function testNotesSetGet()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    notes:setNote("Friend1", "Test note")
    assert(notes:getNote("Friend1") == "Test note", "Should return set note")
    assert(notes:hasNote("Friend1"), "Should have note after setting")
    
    notes:setNote("Friend1", "Updated note")
    assert(notes:getNote("Friend1") == "Updated note", "Should return updated note")
    
    return true
end

local function testNotesDelete()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    notes:setNote("Friend1", "Test note")
    assert(notes:hasNote("Friend1"), "Should have note")
    
    notes:deleteNote("Friend1")
    assert(not notes:hasNote("Friend1"), "Should not have note after delete")
    assert(notes:getNote("Friend1") == "", "Should return empty string after delete")
    
    return true
end

local function testNotesPersistence()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    notes:setNote("Friend1", "Test note")
    notes:setNote("Friend2", "Another note")
    notes:save()
    
    -- Create new instance and load
    local notes2 = Notes.Notes.new(deps)
    notes2:load()
    
    assert(notes2:getNote("Friend1") == "Test note", "Should load saved note")
    assert(notes2:getNote("Friend2") == "Another note", "Should load all saved notes")
    
    return true
end

local function testNotesEmptyNote()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    notes:setNote("Friend1", "Test note")
    assert(notes:hasNote("Friend1"), "Should have note")
    
    notes:setNote("Friend1", "")  -- Empty note should delete
    assert(not notes:hasNote("Friend1"), "Should not have note after setting empty")
    
    return true
end

-- BUG 1 FIX TESTS: Pending note persistence

local function testPendingNoteSetAndGet()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    -- Set a pending note
    notes:setPendingNote("NewFriend", "Draft note for pending friend")
    
    -- Get pending note should work
    local pending = notes:getPendingNote("NewFriend")
    assert(pending == "Draft note for pending friend", "Should get pending note")
    
    return true
end

local function testPendingNotePersistence()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    -- Set a pending note
    notes:setPendingNote("NewFriend", "Draft note for pending friend")
    notes:save()
    
    -- Create new instance and load
    local notes2 = Notes.Notes.new(deps)
    notes2:load()
    
    -- Pending note should be persisted
    local pending = notes2:getPendingNote("NewFriend")
    assert(pending == "Draft note for pending friend", "Should persist pending note across reload")
    
    return true
end

local function testPendingNoteConsumed()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    -- Set a pending note
    notes:setPendingNote("NewFriend", "Draft note")
    
    -- Consume it
    local consumed = notes:consumePendingNote("NewFriend")
    assert(consumed == "Draft note", "Should consume pending note")
    
    -- Second consume should return nil
    local consumed2 = notes:consumePendingNote("NewFriend")
    assert(consumed2 == nil, "Should not consume pending note twice")
    
    -- After reload, consumed note should not appear
    local notes2 = Notes.Notes.new(deps)
    notes2:load()
    local pending = notes2:getPendingNote("NewFriend")
    assert(pending == nil, "Consumed note should not persist")
    
    return true
end

local function testPendingNoteState()
    local deps = createFakeDeps()
    local notes = Notes.Notes.new(deps)
    
    notes:setNote("ExistingFriend", "Existing note")
    notes:setPendingNote("NewFriend1", "Pending 1")
    notes:setPendingNote("NewFriend2", "Pending 2")
    
    local state = notes:getState()
    assert(state.noteCount == 1, "Should have 1 note")
    assert(state.pendingCount == 2, "Should have 2 pending notes")
    
    return true
end

local function runTests()
    local tests = {
        testNotesInitialState,
        testNotesSetGet,
        testNotesDelete,
        testNotesPersistence,
        testNotesEmptyNote,
        -- BUG 1 FIX TESTS
        testPendingNoteSetAndGet,
        testPendingNotePersistence,
        testPendingNoteConsumed,
        testPendingNoteState
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
    
    print(string.format("NotesTest: %d passed, %d failed", passed, failed))
    return failed == 0
end

return { run = runTests }

