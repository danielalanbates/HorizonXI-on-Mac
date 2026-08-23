# Vanaguide

Written 2026-08-22.

`addons/Vanaguide/` is a guide addon written for this project: step-by-step walkthroughs
that tick themselves off using the server's own quest log, with a waypoint arrow and
routing between zones. It is the FFXI answer to Zygor, and the sibling of the same author's
WoW addon, CompletionRoute.

Canonical repository: <https://github.com/danielalanbates/vanaguide> — full documentation,
the guide format, the offline test harness, and the honest list of what has not been
verified live there. This folder is a vendored copy, the same way `FFXIFriendList` is, so
the launcher can install it without a second checkout.

## It is not on any server's allowlist

This matters more than the feature list. HorizonXI, CatsEyeXI and FFEra all publish
allowlists and enforce them, and Vanaguide is on none of them because it is new. The
launcher's addon screen filters per server (`docs/ADDON-POLICY.md`), so on those servers
Vanaguide will not be offered — which is correct, and must stay that way until a server
actually approves it.

Where it can be used today: the **Local server** (your own LandSandBoat world, policy
`.unrestricted`), and any server whose policy is `.unknown` *after you have asked them*.

Vanaguide sends no packets, moves nothing, and targets nothing. It reads the log the server
already sent and draws on your own screen. That is the case to put to a server admin.

## Installing it by hand

```sh
cp -R addons/Vanaguide "<install>/addons/Vanaguide"
```

then `/addon load vanaguide` in-game, or add `/addon load vanaguide` to the custom section
of `scripts/default.txt` — below the launcher's managed markers, so the launcher does not
rewrite it.

## Licence

Vanaguide is PolyForm Noncommercial 1.0.0 with a commercial-use rider
(`addons/Vanaguide/LICENSE`), not this repository's MIT. Keep the two straight when copying
code between them.
