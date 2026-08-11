# Phase 2 — open beta packaging

## What ships today

`scripts/package.sh` builds `HorizonXI-on-Mac-<version>.dmg`. As of 2.2 it is **signed with
the Developer ID, notarised by Apple and stapled**, so a non-technical user can download it,
double-click, and drag to Applications with no Gatekeeper warning and no terminal.

Verified: `spctl -a -t open --context context:primary-signature -v` →
`accepted / source=Notarized Developer ID`.

Inside:

- `HorizonXI-on-Mac.app` — the launcher. Has the standard account section: **username,
  password, and "Remember me"**. The password goes to the macOS Keychain
  (`Credentials.swift`, service `org.batesai.horizonxi-on-mac`) and is written into Ashita's
  boot profile only at launch time, `chmod 600`. It is never stored in a plist or the repo.
- The renderer DLLs ride inside the app bundle: patched DXVK 1.10.3 (with the Metal feature
  relaxations and the push-constant fix) and `d3d8to9.dll`. No separate download.
- `START HERE.md` — the setup guide.

Build a release with:

```sh
HXI_SIGN_ID=<developer-id-cert-hash> ./scripts/package.sh ~/Downloads
codesign --force -s <hash> <dmg>
xcrun notarytool submit <dmg> --keychain-profile batesai-notary --wait
xcrun stapler staple <dmg>
```

Use the certificate **hash**, not its name — there are two identical
"Developer ID Application: Daniel Bates" certs in the login keychain and `codesign` rejects
the name as ambiguous.

## What does NOT ship, and the decision required

Two dependencies are still not in the package, and the second one is a **licensing decision,
not an engineering problem**.

### 1. The game client (~15 GB of `SquareEnix/`)

Square Enix's copyrighted game data. It cannot be redistributed. Users install it with
HorizonXI's own installer or copy an existing install. The launcher already detects an
existing install and remembers it. **This one is correct as-is** — no package should ever
carry it.

### 2. The wine wrapper (~5.3 GB)

This is the actual blocker for "one download and it works". The wrapper currently in use
(`siku.app`) is **CrossOver-derived** — the giveaways are `Frameworks/moltenvkcx/`,
`wine.cx32bak/`, `prefixcx24/`. CrossOver is CodeWeavers' commercial product. Redistributing
their build in a public beta would be a licence violation, so `package.sh` deliberately does
not include it.

Three ways forward. This is Daniel's call, not mine:

| option | effort | licence | user experience |
|---|---|---|---|
| **A. First-run downloader** — launcher fetches a redistributable wine engine (Kegworks/Wineskin) on first launch, then builds the prefix | moderate; needs a pinned engine URL and integrity checking | clean — the user fetches it, we don't redistribute | one extra progress bar on first run; still one download for the user |
| **B. Build wine from source** — upstream wine (LGPL) with wow64 for 32-bit x86 on Apple Silicon, plus MoltenVK (Apache 2.0) and DXVK (zlib) | high; 32-bit-on-ARM wine is the hard part | fully clean, everything redistributable | true single-download bundle |
| **C. Ship the CrossOver-derived wrapper anyway** | none | **violates CodeWeavers' licence** | best UX, unacceptable risk |

Recommendation: **A**. It gets the non-technical user to a single download and a progress
bar, it is legally clean, and it does not require solving 32-bit wine on ARM. B is the
better long-term answer and can follow.

Everything else in the chain is already redistributable: MoltenVK is Apache 2.0, DXVK is
zlib, and our patches are ours.

## Frame-rate status going into beta

Do not promise 30 fps unconditionally. Measured on an M1 (see `FOG-INVESTIGATION.md`):

| scene | draw calls | fps |
|---|---|---|
| menus / light scenes | ~390 | 29 |
| Selbina | ~950 | 20.7 |
| crowded hub (Jeuno), max settings | ~2,100 | 6.2 |

Frame rate × draw calls is roughly constant at **11,000–20,000 draw calls per second**. That
is the ceiling of the D3D8 → d3d8to9 → D3D9 → DXVK → Vulkan → MoltenVK → Metal chain, and it
is CPU-bound: the GPU measures **9–11% utilisation** while the CPU shows **0% idle** with 59%
of that in system time (driver command encoding).

Practical consequence for beta notes: **30 fps needs ≲400–650 draw calls per frame.** Lower
graphics settings and fewer visible players get you there; a crowded auction-house hub at max
settings will not, on any Mac, until the translation chain gets cheaper per draw.

Routes investigated and closed:

- **d8vk** (native D3D8, removes the `d3d8to9` hop) — DXVK 2.x based, requires
  `graphicsPipelineLibrary` and `nullDescriptor`, which Metal lacks. Dead end, same wall as
  DXVK 2.x.
- **GPU-assisted translation** — not possible. Draw-call translation is serial, branchy
  CPU work and GPUs cannot issue Metal API calls. Metal Indirect Command Buffers solve this
  class of problem but require the *application* to batch work up front; FFXI is a 2002
  immediate-mode fixed-function engine.
- **MoltenVK prefill modes / draw-distance reduction** — no meaningful change; in a hub the
  draw calls come from other players' models, not world geometry.

## The biggest untried lever: the renderer runs under Rosetta

Measured 2026-08-11:

```
wine           -> Mach-O 64-bit x86_64
wineserver     -> Mach-O 64-bit x86_64
libMoltenVK    -> x86_64
```

**Every binary in the hot path is x86_64-only, so on an M1 the whole stack runs translated
through Rosetta 2.** That includes MoltenVK — the component the profiler measured spending
35.4 ms per frame encoding command buffers. That encoding is emulated x86 code, not native
ARM.

This reframes the CPU ceiling. We are not only paying API translation
(D3D8 -> d3d8to9 -> D3D9 -> DXVK -> Vulkan -> MoltenVK -> Metal); we are paying **CPU
instruction-set emulation on top of it**, on the exact code that is saturating the CPU.

The fix is an **arm64 wine wrapper**: run wine, DXVK and MoltenVK natively on ARM, and let
only the 32-bit x86 game code be emulated (wow64). That is what CrossOver 23+, Whisky and
Kegworks do. Nothing about the current wrapper takes advantage of it — it predates that work.

This is the most promising remaining route to 30 fps, and it converges with the licensing
decision above: Whisky/Kegworks engines are both **arm64 and redistributable**, so option A
or B in the table would likely deliver the frame-rate win and the legal clearance in one
move.

Order of work suggested:

1. Stand up an arm64 wine wrapper with a fresh prefix.
2. Install the patched DXVK d3d9.dll and an **arm64** MoltenVK into it.
3. Re-measure the crowded-hub scene. If the draws/second ceiling moves materially above
   ~20k, this is the answer and phase 2 should be built on that wrapper.
