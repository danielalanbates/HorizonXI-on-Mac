#!/bin/zsh
# update-client.sh — bring the game files in a prefix up to date, the way each server's own
# launcher would, so the login server stops answering "The game's data has been updated".
#
#   update-client.sh check  <drive_c/HorizonXI dir>            -> prints "installed=<ver> horizon=<marketing> latest=<marketing>"
#   update-client.sh horizon <drive_c/HorizonXI dir>           -> applies every pending HorizonXI update
#
# What each server actually does (checked 2026-08-15, see docs/CLIENT-UPDATES.md):
#
#   * HorizonXI: `api.horizonxi.com/api/v1/launcher/update-game?ver=<n>` lists numbered update
#     zips, each delivered as a BitTorrent magnet (their Electron launcher uses webtorrent).
#     This script fetches them with aria2c (brew), unzips over the game dir, deletes the
#     `deleteFiles` list, and writes the new marketing version to version.json — the same steps
#     their launcher performs. Torrents mean it can be slow or stall when nobody is seeding.
#
#   * CatsEyeXI: their launcher syncs the client from a private Cloudflare R2 bucket using
#     credentials baked into the .exe. There is no public manifest, so this script cannot
#     update a CatsEye client. It can only tell you the version is wrong (see `check`) and the
#     required version comes from their public server settings.
#
# Every step is idempotent: re-running after a stall resumes the aria2 download.
set -euo pipefail

say() { print -r -- "==> $*"; }
die() { print -r -- "!! $*" >&2; exit 1; }

API="https://api.horizonxi.com/api/v1/launcher"
UA="FFXI-on-Mac launcher"

game="${2:-}"
[[ -n "$game" && -d "$game" ]] || die "usage: $0 {check|horizon} <drive_c/HorizonXI>"
ffxi="$game/SquareEnix/FINAL FANTASY XI"

# The retail patch level the client is at. patch.cfg is the client's own record of applied
# patch groups; the newest one listed is what the login server sees at offset 0x74 of packet 0x26.
installed_client() {
  [[ -f "$ffxi/patch.cfg" ]] || { print ""; return; }
  grep -oE '\b30[0-9]{6}_[0-9]\b' "$ffxi/patch.cfg" | sort -u | tail -1
}

horizon_marketing() {
  [[ -f "$game/version.json" ]] || { print ""; return; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$game/version.json" 2>/dev/null || print ""
}

fetch_json() { curl -fsSL -A "$UA" --max-time 20 "$1"; }

case "${1:-}" in
  check)
    inst=$(installed_client); hm=$(horizon_marketing)
    latest=$(fetch_json "$API/install-game" 2>/dev/null \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["updateData"][-1]["marketingVersion"] if d.get("updateData") else d["installData"]["baseGameMarketingVersion"])' 2>/dev/null || print "")
    print "installed=${inst:-unknown} horizon=${hm:-unknown} latest=${latest:-unknown}"
    ;;

  horizon)
    command -v aria2c >/dev/null || die "aria2c is not installed (brew install aria2). HorizonXI ships updates as torrents; nothing else can fetch them."
    hm=$(horizon_marketing); [[ -n "$hm" ]] || die "no version.json in $game — is this a HorizonXI install?"
    say "installed HorizonXI $hm, asking api.horizonxi.com what is newer"
    # ver= takes the *marketing* version; the API answers with everything after it.
    plan=$(fetch_json "$API/update-game?ver=$hm" | python3 -c '
import json,sys
seen=set()
for e in json.load(sys.stdin):
    if e["updateZipName"] in seen: continue
    seen.add(e["updateZipName"])
    print("\t".join([str(e["version"]), e["marketingVersion"], e["updateZipName"], e["updateMagnetLink"], "|".join(e.get("deleteFiles",[]))]))')
    [[ -n "$plan" ]] || { say "already up to date"; exit 0; }
    dl="$game/updates"; mkdir -p "$dl"
    # Files this project puts in place (Metal renderer shims, x87 loader) that an update zip
    # may clobber. Saved and put back; Repair does the same thing more thoroughly.
    keep=(d3d8.dll d3d9.dll dxvk.conf dgVoodoo.conf)
    print -r -- "$plan" | while IFS=$'\t' read -r ver mv zip magnet dels; do
      say "update $mv ($zip)"
      if [[ ! -f "$dl/$zip" ]]; then
        aria2c --dir="$dl" --seed-time=0 --bt-stop-timeout=600 --summary-interval=30 \
               --console-log-level=warn --enable-dht=true --allow-overwrite=true "$magnet" \
          || die "torrent download of $zip failed or stalled — run again to resume, or use HorizonXI's own launcher"
        [[ -f "$dl/$zip" ]] || die "aria2 finished but $zip is not in $dl"
      fi
      tmpk=$(mktemp -d)
      for f in $keep; do
        [[ -f "$game/$f" ]] && cp "$game/$f" "$tmpk/game.$f"
        [[ -f "$ffxi/$f" ]] && cp "$ffxi/$f" "$tmpk/ffxi.$f"
      done
      say "extracting $zip"
      ditto -x -k "$dl/$zip" "$game" || die "unzip of $zip failed"
      # Their zips are rooted at HorizonXI/ sometimes; flatten if so.
      if [[ -d "$game/HorizonXI" && -f "$game/HorizonXI/version.json" ]]; then
        ditto "$game/HorizonXI" "$game" && rm -rf "$game/HorizonXI"
      fi
      if [[ -n "$dels" ]]; then
        for d in ${(s:|:)dels}; do rm -rf "$game/$d"; done
      fi
      for f in $keep; do
        [[ -f "$tmpk/game.$f" ]] && cp "$tmpk/game.$f" "$game/$f"
        [[ -f "$tmpk/ffxi.$f" ]] && cp "$tmpk/ffxi.$f" "$ffxi/$f"
      done
      rm -rf "$tmpk"
      print -r -- "{\n  \"version\": \"$mv\"\n}" > "$game/version.json"
      say "now at $mv"
    done
    say "done — client is at $(installed_client)"
    ;;
  *) die "usage: $0 {check|horizon} <drive_c/HorizonXI>" ;;
esac
