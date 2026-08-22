# GM Tools v1.0.4 - GM Command Helper for Ashita v4.3

A comprehensive GM command interface for LandSandBoat private servers. Browse, execute, and manage 184 GM commands through an ImGui GUI without memorizing syntax or item IDs.

## Features

- **Command Browser** - 11 categories with typed inputs (dropdowns for zones/jobs/weather, integer/float/text fields, checkboxes)
- **Item Search** - Search all FFXI items by name, give with one click (incremental cache, no frame drops)
- **Favorites** - Star any command with current arguments, reorder with up/down buttons, persisted in SQLite
- **Presets** - 3 built-in quick-setup presets + custom preset builder with clipboard JSON export/import
- **Job Gear** - Per-job gear loadouts for all 22 jobs with save/reset, copy/paste, add by ID or search
- **History** - Last 200 executed commands with search and re-run
- **GM Level Filter** - Filter commands by permission level (Player/GM/SeniorGM/Admin/SuperAdmin/Developer)
- **Per-Character Settings** - Queue delay, GM level filter, and show on load saved per character via Ashita's settings module

## Requirements

- Ashita v4.3.0.2 (uses built-in LuaSQLite3)
	- This release has only been tested with Ashita v4.3.0.2

## Installation

1. Copy the `gmtools` folder to your Ashita `addons` directory
2. Load with `/addon load gmtools`

## Commands

| Command | Description |
|---------|-------------|
| `/gm` | Toggle the GM Tools window |
| `/gm help` | Show all commands, presets, and available jobs |
| `/gm preset <name>` | Run a preset by name (e.g., `/gm preset full unlock`) |
| `/gm stop` | Stop a running preset mid-execution |
| `/gm resetui` | Reset window size, position, and column widths |
| `/gm delay <sec>` | Set preset command delay (0.1-10.0, default 1.5s) |
| `/gm gear <job>` | Give gear loadout for a job (e.g., `/gm gear WAR`) |
| `/gm export <job>` | Export gear loadout to clipboard as JSON |
| `/gm import` | Import gear from clipboard into currently selected job |
| `/gm search <item>` | Search items by name (e.g., `/gm search sword`) |

## Built-in Presets

| Preset | Description |
|--------|-------------|
| Full Dev Setup | `!setupchar` (all 22 jobs 99 mastered, skills capped, key items) + all content unlocks + 10M gil + max inventory |
| Chest & Coffer Kit | Keys for chest/coffer testing (Skeleton Key, Living Key, Thief's Tools + zone-specific keys). Warps to Garlaige Citadel |
| BCNM Orb Kit | All BCNM orbs (Lv20-60 cap), KSNM orbs (Clotho/Lachesis/Atropos/Themis), 99x seals and crests. Warps to Horlais Peak |

## Job Gear

Default loadouts for all 22 jobs with endgame gear (Nyame, Sakpata, Malignance, Bunzi, Mpaca, Flamma, Ayanmo, Mummu sets; Relic/Mythic/Empyrean weapons, JSE capes, etc.). Customize any loadout through the UI:

- Add items by ID or search by name
- Remove individual items per slot
- Save customizations to database (persists across sessions)
- Copy/Paste loadouts between jobs via clipboard JSON
- Reset to hardcoded defaults at any time

## File Structure

```
gmtools/
  gmtools.lua    -- Entry point, slash commands, events, settings
  ui.lua         -- ImGui UI rendering (all 6 tabs)
  db.lua         -- SQLite persistence (favorites, history, presets, gear overrides)
  commands.lua   -- 184 command definitions in 11 categories
  presets.lua    -- 3 built-in preset definitions
  jobgear.lua    -- Per-job gear definitions (22 jobs, 16 equipment slots)
```

## Data Storage

- **Per-character settings** (queue delay, GM level filter) are saved by Ashita's settings module under `config/addons/gmtools/<CharName>_<ID>/settings.lua`
- **Shared data** (favorites, history, custom presets, gear overrides) is stored in `config/addons/gmtools/gmtools.db` (SQLite, auto-created)
- SQLite uses WAL mode which creates companion `-wal` and `-shm` files (normal, auto-managed)

## Technical Notes

### Performance
- **Dirty-flag caching**: All DB-backed data uses dirty flags (`favorites_dirty`, `history_dirty`, `custom_presets_dirty`) — UI reads from memory cache, only re-queries on mutation
- **Combo string cache**: ImGui combo strings (null-delimited) built once via `table.concat` and cached (avoids O(n^2) string concatenation)
- **Item name cache**: `resolve_item_name()` caches `GetItemById()` lookups in a hash table — avoids repeated SDK calls for the same item ID
- **Item cache**: Incremental build at 2000 items/frame via `GetResourceManager():GetItemById()` to avoid frame drops
- **SQL-side timestamp formatting**: History queries use `strftime()` in SQL to return pre-formatted time strings — eliminates per-row `os.date()` calls in the render loop
- **Efficient history cleanup**: Uses `WHERE id <= (SELECT MAX(id) - 200)` instead of a `NOT IN` subquery for O(1) pruning
- **Transaction-batched reorder**: `normalize_favorite_order()` wraps all UPDATEs in a single transaction with statement reuse (one `prepare`/`finalize`, multiple `bind`/`step`/`reset`)
- **Deferred saves**: UI sets `settings_dirty` flag, d3d_present handler processes it (decouples rendering from I/O)

### Command Categories
1. Teleport (16 commands) - Zone, position, goto, bring, send, speed, wallhack
2. Character (20 commands) - Level, jobs, XP, merits, rank, race, costume
3. Skills (17 commands) - Cap skills, learn spells/trusts/WS, crafting
4. Items (24 commands) - Add/delete items, gil, currency, key items, titles
5. Status (10 commands) - HP/MP/TP, god mode, effects
6. Mobs (18 commands) - Spawn, despawn, mob control, pets
7. World (14 commands) - Weather, time, conquest, music, animations
8. Quests (17 commands) - Missions, quests, cutscenes, variables
9. Admin (13 commands) - GM toggle, jail, promote, yell, exec
10. Reload (7 commands) - Reload scripts, navmesh, recipes
11. Debug (28 commands) - Stats, mods, variables, packets, instances

### Permission Levels
| Level | Name | Example Commands |
|-------|------|-----------------|
| 0 | Player | `!build`, `!geteffects` |
| 1 | GM | Most commands (default) |
| 2 | Senior GM | `!getenmity` |
| 3 | Admin | `!racechange`, `!getmod`, `!setlocalvar`, `!getfame`, `!setfamelevel` |
| 4 | Super Admin | `!exec`, `!breaklinkshell`, `!reloadglobal` |
| 5 | Developer | `!sleep`, `!addtime`, all `!reload*` commands |

## Version History

### v1.0.4
- Fixed view_button Push/Pop style color mismatch (red border flash when switching tabs)

### v1.0.3
- Pre-allocated all ImGui size/position tables and button style color tables (eliminates ~20 per-frame table allocations)
- Fixed README command counts (177 → 184): Items 23→24, Quests 18→17, Debug 21→28
- Added `show_on_load` to documented per-character settings

### v1.0.2
- Added `InputTextWithHint` placeholder text to 5 search/input fields (history search, job gear item search, item search tab, preset name, preset description)
- Fixed README preset table (was listing 11 old presets, now correctly shows 3 current presets)

### v1.0.1
- Combo string builder: replaced O(n^2) string concat loop with `table.insert`+`table.concat`
- Item name cache: `resolve_item_name()` caches SDK lookups in a hash table
- History cleanup: replaced expensive `NOT IN` subquery with efficient `WHERE id <= (SELECT MAX(id) - 200)`
- History queries: moved timestamp formatting to SQL `strftime()` (eliminates per-row `os.date()`)
- Favorite reorder: wrapped in transaction with prepared statement reuse

### v1.0.0
- 6 tabs: Categories, Favorites, Presets, Job Gear, Item Search, History
- SQLite persistence via Ashita v4.30 LuaSQLite3
- Per-character settings via Ashita's settings module (queue delay, GM level filter)
- Dirty-flag caching for all DB-backed data
- Combo string cache and incremental item cache
- 3 built-in presets (Full Dev Setup, Chest & Coffer Kit, BCNM Orb Kit)
- 22 job gear definitions with verified item IDs
- json.encode calls wrapped in pcall for consistent error handling
- All DB queries use prepared statements

## Thanks

- **Ashita Team** - atom0s, thorny, and the [Ashita Discord](https://discord.gg/Ashita) community
- **LandSandBoat** - FFXI server emulator team

## License

MIT License - See LICENSE file
