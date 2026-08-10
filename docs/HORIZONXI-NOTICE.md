# Draft notice for the HorizonXI community — **HELD, NOT POSTED**

Daniel's instruction, verbatim: *"before we post on horizonxi we need to get it working with gpu
support though."*

That gate is **not met**. As of 2026-08-10 the only pathway that draws the game world correctly
runs at about **3 frames per second in a zone**. Two GPU pathways now render — 20 and 29 fps — and
each is missing part of the picture. Posting this to a community of ~9,500 players in that state
would send people to something that is not yet worth their evening.

**Post it when:** a GPU pathway renders the world correctly in a zone, verified with a screenshot
in `docs/img/`, and the launcher defaults to it.

---

## How to post it, when the time comes

HorizonXI's own code is not on a public GitHub org that takes issues, so "the HorizonXI repo" in
practice means one of:

1. **Their Discord** — the actual centre of gravity for that community, and where a Mac client
   would get real testers. Post in the community/tech channel, not as a DM to staff.
2. **The HorizonXI wiki**, which already links a community Linux installation guide
   (`gitlab.com/MattyGWS/HorizonXI-Linux-Installation`). A macOS equivalent belongs beside it, and
   the wiki is the durable home.
3. **A GitHub Discussion on this repo**, linked from both of the above, so the write-up lives
   somewhere that can be updated.

Ask before posting anywhere: private servers are sensitive about anything that looks like a
modified client, and this project ships no game code — only a launcher and a wine configuration.
Say that plainly and early.

---

## The draft

> **Final Fantasy XI running natively on Apple Silicon — no virtual machine, no Boot Camp**
>
> I've had HorizonXI running on an M1 MacBook Pro under Wine for a few weeks now: logged in,
> in-world, chat live, Ashita macros bound. As far as I can tell every other
> FFXI-on-a-non-Windows-machine project is Linux-only, so this is new ground.
>
> What exists today:
>
> - a native macOS launcher — account name and password, a world dropdown, preflight checks that
>   tell you exactly which piece of the setup is missing, and a repair button
> - a scripted setup for the wine prefix, including the four macOS-specific problems that make
>   the client exit silently with no error
> - a full write-up of every renderer pathway with measured frame rates, so nobody has to redo
>   the debugging
>
> No game code is modified or redistributed. You bring your own HorizonXI client, installed with
> HorizonXI's own installer. The project is a launcher and a wine configuration, nothing more.
>
> **Honest status:** *(this paragraph must be rewritten to match reality on the day it is posted —
> do not post the optimistic version)*
>
> Testers wanted, especially on Apple Silicon Macs with more than 8 GB and on Intel Macs, neither
> of which I can test here.
>
> Repo: <https://github.com/danielalanbates/HorizonXI-on-Mac>
