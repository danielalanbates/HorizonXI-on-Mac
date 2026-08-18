--[[
    GM Tools v1.0.4 - SQLite3 Persistence Layer
    Uses Ashita v4.30's built-in LuaSQLite3 for favorites, history, and custom presets.

    LuaSQLite3 API reference:
        db:exec(sql)                    -- Execute SQL statement
        db:rows(sql)                    -- Iterator over result rows (as arrays)
        db:nrows(sql)                   -- Iterator over result rows (as named tables)
        db:close()                      -- Close database connection
        db:prepare(sql)                 -- Prepare a statement
        stmt:bind_values(...)           -- Bind values to prepared statement
        stmt:step()                     -- Execute step
        stmt:finalize()                 -- Finalize statement
]]--

require 'common';

local json = require 'json';

local db = {};
db.conn = nil;
db.path = nil;

-- Cache dirty flags: invalidated on any mutation
db.favorites_dirty = true;
db.history_dirty = true;
db.custom_presets_dirty = true;

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

function db.init(addon_path)
    local sqlite3 = require('sqlite3');

    -- Store DB in the addon's config directory
    db.path = addon_path .. '\\gmtools.db';
    local ok_open, conn = pcall(sqlite3.open, db.path);
    if (not ok_open or conn == nil) then
        print(chat.header('gmtools'):append(chat.error('Failed to open database: ' .. tostring(conn))));
        return;
    end
    db.conn = conn;

    -- Enable WAL mode for better concurrent access
    db.conn:exec('PRAGMA journal_mode=WAL;');
    db.conn:exec('PRAGMA busy_timeout=3000;');

    -- Create tables
    db.conn:exec([[
        CREATE TABLE IF NOT EXISTS favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            cmd TEXT NOT NULL,
            category TEXT,
            use_count INTEGER DEFAULT 0,
            last_used INTEGER DEFAULT 0,
            sort_order INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cmd TEXT NOT NULL,
            timestamp INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS custom_presets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            desc TEXT,
            commands TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS job_gear_overrides (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job TEXT NOT NULL,
            slot TEXT NOT NULL,
            item_id INTEGER NOT NULL,
            item_name TEXT NOT NULL,
            sort_order INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_jgo_job ON job_gear_overrides(job);
    ]]);

    -- Fix legacy rows that all have sort_order=0
    db.normalize_favorite_order();
end

-------------------------------------------------------------------------------
-- Favorites
-------------------------------------------------------------------------------

function db.get_favorites()
    local results = T{};
    if (db.conn == nil) then return results; end

    for row in db.conn:nrows('SELECT * FROM favorites ORDER BY sort_order ASC, use_count DESC') do
        results:append(row);
    end
    return results;
end

function db.add_favorite(name, cmd, category)
    if (db.conn == nil) then return; end

    -- Check if already favorited
    local stmt = db.conn:prepare('SELECT id FROM favorites WHERE cmd = ?');
    if (stmt == nil) then return false; end
    stmt:bind_values(cmd);
    local existing = stmt:step();
    stmt:finalize();

    -- step() returns 100 (SQLITE_ROW) if already exists, 101 (SQLITE_DONE) if not
    if (existing == 100) then return false; end

    -- Get next sort order
    local max_order = 0;
    for row in db.conn:nrows('SELECT MAX(sort_order) as m FROM favorites') do
        if (row.m ~= nil) then max_order = row.m; end
    end

    local ins = db.conn:prepare('INSERT INTO favorites (name, cmd, category, sort_order) VALUES (?, ?, ?, ?)');
    if (ins == nil) then return false; end
    ins:bind_values(name, cmd, category or '', max_order + 1);
    ins:step();
    ins:finalize();
    db.favorites_dirty = true;
    return true;
end

function db.remove_favorite(id)
    if (db.conn == nil) then return; end
    local stmt = db.conn:prepare('DELETE FROM favorites WHERE id = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(id);
    stmt:step();
    stmt:finalize();
    db.favorites_dirty = true;
end

function db.remove_favorite_by_cmd(cmd)
    if (db.conn == nil) then return; end
    local stmt = db.conn:prepare('DELETE FROM favorites WHERE cmd = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(cmd);
    stmt:step();
    stmt:finalize();
    db.favorites_dirty = true;
end

function db.is_favorite(cmd)
    if (db.conn == nil) then return false; end
    local stmt = db.conn:prepare('SELECT id FROM favorites WHERE cmd = ? LIMIT 1');
    if (stmt == nil) then return false; end
    stmt:bind_values(cmd);
    local result = stmt:step();
    stmt:finalize();
    -- step() returns sqlite3.ROW (100) if a row was found
    return (result == 100);
end

function db.update_favorite_usage(id)
    if (db.conn == nil) then return; end
    local stmt = db.conn:prepare('UPDATE favorites SET use_count = use_count + 1, last_used = ? WHERE id = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(os.time(), id);
    stmt:step();
    stmt:finalize();
    db.favorites_dirty = true;
end

-------------------------------------------------------------------------------
-- Favorite Reordering
-------------------------------------------------------------------------------

function db.normalize_favorite_order()
    if (db.conn == nil) then return; end

    -- Reassign sort_order sequentially (1, 2, 3, ...) based on current ordering
    local ids = T{};
    for row in db.conn:nrows('SELECT id FROM favorites ORDER BY sort_order ASC, id ASC') do
        ids:append(row.id);
    end

    db.conn:exec('BEGIN');
    local stmt = db.conn:prepare('UPDATE favorites SET sort_order = ? WHERE id = ?');
    if (stmt == nil) then db.conn:exec('ROLLBACK'); return; end
    for i, fav_id in ipairs(ids) do
        stmt:bind_values(i, fav_id);
        stmt:step();
        stmt:reset();
    end
    stmt:finalize();
    db.conn:exec('COMMIT');
end

function db.move_favorite_up(id)
    if (db.conn == nil) then return; end

    -- Get current sort_order for this favorite
    local cur_order = nil;
    local stmt = db.conn:prepare('SELECT sort_order FROM favorites WHERE id = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(id);
    for row in stmt:nrows() do cur_order = row.sort_order; end
    stmt:finalize();
    if (cur_order == nil) then return; end

    -- Find the row just above (highest sort_order that is less than current)
    local above_id = nil;
    local above_order = nil;
    local stmt2 = db.conn:prepare('SELECT id, sort_order FROM favorites WHERE sort_order < ? ORDER BY sort_order DESC LIMIT 1');
    if (stmt2 == nil) then return; end
    stmt2:bind_values(cur_order);
    for row in stmt2:nrows() do
        above_id = row.id;
        above_order = row.sort_order;
    end
    stmt2:finalize();
    if (above_id == nil) then return; end -- already at top

    -- Swap sort_order values (transaction-wrapped for atomicity)
    db.conn:exec('BEGIN');
    local u1 = db.conn:prepare('UPDATE favorites SET sort_order = ? WHERE id = ?');
    if (u1 == nil) then db.conn:exec('ROLLBACK'); return; end
    u1:bind_values(above_order, id);
    u1:step();
    u1:finalize();

    local u2 = db.conn:prepare('UPDATE favorites SET sort_order = ? WHERE id = ?');
    if (u2 == nil) then db.conn:exec('ROLLBACK'); return; end
    u2:bind_values(cur_order, above_id);
    u2:step();
    u2:finalize();
    db.conn:exec('COMMIT');
    db.favorites_dirty = true;
end

function db.move_favorite_down(id)
    if (db.conn == nil) then return; end

    -- Get current sort_order for this favorite
    local cur_order = nil;
    local stmt = db.conn:prepare('SELECT sort_order FROM favorites WHERE id = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(id);
    for row in stmt:nrows() do cur_order = row.sort_order; end
    stmt:finalize();
    if (cur_order == nil) then return; end

    -- Find the row just below (lowest sort_order that is greater than current)
    local below_id = nil;
    local below_order = nil;
    local stmt2 = db.conn:prepare('SELECT id, sort_order FROM favorites WHERE sort_order > ? ORDER BY sort_order ASC LIMIT 1');
    if (stmt2 == nil) then return; end
    stmt2:bind_values(cur_order);
    for row in stmt2:nrows() do
        below_id = row.id;
        below_order = row.sort_order;
    end
    stmt2:finalize();
    if (below_id == nil) then return; end -- already at bottom

    -- Swap sort_order values (transaction-wrapped for atomicity)
    db.conn:exec('BEGIN');
    local u1 = db.conn:prepare('UPDATE favorites SET sort_order = ? WHERE id = ?');
    if (u1 == nil) then db.conn:exec('ROLLBACK'); return; end
    u1:bind_values(below_order, id);
    u1:step();
    u1:finalize();

    local u2 = db.conn:prepare('UPDATE favorites SET sort_order = ? WHERE id = ?');
    if (u2 == nil) then db.conn:exec('ROLLBACK'); return; end
    u2:bind_values(cur_order, below_id);
    u2:step();
    u2:finalize();
    db.conn:exec('COMMIT');
    db.favorites_dirty = true;
end

-------------------------------------------------------------------------------
-- History
-------------------------------------------------------------------------------

function db.log_command(cmd)
    if (db.conn == nil) then return; end
    local stmt = db.conn:prepare('INSERT INTO history (cmd, timestamp) VALUES (?, ?)');
    if (stmt == nil) then return; end
    stmt:bind_values(cmd, os.time());
    stmt:step();
    stmt:finalize();

    -- Keep only last 200 entries (cheap: single-pass DELETE using max id)
    db.conn:exec('DELETE FROM history WHERE id <= (SELECT MAX(id) - 200 FROM history)');
    db.history_dirty = true;
end

function db.get_history(limit)
    local results = T{};
    if (db.conn == nil) then return results; end

    limit = limit or 50;
    local stmt = db.conn:prepare('SELECT *, strftime(\'%H:%M:%S\', timestamp, \'unixepoch\', \'localtime\') as time_fmt FROM history ORDER BY id DESC LIMIT ?');
    if (stmt == nil) then return results; end
    stmt:bind_values(limit);
    for row in stmt:nrows() do
        results:append(row);
    end
    stmt:finalize();
    return results;
end

function db.search_history(query)
    local results = T{};
    if (db.conn == nil) then return results; end

    local stmt = db.conn:prepare('SELECT *, strftime(\'%H:%M:%S\', timestamp, \'unixepoch\', \'localtime\') as time_fmt FROM history WHERE cmd LIKE ? ORDER BY id DESC LIMIT 50');
    if (stmt == nil) then return results; end
    stmt:bind_values('%' .. query .. '%');
    for row in stmt:nrows() do
        results:append(row);
    end
    stmt:finalize();
    return results;
end

function db.clear_history()
    if (db.conn == nil) then return; end
    db.conn:exec('DELETE FROM history');
    db.history_dirty = true;
end

-------------------------------------------------------------------------------
-- Custom Presets
-------------------------------------------------------------------------------

function db.get_custom_presets()
    local results = T{};
    if (db.conn == nil) then return results; end

    for row in db.conn:nrows('SELECT * FROM custom_presets ORDER BY id ASC') do
        -- Decode commands JSON to table
        local ok, cmds = pcall(json.decode, row.commands);
        if (ok and cmds ~= nil) then
            row.commands = T(cmds);
        else
            row.commands = T{};
        end
        results:append(row);
    end
    return results;
end

function db.save_custom_preset(name, desc, commands_list)
    if (db.conn == nil) then return; end

    local commands_json = json.encode(commands_list);
    local stmt = db.conn:prepare('INSERT INTO custom_presets (name, desc, commands) VALUES (?, ?, ?)');
    if (stmt == nil) then return; end
    stmt:bind_values(name, desc or '', commands_json);
    stmt:step();
    stmt:finalize();
    db.custom_presets_dirty = true;
end

function db.update_custom_preset(id, name, desc, commands_list)
    if (db.conn == nil) then return; end

    local commands_json = json.encode(commands_list);
    local stmt = db.conn:prepare('UPDATE custom_presets SET name = ?, desc = ?, commands = ? WHERE id = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(name, desc or '', commands_json, id);
    stmt:step();
    stmt:finalize();
    db.custom_presets_dirty = true;
end

function db.delete_custom_preset(id)
    if (db.conn == nil) then return; end
    local stmt = db.conn:prepare('DELETE FROM custom_presets WHERE id = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(id);
    stmt:step();
    stmt:finalize();
    db.custom_presets_dirty = true;
end

function db.clear_all_presets()
    if (db.conn == nil) then return; end
    db.conn:exec('DELETE FROM custom_presets');
    db.custom_presets_dirty = true;
end

function db.seed_defaults(preset_defaults)
    if (db.conn == nil) then return; end

    -- Check if table already has rows
    local count = 0;
    for row in db.conn:nrows('SELECT COUNT(*) as c FROM custom_presets') do
        count = row.c;
    end
    if (count > 0) then return false; end

    -- Insert all built-in presets
    db.conn:exec('BEGIN');
    local ins = db.conn:prepare('INSERT INTO custom_presets (name, desc, commands) VALUES (?, ?, ?)');
    if (ins == nil) then db.conn:exec('ROLLBACK'); return false; end
    for _, preset in ipairs(preset_defaults) do
        local commands_json = json.encode(preset.commands);
        ins:bind_values(preset.name, preset.desc or '', commands_json);
        ins:step();
        ins:reset();
    end
    ins:finalize();
    db.conn:exec('COMMIT');
    db.custom_presets_dirty = true;
    return true;
end

-------------------------------------------------------------------------------
-- Job Gear Overrides
-------------------------------------------------------------------------------

function db.has_job_gear_override(job_name)
    if (db.conn == nil) then return false; end
    local stmt = db.conn:prepare('SELECT COUNT(*) as c FROM job_gear_overrides WHERE job = ?');
    if (stmt == nil) then return false; end
    stmt:bind_values(job_name);
    local count = 0;
    for row in stmt:nrows() do count = row.c; end
    stmt:finalize();
    return count > 0;
end

function db.get_job_gear(job_name)
    if (db.conn == nil) then return nil; end

    local results = {};
    local stmt = db.conn:prepare('SELECT slot, item_id, item_name FROM job_gear_overrides WHERE job = ? ORDER BY slot, sort_order ASC');
    if (stmt == nil) then return nil; end
    stmt:bind_values(job_name);
    for row in stmt:nrows() do
        if (results[row.slot] == nil) then
            results[row.slot] = T{};
        end
        results[row.slot]:append({ id = row.item_id, name = row.item_name });
    end
    stmt:finalize();
    return results;
end

function db.save_job_gear(job_name, slots, slot_order)
    if (db.conn == nil) then return; end

    db.conn:exec('BEGIN');

    -- Delete existing overrides for this job
    local del = db.conn:prepare('DELETE FROM job_gear_overrides WHERE job = ?');
    if (del == nil) then db.conn:exec('ROLLBACK'); return; end
    del:bind_values(job_name);
    del:step();
    del:finalize();

    -- Insert all slot items
    local ins = db.conn:prepare('INSERT INTO job_gear_overrides (job, slot, item_id, item_name, sort_order) VALUES (?, ?, ?, ?, ?)');
    if (ins == nil) then db.conn:exec('ROLLBACK'); return; end
    for _, slot_name in ipairs(slot_order) do
        local items = slots[slot_name];
        if (items ~= nil) then
            for i, item in ipairs(items) do
                ins:bind_values(job_name, slot_name, item.id, item.name, i);
                ins:step();
                ins:reset();
            end
        end
    end
    ins:finalize();

    db.conn:exec('COMMIT');
end

function db.delete_job_gear(job_name)
    if (db.conn == nil) then return; end
    local stmt = db.conn:prepare('DELETE FROM job_gear_overrides WHERE job = ?');
    if (stmt == nil) then return; end
    stmt:bind_values(job_name);
    stmt:step();
    stmt:finalize();
end

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

function db.close()
    if (db.conn ~= nil) then
        db.conn:close();
        db.conn = nil;
    end
end

return db;
