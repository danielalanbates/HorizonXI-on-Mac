import sys, time, Quartz, subprocess
from AppKit import NSRunningApplication, NSWorkspace
S="/private/tmp/claude-501/-Users-daniel/5430f34a-6e9c-43dc-ba9c-a71b92979877/scratchpad"
label=sys.argv[1]; steps=int(sys.argv[2]) if len(sys.argv)>2 else 1
def gw():
    for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements, Quartz.kCGNullWindowID):
        if (w.get("kCGWindowOwnerName","") or "")=="wine" and w.get("kCGWindowBounds",{}).get("Width",0)>400: return w
w=gw()
if not w: print("NO WINDOW"); raise SystemExit(1)
pid=w["kCGWindowOwnerPID"]
ws=NSWorkspace.sharedWorkspace()
for app in ws.runningApplications():
    n=app.localizedName() or ""
    if app.activationPolicy()==0 and app.processIdentifier()!=pid and n!="wine":
        app.hide()
time.sleep(1.5)
ok=False
for i in range(12):
    NSRunningApplication.runningApplicationWithProcessIdentifier_(pid).activateWithOptions_(1<<1)
    time.sleep(1.2)
    f=ws.frontmostApplication()
    if f.processIdentifier()==pid: ok=True; break
print("focus:", ok, ws.frontmostApplication().localizedName(), flush=True)
def press(k,hold=0.12):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None,k,True)); time.sleep(hold)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None,k,False)); time.sleep(1.0)
for i in range(steps):
    press(36); time.sleep(14)
w2=gw() or w
subprocess.run(["screencapture","-x","-o","-l",str(w2["kCGWindowNumber"]), f"{S}/shot_{label}.png"])
from PIL import Image
im=Image.open(f"{S}/shot_{label}.png"); im.thumbnail((900,580)); im.save(f"{S}/shot_{label}_s.png")
print("SHOT_OK")
