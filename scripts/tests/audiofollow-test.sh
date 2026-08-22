#!/bin/zsh
# A/B the audiofollow dylib: pin a HALOutput unit to the current default device (what wine does),
# switch the Mac's sound output half way through, and see whether the unit follows.
#
#   ./audiofollow-test.sh            # both runs, arm64
#   ./audiofollow-test.sh x86_64     # both runs under Rosetta, which is what wine actually is
#
# GOTCHA: do not launch the x86_64 binary through `arch -x86_64`. `arch` is a system binary, so
# dyld strips DYLD_INSERT_LIBRARIES across the exec and the dylib silently never loads. Run the
# x86_64-only binary directly and let Rosetta pick it up.
set -euo pipefail
REPO="${0:A:h:h:h}"
ARCH="${1:-arm64}"
DYLIB="$REPO/app/Resources/audiofollow.dylib"
[[ -f "$DYLIB" ]] || "$REPO/scripts/build-audiofollow.sh"

BIN=$(mktemp -d)/aftest
clang -arch "$ARCH" -O2 -o "$BIN" "$REPO/scripts/tests/audiofollow-test.c" \
      -framework AudioToolbox -framework CoreAudio

helper=$(mktemp -d)
cat > "$helper/dev.c" <<'EOF'
#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char**argv){
  AudioObjectPropertyAddress a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
  if(argc<2){AudioDeviceID d=0;UInt32 s=sizeof(d);AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&s,&d);printf("%u\n",(unsigned)d);return 0;}
  AudioDeviceID d=(AudioDeviceID)atoi(argv[1]);
  return AudioObjectSetPropertyData(kAudioObjectSystemObject,&a,0,NULL,sizeof(d),&d)!=noErr;
}
EOF
clang -O2 -o "$helper/dev" "$helper/dev.c" -framework CoreAudio

# Two real output devices are needed; the test switches between them and puts yours back.
list=$(system_profiler SPAudioDataType >/dev/null 2>&1; true)
ORIG=$("$helper/dev")
echo "your output device is $ORIG — it will be restored at the end"
echo "pick two output device ids from /tmp/lsdev or System Settings, then:"
echo "  A=<id1> B=<id2> $0 $ARCH"
A="${A:-}"; B="${B:-}"
if [[ -z "$A" || -z "$B" ]]; then echo "set A= and B= to two output device ids"; exit 2; fi

run() {  # run(label, insert?)
  "$helper/dev" "$A"; sleep 1
  if [[ "$2" == "yes" ]]; then
    DYLD_INSERT_LIBRARIES="$DYLIB" FFXI_AUDIOFOLLOW_DEBUG=1 "$BIN" 8 > "/tmp/af_$1.log" 2>&1 &
  else
    "$BIN" 8 > "/tmp/af_$1.log" 2>&1 &
  fi
  sleep 3; "$helper/dev" "$B"; sleep 6
  echo "=== $1 ==="; cat "/tmp/af_$1.log"
}
run without no
run with   yes
"$helper/dev" "$ORIG"
echo "restored output device $ORIG"
