# Addons from the command line

`FFXI-on-Mac --addons …` reads and changes a world's addon list with no window, so a script
(or an AI session) can do what the Addons… sheet does, and say exactly which file it wrote.
`scripts/addons.sh` is the short form and runs the installed app.

```
scripts/addons.sh list                        # the selected world
scripts/addons.sh list --world "Local server"
scripts/addons.sh enable vanaguide,cmdpipe --world "Local server"
scripts/addons.sh disable clock --world "Local server"
scripts/addons.sh enable balloon --world HorizonXI
scripts/addons.sh narration on                # "Read cutscenes aloud (VanaVoice)"
scripts/addons.sh script --world HorizonXI    # prints …/scripts/default.txt
```

## What it does, exactly

* **The world picks the file.** A world's boot profile names its script (`script=` in the
  Ashita v4 .ini): HorizonXI runs `scripts/default.txt`, the local LandSandBoat world
  `scripts/lsb.txt`. Until 2026-08-29 the sheet always wrote `default.txt`, which is how three
  local-only addons ended up in HorizonXI's script; both the sheet and this command now resolve
  the file through the profile and print it.
* **The block is the launcher's; the rest of the file is yours.** Load lines live between
  `# --HORIZON_PLUGINS_START/STOP--` and `# --HORIZON_ADDONS_START/STOP--`. Lines outside
  those markers — `lsb.txt` keeps cmdpipe, vanaguide, vanagear and vanavoice there by hand —
  count as **on** (they load) and are listed with *loaded by a line outside the launcher's
  block*. Enabling one never duplicates it; disabling one removes that hand-written line,
  because nothing else would switch it off.
* **The world's rules apply.** On a world with a published allowlist (HorizonXI), enabling an
  addon that is not on it is refused with exit 1 — loading it there is a bannable offence —
  unless you pass `--force`, which writes it and says so. The local world has no rules.
  Disabling `Addons` (the Lua host every addon needs) is refused the same way.
* **It reads the file back.** After a write, each changed addon is re-scanned from disk and
  printed `ok` or `!!`; exit 3 if the file did not end up as asked.
* **`narration on|off`** is the launcher's *Read cutscenes aloud (VanaVoice)* toggle (under
  SETUP & DIAGNOSTICS). It matters more than it looks: with it **off**, every Play *removes*
  `/addon load vanavoice` from the world's script; with it on, Play installs the addon from
  VanaVoice.app and adds the line. If the launcher window is open it holds its own copy of the
  settings and writes it back on its next change — the command says so; flip the toggle there
  too, or quit and reopen.

Exit status: 0 done · 1 refused by the world's rules · 2 usage, unknown name or no install ·
3 could not write (the script's launcher markers are missing).

## Verifying a change without trusting the output

```
md5 …/scripts/default.txt …/scripts/lsb.txt      # before
scripts/addons.sh disable clock --world "Local server"
md5 …/scripts/default.txt …/scripts/lsb.txt      # only lsb.txt changed
grep -n "addon load" …/scripts/lsb.txt
```

That is the check run on 2026-08-29 when this was written (see docs/SERVERS-WORKLOG.md).
