# Building d3d8to9 on macOS, and instrumenting it

`d3d8to9` sits between FFXI and DXVK and was the last unmeasured layer in the chain. It ships as
an MSVC build; this is how to cross-build it on a Mac with mingw so it can be modified and
profiled. The answer it gave — 6% of the frame — is in `docs/INWORLD-STALL.md`.

## Build

```sh
git clone --depth 1 https://github.com/crosire/d3d8to9.git
cd d3d8to9
cat > mingw-i686.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86)
set(CMAKE_C_COMPILER   i686-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER i686-w64-mingw32-g++)
set(CMAKE_RC_COMPILER  i686-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
cmake -B build -DCMAKE_TOOLCHAIN_FILE=mingw-i686.cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-static-libgcc -static-libstdc++" \
      -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc -static-libstdc++ -static"
cmake --build build -j8
i686-w64-mingw32-strip -o d3d8.dll build/d3d8.dll
```

**The static-link flags are not optional.** Without them the DLL imports `libgcc_s_sjlj-1.dll`,
which is not in the prefix, so the DLL fails to load — and the failure surfaces as
`[E] Injection failed!` from Ashita, or as wine quietly substituting its own builtin `d3d8`
(visible with `WINEDEBUG=+module` as `get_load_order_value got standard key n for L"*d3d8"`
followed by wine's own d3d8 loading anyway). Exports are correct either way, so comparing
export tables will not find this; compare `objdump -p | grep "DLL Name:"` instead.

It also needs the `api-ms-win-crt-*` forwarders in `syswow64`, exactly as the MSVC build does.
`Renderer.swift` already copies those.

## Instrumenting it

`D3D8TO9_PROBE=<path>` in our tree writes one CSV row per second with, for every entry point:
calls/second and milliseconds/second spent inside it; a bucketed histogram of the gaps *between*
entry points (which is FFXI plus Ashita, everything above this layer); and long pauses
attributed to the call that follows them.

The probe is a single header, `source/d3d8to9_probe.hpp`, plus one `D3D8TO9_TIME(CallX);` line
at the top of each method body — added mechanically. It is not upstreamed and is not in this
repo's `vendor/`; the shipped `vendor/d3d8to9.dll` is still the stock MSVC build.

## An observation that did not survive

The mingw build measured **27.48 fps** on the rules screen against **23.78 fps** for the shipped
MSVC build, which looked like a free ~15% win. It is not: a later run of the *MSVC* build on the
same scene measured **26.97 fps**. That scene varies between roughly 23.8 and 27.5 run to run —
most likely with how warm DXVK's pipeline state cache is — and the apparent difference was
entirely inside that spread.

Recorded because it is exactly the kind of single-run number this project has been burned by
before. If it is ever worth revisiting, alternate the two builds three times each in one sitting
and compare medians:

```sh
for i in 1 2 3; do
  cp vendor/d3d8to9.dll  <game>/d3d8.dll   # and <game>/bootloader/d3d8.dll
  ./bench.py --tag msvc-$i  --enters 0 --boot-wait 65 --sample 30
  cp build/d3d8.dll      <game>/d3d8.dll   # and bootloader
  ./bench.py --tag mingw-$i --enters 0 --boot-wait 65 --sample 30
done
```

## A warning about the prefix registry

Do not rewrite `user.reg` or `system.reg` by parsing and re-emitting them. Doing that here
produced a file wine could no longer read the `DllOverrides` section out of, so `*d3d8` stopped
being `native`, wine silently substituted its own builtin d3d8, and DXVK stopped loading
entirely — while the game still launched and rendered, so nothing looked broken except that
every measurement came back empty. The symptom in `WINEDEBUG=+module` is:

```
get_load_order got hardcoded default for L"C:\HorizonXI\bootloader\d3d8.dll"
```

A working prefix says `get_load_order_value got standard key n for L"*d3d8"` instead. Snapshot
both hives before touching them, and prefer `wine reg add` despite it being slow.
