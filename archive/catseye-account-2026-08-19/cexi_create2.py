#!/usr/bin/env python3
import os, pty, re, select, sys, time, json
USER = "danielalanbates"
PASS = json.load(open(os.path.expanduser(
    "~/Library/Application Support/HorizonXI-on-Mac/accounts.json")))[USER]
WINE = "/Volumes/Games/FFXI/siku.app/Contents/SharedSupport/wine/bin/wine"
PFX  = "/Volumes/Games/FFXI/siku.app/Contents/SharedSupport/prefix10"
env = dict(os.environ); env.update(WINEPREFIX=PFX, WINEDEBUG="-all", TERM="xterm-256color")
env.pop("DYLD_FALLBACK_LIBRARY_PATH", None); env.pop("DYLD_LIBRARY_PATH", None)
pid, fd = pty.fork()
if pid == 0:
    os.execve(WINE, [WINE, r"C:\Games\CatsEyeXI\catseyexi-client\Ashita\bootloader\pol.exe",
                     "--server", "server.catseyexi.com",
                     "--user", USER, "--pass", PASS,
                     "--email", "danielalanbates@gmail.com"], env)
buf = b""; end = time.time() + 120
while time.time() < end:
    r,_,_ = select.select([fd], [], [], 1)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        buf += d
    clean = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", buf)
    if re.search(rb"successfully created|Account successfully|Failed|Invalid|already", clean, re.I):
        time.sleep(3)
        break
clean = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", buf)
print(clean[-2500:].decode("utf-8","replace"))
try: os.kill(pid, 9)
except ProcessLookupError: pass
