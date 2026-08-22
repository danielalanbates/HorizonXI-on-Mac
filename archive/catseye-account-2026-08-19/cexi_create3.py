#!/usr/bin/env python3
"""Create CatsEye account: probe TUI navigation until highlight lands on Create New Account."""
import os, pty, re, select, sys, time, json
USER = "danielalanbates"
PASS = json.load(open(os.path.expanduser(
    "~/Library/Application Support/HorizonXI-on-Mac/accounts.json")))[USER]
WINE = "/Volumes/Games/FFXI/siku.app/Contents/SharedSupport/wine/bin/wine"
PFX  = "/Volumes/Games/FFXI/siku.app/Contents/SharedSupport/prefix10"
env = dict(os.environ); env.update(WINEPREFIX=PFX, WINEDEBUG="-all", TERM="xterm-256color",
                                   LINES="40", COLUMNS="100")
env.pop("DYLD_FALLBACK_LIBRARY_PATH", None); env.pop("DYLD_LIBRARY_PATH", None)
pid, fd = pty.fork()
if pid == 0:
    os.execve(WINE, [WINE, r"C:\Games\CatsEyeXI\catseyexi-client\Ashita\bootloader\pol.exe",
                     "--server", "server.catseyexi.com"], env)
import fcntl, termios, struct
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
log = open("/tmp/cexi3.log", "wb")
buf = b""
def drain(t):
    global buf
    end = time.time() + t
    got = b""
    while time.time() < end:
        r,_,_ = select.select([fd], [], [], 0.3)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return got
            if not d: return got
            buf += d; got += d; log.write(d); log.flush()
    return got

def strip(b): return re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", b)

def selected(frame):
    # last inverse-video region content in the most recent frame
    hits = re.findall(rb"\x1b\[7m([^\x1b]*)\x1b\[27m", frame)
    return b"|".join(hits[-6:])

def send(s):
    log.write(b"\n<<SEND %r>>\n" % s.encode()); log.flush()
    os.write(fd, s.encode())

# wait for menu
end = time.time() + 90
while time.time() < end:
    drain(1)
    if b"CreateNewAccount" in strip(buf).replace(b" ", b""): break
else:
    print("NO MENU"); sys.exit(1)
time.sleep(1); buf = b""

on_create = False
for key, name in [("\x1b[B","down"), ("\x1bOB","down-appmode"), ("j","j"), ("\t","tab"), ("2","two")]:
    send(key); frame = drain(2)
    sel = selected(frame)
    print(name, "->", strip(sel)[:60])
    if b"Create" in strip(sel).replace(b" ", b""):
        on_create = True; break
if not on_create:
    # mouse click: find row of Create item is unknowable reliably; try SGR clicks on rows 2-12, col 10
    for row in range(2, 14):
        send("\x1b[<0;10;%dM\x1b[<0;10;%dm" % (row, row))
        frame = drain(1.2)
        sel = selected(frame)
        if b"Create" in strip(sel).replace(b" ", b""):
            print("mouse row", row, "selected Create"); on_create = True; break
if not on_create:
    print("COULD NOT SELECT"); sys.exit(1)

send("\r")
drain(2)
# prompts
end = time.time() + 60
stage = 0
sent_stages = []
while time.time() < end and stage < 3:
    frame = drain(1)
    txt = strip(buf).replace(b" ", b"").lower()
    if stage == 0 and re.search(rb"username|enterauser", txt):
        time.sleep(0.5); send(USER + "\r"); stage = 1; buf = b""; sent_stages.append("user")
    elif stage == 1 and b"password" in txt:
        time.sleep(0.5); send(PASS + "\r"); stage = 2; buf = b""; sent_stages.append("pass")
    elif stage == 2 and re.search(rb"password|repeat|confirm|again", txt):
        time.sleep(0.5); send(PASS + "\r"); stage = 3; sent_stages.append("pass2")
drain(15)
out = strip(buf).decode("utf-8","replace")
print("stages:", sent_stages)
print(out[-2000:])
print("RESULT:", "CREATED" if re.search(r"successfully", out, re.I) else "UNKNOWN")
try: os.kill(pid, 9)
except ProcessLookupError: pass
