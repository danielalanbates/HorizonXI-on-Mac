import time, Quartz, subprocess
from AppKit import NSRunningApplication, NSWorkspace
def gw():
    for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly|Quartz.kCGWindowListExcludeDesktopElements, Quartz.kCGNullWindowID):
        if (w.get("kCGWindowOwnerName","") or "")=="wine" and w.get("kCGWindowBounds",{}).get("Width",0)>400: return w
w=gw()
if not w: print("no game window"); raise SystemExit(0)
pid=w["kCGWindowOwnerPID"]; ws=NSWorkspace.sharedWorkspace()
for app in ws.runningApplications():
    if app.activationPolicy()==0 and app.processIdentifier()!=pid: app.hide()
time.sleep(1)
for _ in range(10):
    NSRunningApplication.runningApplicationWithProcessIdentifier_(pid).activateWithOptions_(1<<1); time.sleep(1)
    if ws.frontmostApplication().processIdentifier()==pid: break
print("focus:", ws.frontmostApplication().localizedName(), flush=True)
KEY={'/':44,'s':1,'h':4,'u':32,'t':17,'d':2,'o':31,'w':13,'n':45}
def tap(code, hold=0.06):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None,code,True)); time.sleep(hold)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None,code,False)); time.sleep(0.12)
for _ in range(3):
    tap(36); time.sleep(1.2)          # enter -> open chat input
for ch in "/shutdown":
    tap(KEY[ch]); time.sleep(0.08)
time.sleep(0.5); tap(36)              # send
print("sent /shutdown", flush=True)
