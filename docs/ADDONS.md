# Getting Ashita's addons to actually load

Written 2026-08-13. Until today **no addon in this install had ever run**, on Mac or anywhere
else, and nothing said so except one line in the client log.

## The symptom

    PluginManager::Load | Failed to load plugin 'Addons';
      plugin is compiled with a different interface version than expected. (Plugin: 4.15)(Expected: 4.16)

`Addons.dll` is Ashita's Lua host. When it is refused, every `/addon load` in
`scripts/default.txt` silently does nothing — the script still lists them, the launcher still
shows them enabled, and nothing runs. `screenshot`, `Nameplate`, `PacketFlow` and `thirdparty`
were refused the same way.

## What was actually wrong

The core and the bundled plugins came from different builds. Ashita checks an interface number
that both sides compile in, and the two did not match.

The number is a `double` constant in each binary, which makes this diagnosable in a second
instead of by launching the game repeatedly:

```sh
python3 - <<'EOF'
import struct, glob, os
pats = {v: struct.pack('<d', v) for v in (4.15, 4.16, 4.30)}
for f in sorted(glob.glob('plugins/*.dll')) + ['Ashita.dll']:
    d = open(f, 'rb').read()
    print(os.path.basename(f), [v for v, p in pats.items() if p in d])
EOF
```

Results here: `Ashita.dll` wants **4.16**; every bundled plugin was **4.15**.

## Finding the matching set

`Ashita.dll` in this install is **byte-identical** (md5 `b5142803f63e09f779ad5205420300f1`) to the
one at commit **`35c124ce4b`** of `AshitaXI/Ashita-v4beta`. That commit's plugins are the set it
was built against, and they are 4.16:

```sh
SHA=35c124ce4b
for f in Addons.dll screenshot.dll thirdparty.dll hardwaremouse.dll Minimap.dll toon.dll; do
  curl -sSL -o "plugins/$f" \
    "https://raw.githubusercontent.com/AshitaXI/Ashita-v4beta/$SHA/plugins/$f"
done
```

Note the repository's `main` branch is **not** the right source: its plugin binaries are 4.15
(older than this core) while its `Ashita.dll` is 4.30 (newer). Both were tried; the 4.15 plugins
were refused for the version, and the 4.30 core refused *every* plugin with "missing required
exports". The only coherent pairing is the one commit above.

## Result

    Loaded plugin: Addons     - Version: 2.30
    Loaded plugin: screenshot - Version: 4.10
    Loaded plugin: thirdparty - Version: 4.10
    Loaded plugin: Sequencer  - Version: 1.01
    Loaded plugin: winefix    - Version: 1.00

Lua addons run — `statustimers` was resolving its pointers within seconds of the client starting.

## Still broken, and why

`Nameplate` and `PacketFlow` are HorizonXI's own plugins, not Ashita's, and the copies here are
4.15. They are not in the Ashita repository at any commit, and HorizonXI does not publish them
separately: their launcher fetches the whole 9.4 GB game archive by BitTorrent
(`https://api.horizonxi.com/api/v1/launcher/install-game`), and the incremental update it serves
(`update-game?ver=<n>`) contains only ROM `.DAT` files. Getting 4.16 builds of those two means
pulling the current base archive. `Deeps` and `Shorthand` (Thorny's) are 4.15 as well.

Everything else, including the Lua host that every addon depends on, works.

## Where this is applied

Both installs: `~/Games/HorizonXI/…` (the benchmark harness) and
`/Volumes/x10/Video Games/Mac HorizonXI/…` (the one the launcher app uses). The originals are
kept beside them in `plugins/backup-4.15/` and `plugins/backup-orig/`.

The launcher's Addons panel reads these failures out of the newest client log and shows them, so
a future mismatch is visible in the UI rather than only in a log nobody opens.
