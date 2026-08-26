# Does zoning disconnect you from your linkshell?

**Tested against the local LandSandBoat server on 2026-08-23** (LSB `627e5671`, single `xi_map`
process, two real clients on one Mac). Short answer:

> **No.** Zoning does not drop linkshell membership. The pearl stays equipped, the member list
> repairs itself, and chat works in both directions the moment you land. What you *do* lose is
> the linkshell chat that was said while you were between zones — measured here at **~2 seconds,
> two messages out of twenty-five**.

If what you actually see on a public server is the pearl unequipping or "you have been removed
from the linkshell" after a zone line, that is **not** stock LSB behaviour and the cause is on
that server, not in this mechanism.

---

## Why the gap exists at all

FFXI does not keep one connection to one server. `charutils::SendToZone`
(`src/map/utils/charutils.cpp`) writes the character's position to the database and then sends
the client a **logout** packet with `GP_GAME_LOGOUT_STATE::ZONECHANGE` and the IP/port of the
destination zone. The client tears the map connection down and dials the new one — even when, as
on a personal server, "the new one" is the same process on the same port.

So every zone line destroys the `CCharEntity` and builds a fresh one:

| Step | Code | Effect on the linkshell |
|---|---|---|
| Zone out | `charutils::SendToZone` | `status = Disappear` |
| Character freed | `CCharEntity::~CCharEntity` | `PLinkshell1/2->DelMember(this)` — you leave the online-member list |
| Zone in | `charutils::LoadChar` → `LoadInventory` | the equipped pearl is read back from `char_equip` |
| Re-registered | `linkshell::AddOnlineMember` | you are back in the online-member list |

Between rows 2 and 4 nobody is holding a pointer to you, and `CLinkshell::PushPacket`
(`src/map/linkshell.cpp`) walks exactly that list. Anything said in the gap is delivered to
everyone else and to nobody on your behalf. It is not queued, because there is nothing to queue
it against.

This is also why the vanilla failed-tell message reads *"the recipient is either offline **or
changing areas**"* — the server genuinely cannot tell the two apart.

## What the measurement looked like

Two accounts (`Test` / charid 1, `Buddy` / charid 2), both wearing a pearl for the same linkshell
in `SLOT_LINK2`, both in San d'Oria. `Buddy` sent 25 numbered messages 1.6s apart; partway
through, `Test` was sent across a zone line with `!zone`. Every incoming chat line on both
clients was captured by `addons/lslog` (see below) rather than read off a screenshot.

```
15:27:34  SEQ-001 .. SEQ-005   received by Test
15:27:42  PACKET 0x0B zone-out
                                SEQ-006, SEQ-007 sent here -- never arrive
15:27:44  PACKET 0x0A zone-in
15:27:44  SEQ-008 .. SEQ-025   received by Test
```

25 sent, 23 received, and the two casualties are precisely the two that fell inside the
handover. Before and after the line, chat flows in both directions with no re-equip, no relog
and no user-visible membership change.

## The fix: replay the gap on zone-in

Since the server knows both *when* a character left an online-member list and *what* was said
after that, it can simply hand over the difference when the character comes back.

`patches/lsb-linkshell-zone-backlog.patch` adds, to `src/map/`:

* **A short ring buffer per linkshell.** `CLinkshell::BufferMessage` records every linkshell
  chat line as `IPCClient::handleMessage_ChatMessageLinkshell` relays it, capped at
  `LINKSHELL_BACKLOG_SIZE` (50) messages and `LINKSHELL_BACKLOG_MAX_AGE` (60s). It is a buffer,
  not a history: it is not persisted and it is not readable by players.
* **A departure timestamp per character.** `charutils::SendToZone` calls
  `linkshell::NoteZoneDeparture(charId)`. Deliberately *not* `CLinkshell::DelMember`: that would
  be tidier, but the old `CCharEntity` is not guaranteed to be destroyed before the new one has
  already re-registered, and `DelMember` also fires for logouts and kicks, which must not replay
  anything. `SendToZone` is the one point that is unambiguously before the handover.
* **Replay deferred to the 0x00A handler.** `linkshell::AddOnlineMember` consumes the timestamp
  and — only if the departure is inside the 60s window — records what the character is owed.
  `linkshell::FlushPendingReplay`, called from `0x00a_login.cpp` once `status` goes back to
  `Normal`, is what actually pushes the messages, skipping the character's own lines and
  re-tagging for LS2 the way `PushPacket` does.

  The split matters. The obvious version — push the backlog straight from `AddOnlineMember` —
  compiles, runs, and silently does nothing: `AddOnlineMember` is reached from inside `LoadChar`,
  and the 0x00A handler calls `clearPacketList()` twice *after* that, so the replay is queued and
  then thrown away. The first cut of this patch shipped that bug and the measurement below is
  what caught it.

The 60s window is what separates *"this player zoned"* from *"this player logged in"*: a zone
handover measured here is about two seconds, and nobody wants a minute of backlog dumped on them
at login.

### Does it work?

Same harness, same 25-messages-at-1.6s-across-a-zone-line run, on the patched server:

| Run | Who zoned | Sent | Received | Lost |
|---|---|---|---|---|
| baseline (unpatched) | Test | 25 | 23 | `006`, `007` |
| V2 | Test | 25 | **25** | — |
| V3 | Test | 25 | **25** | — |
| V4 | Buddy | 25 | 24 | `006` |
| V5 | Buddy | 25 | 24 | `006` |
| V6 | Buddy | 25 | 24 | `006` |

The messages that used to vanish are now delivered a fraction of a second after zone-in, pushed
by `FlushPendingReplay`. `docs/img/linkshell-zone-replay.png` is `Buddy`'s own chat window after
zoning mid-conversation: `Buddy : !zone 230` with all three lines `Test` spoke during the
handover sitting underneath it.

**One message can still be lost, and it is always the same one.** In the runs where `Buddy`
zoned, the line spoken in the last fraction of a second *before* `SendToZone` executed is
delivered live — into a connection the client has already stopped reading — and is then excluded
from the replay, because `BufferMessage` stamped it earlier than the departure timestamp. A
timestamp taken at `SendToZone` cannot cover that, and widening it with a grace period would
replay messages the character demonstrably did see, which is worse. Closing it properly needs
sequence numbers rather than clock time (see the pathway below): record, at `SendToZone`, the
sequence number of the last linkshell message actually written out for that character, and replay
everything after it.

So: 2 lost of 25 before, 0–1 of 25 after, and the residual is a race with the client's own
teardown rather than the server dropping the character off the linkshell.

### Known limits — read before deploying this anywhere real

1. **Single map process only.** The buffer and the departure map live in `xi_map`'s memory. On a
   server that shards zones across several `xi_map` processes, a character zoning from one shard
   to another departs in one process and re-registers in another, which has neither its
   timestamp nor the messages. It degrades to today's behaviour — the gap comes back — rather
   than misbehaving, but it does not *fix* anything there.
2. **The buffer dies with the linkshell.** `DelOnlineMember` erases a linkshell from
   `LinkshellList` once its last member leaves. If the only online member zones, the buffer goes
   with it. Nothing was missed in that case, so this is harmless, but it is why the fix cannot be
   relied on for a one-member shell.
3. **Replay is not ordered against live traffic** beyond the fact that it is pushed before the
   character can receive anything new; a message that arrives mid-replay lands after it.

### The multi-process pathway, for whoever picks this up next

The properly general version belongs in **`xi_world`**, which already relays every
`ipc::ChatMessageLinkshell` and is the one process every shard talks to:

* Give the world server the ring buffer, keyed by `linkshellId`, with a monotonic sequence
  number per message.
* Add `ls_lastseq1` / `ls_lastseq2` columns to `accounts_sessions` — the table already carries
  `linkshellid1/2`, is shared by every map process, and is already written on join and leave.
  Map servers advance them as they deliver.
* On `AddOnlineMember`, the map server asks the world server for everything newer than the
  character's stored sequence number; the world server answers with a new IPC message and the
  map server pushes the result.

That version survives shard hops, restarts of individual map processes, gives exactly-once
delivery instead of a time window, and — because it counts messages rather than seconds — also
closes the one-message teardown race described above. It is a larger change — new IPC message types and a schema
migration — which is why the contained map-side version is what is offered here.

## Reproducing it

`addons/lslog` (in this repo, autoloaded from `scripts/lsb.txt`) writes every incoming chat line
and the zone-in/zone-out packets to `addons/lslog/lslog.log` — `lslog2.log` when `FLCLIENT=2`.
Reading assertions out of a text file beats reading them off a 640x480 screenshot, and it is how
the numbers above were produced.

Driving the clients: `scripts/twoclient.py` launches and walks in each client, and
`addons/mousediag/cmd.txt` / `cmd2.txt` is a one-line-at-a-time command channel into a running
client that needs no window focus. Two gotchas cost an hour here:

* The second client must be launched with the **same** wine that is already running
  (`/Volumes/Games/FFXI/wine-coop/wine/bin/wine`). Starting it with the wrapper's own
  `SharedSupport/wine/bin/wine` while a wine-coop `wineserver` is up fails with
  `version mismatch 1809/856`.
* Do not let two characters equip the same linkshell at the same moment while scripting setup.
  A one-way-chat failure was seen once after doing exactly that and did not reproduce after a
  clean map-server restart with the equips serialised; the cause was never pinned down, so treat
  it as a reason to serialise, not as a diagnosed bug.

## Files

| Path | What |
|---|---|
| `patches/lsb-linkshell-zone-backlog.patch` | the server fix, against LSB `627e5671` |
| `addons/lslog/lslog.lua` | chat + zone packet logger used for the measurement |
| `scripts/lsb-server.sh` | build/run the local LSB server |

---

Copyright (c) 2026 Bates LLC. All rights reserved.
Questions: <help@batesai.org> — <https://batesai.org>
