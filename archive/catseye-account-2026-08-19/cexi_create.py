#!/usr/bin/env python3
"""Drive CatsEye's xiloader (pol.exe) TUI over a pty to create an account."""
import os, pty, re, select, sys, time, json

USER = "danielalanbates"
PASS = json.load(open(os.path.expanduser(
    "~/Library/Application Support/HorizonXI-on-Mac/accounts.json")))[USER]

WINE = "/Volumes/Games/FFXI/siku.app/Contents/SharedSupport/wine/bin/wine"
PFX  = "/Volumes/Games/FFXI/siku.app/Contents/SharedSupport/prefix10"
EXE  = r"C:\Games\CatsEyeXI\catseyexi-client\Ashita\bootloader\pol.exe"

env = dict(os.environ)
env.update(WINEPREFIX=PFX, WINEDEBUG="-all", TERM="xterm-256color")
env.pop("DYLD_FALLBACK_LIBRARY_PATH", None); env.pop("DYLD_LIBRARY_PATH", None)

pid, fd = pty.fork()
if pid == 0:
    os.execve(WINE, [WINE, EXE, "--server", "server.catseyexi.com"], env)

log = open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/cexi_create.log", "wb")
buf = b""
def feed(timeout):
    global buf
    end = time.time() + timeout
    while time.time() < end:
        r,_,_ = select.select([fd], [], [], 0.5)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return False
            if not d: return False
            buf += d; log.write(d); log.flush()
    return True

def send(s, note=""):
    log.write(("\n<<SEND %r %s>>\n" % (s, note)).encode()); log.flush()
    os.write(fd, s.encode())

def wait_for(pat, timeout=60):
    global buf
    end = time.time() + timeout
    rx = re.compile(pat.encode(), re.I)
    while time.time() < end:
        clean = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", buf)
        if rx.search(clean): return True
        if not feed(1): return False
    return False

if not wait_for(r"Create.?New.?Account", 90):
    print("NO MENU"); sys.exit(1)
time.sleep(1)
send("\x1b[B\r", "arrow down + enter -> Create New Account")
# account creation prompts (LSB xiloader): username, password, repeat password
if wait_for(r"user.?name", 30):
    time.sleep(0.5); send(USER + "\r", "username")
if wait_for(r"password", 30):
    time.sleep(0.5); send(PASS + "\r", "password")
time.sleep(1)
# repeat password prompt
buf = b""
if wait_for(r"password|repeat|again|confirm", 15):
    time.sleep(0.5); send(PASS + "\r", "confirm password")
feed(20)
clean = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", buf)
tail = clean[-3000:].decode("utf-8", "replace")
print(tail)
ok = re.search(r"successfully|created", tail, re.I)
print("RESULT:", "CREATED" if ok else "UNKNOWN")
try: os.kill(pid, 9)
except ProcessLookupError: pass
