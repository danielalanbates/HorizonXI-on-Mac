# Which emulator each world runs, and why the list is shorter

**Decision (2026-08-21, Daniel's call): the launcher offers LandSandBoat worlds only.**

LandSandBoat is the only FFXI server emulator still in development. Everything else in the family
tree is frozen:

    DarkStar (deprecated 2020-04-25)
      -> Project Topaz -> renamed LandSandBoat        <- alive, actively released
      -> AirSkyBoat (fork, May 2022, 75-cap module)   <- archived Feb 2025, no reason given
      -> various private forks                        <- frozen wherever they forked

HorizonXI itself is the cautionary tale: it ran on AirSkyBoat, ASB was archived in February 2025,
and Horizon spent nearly a year re-basing onto LandSandBoat, completed 30 January 2026. A world on
a dead fork gets no new content and no upstream fixes.

## How each world was classified

Not by asking around — none of these servers publish their codebase. By probing the login server:

Modern LandSandBoat speaks **JSON over TLS on port 54231** (`src/login/auth_session.cpp`), and
answers a stale version tuple with a verbatim `Your xiloader is too old.` payload. DarkStar-lineage
login servers predate TLS entirely and never complete a handshake. `scripts/login-probe.py` re-runs
the whole test in about ten seconds.

| World | Port 54231 | TLS | Reply | Verdict |
|---|---|---|---|---|
| HorizonXI | open | yes | `{"error_message":"Your xiloader is too old…'2.0.x'…"}` | **LandSandBoat** |
| CatsEyeXI | open | yes | same LSB payload (and their fork is public: `CatsAndBoats/catseyexi`, forked from `LandSandBoat/server`) | **LandSandBoat** |
| Supernova | open | yes | same LSB payload | **LandSandBoat** |
| OmicronXI | open | yes | LSB payload, demanding xiloader `2.1.x` | **LandSandBoat** |
| Gaia XI | open | yes | `0x02` — binary result code from an older LSB login | **LandSandBoat** (older login build) |
| Local server | n/a | n/a | it is LSB, built by `scripts/lsb-server.sh` | **LandSandBoat** |
| Eden | open | **no** (handshake times out) | — | DarkStar lineage — *retired*; their own community wiki says Eden forked from DarkStar |
| FFEra | open | **no** (EOF during handshake) | — | DarkStar lineage — *retired* |
| ValhallaXI | open | **no** (EOF during handshake) | — | DarkStar lineage — *retired* |
| Tabula Rasa XI | no host published | — | — | defunct (parked domain) — *retired* |

## What "retired" means in the code

`Server.all` still holds all ten. `Server.builtins` — what the picker shows — is
`all.filter { $0.codebase == .landSandBoat }`; `Server.retired` is the complement. Nothing was
deleted: the retired entries keep their install pathways, boot profiles, client-version sources and
signup routes, because that was all real work and none of it is wrong — those worlds simply do not
meet the LSB bar.

`ServerStore.merge` drops retired worlds by name from a `servers.json` written by an older build,
so an existing install cleans itself up on first launch. It only drops entries this project
shipped; a server the user added by hand is never touched.

**To bring a world back**, change its `codebase:` to `.landSandBoat` — that is the entire change.
Do it only on evidence: re-run `scripts/login-probe.py` and check the reply, because a server that
re-bases onto LSB (as Horizon did) will start answering the JSON.

## Caveats worth keeping honest

- The probe proves the *login server* is LSB. A world could in principle run an LSB login in front
  of something else; nothing observed suggests that, but it is not disproved.
- Gaia XI's `0x02` is an LSB result code, not the JSON payload — it is on an older LSB login than
  the other four. LSB-family, but not the same vintage.
- "LandSandBoat" here means the lineage, not that a world tracks upstream closely. Every one of
  these is a fork with its own content; the point of the cut is that the fork can still *pull* from
  a living upstream, as Horizon now does.
