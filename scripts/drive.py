#!/usr/bin/env python3
"""Locate the FINAL FANTASY XI window and click points inside it in *relative* coords.

Hardcoded screen coordinates break the moment the window moves. Everything here is
expressed as a fraction of the game's client area.
"""
import sys, time, subprocess, Quartz


def bounds():
    wins = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID)
    for w in wins:
        name = w.get("kCGWindowName", "") or ""
        owner = w.get("kCGWindowOwnerName", "") or ""
        if "FINAL FANTASY" in name or ("wine" in owner.lower() and w.get("kCGWindowLayer") == 0):
            b = w["kCGWindowBounds"]
            return dict(x=b["X"], y=b["Y"], w=b["Width"], h=b["Height"],
                        id=w["kCGWindowNumber"], name=name, owner=owner)
    return None


def click_rel(fx, fy):
    b = bounds()
    if not b:
        raise SystemExit("no game window")
    # client area sits below the ~28pt title bar
    top = b["y"] + 28
    h = b["h"] - 28
    x, y = b["x"] + fx * b["w"], top + fy * h
    p = Quartz.CGPointMake(x, y)
    for kind, btn in ((Quartz.kCGEventMouseMoved, 0),
                      (Quartz.kCGEventLeftMouseDown, Quartz.kCGMouseButtonLeft),
                      (Quartz.kCGEventLeftMouseUp, Quartz.kCGMouseButtonLeft)):
        Quartz.CGEventPost(Quartz.kCGHIDEventTap,
                           Quartz.CGEventCreateMouseEvent(None, kind, p, btn))
        time.sleep(0.08)
    return x, y


def focus():
    subprocess.run(["osascript", "-e",
                    'tell application "System Events" to set frontmost of '
                    '(first process whose name contains "wine") to true'], capture_output=True)
    time.sleep(0.5)


if __name__ == "__main__":
    if sys.argv[1] == "bounds":
        print(bounds())
    else:
        focus()
        for a in sys.argv[1:]:
            if a.startswith("wait:"):
                time.sleep(float(a[5:]))
            else:
                fx, fy = a.split(",")
                print("clicked", click_rel(float(fx), float(fy)))
