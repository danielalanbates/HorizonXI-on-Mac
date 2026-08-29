// winecursor.dylib -- keep the mouse cursor visible while FFXI runs under Wine on macOS.
//
// FFXI calls ShowCursor(FALSE) every frame and draws its own cursor sprite, which DXVK does not
// render, so the pointer vanishes inside the game window. Wine's Mac driver (winemac.drv) carries
// that hide out with AppKit's +[NSCursor hide] -- confirmed by the driver's own symbols
// (winemac.so references the NSCursor hide/unhide selectors and NO CGDisplay{Show,Hide}Cursor
// call). This dylib is inserted into the Wine process with DYLD_INSERT_LIBRARIES, exactly like
// audio/audiofollow.c, and neutralises +[NSCursor hide]/+[NSCursor unhide] so the system arrow
// stays visible.
//
// It is the native-layer equivalent of the `winecursor` Ashita addon holding the Win32
// show-count at +1 -- and, unlike an Ashita addon, it is a platform compatibility shim, not
// something a private server's addon allowlist governs: it touches no game, Wine, or Square Enix
// data, sends nothing, and only stops the OS cursor from being hidden. That is the whole point of
// doing it here rather than as an addon (see docs/CURSOR.md): the fix works on HorizonXI without
// loading an unlisted addon.
//
// Copyright (c) 2026 Bates LLC. All rights reserved.

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <os/log.h>

// The cursor's hide-count is a process-global inside AppKit. Never incrementing it (hide) and
// never decrementing it (unhide) leaves it at its default of 0 -- cursor visible -- for the life
// of the process, whatever the game asks for.
static void winecursor_noop(id self, SEL _cmd) { (void)self; (void)_cmd; }

__attribute__((constructor))
static void winecursor_init(void) {
    Class cls = objc_getClass("NSCursor");
    if (cls == NULL) return;                 // no AppKit in this process -- nothing to do
    SEL sels[2] = { @selector(hide), @selector(unhide) };
    int patched = 0;
    for (int i = 0; i < 2; i++) {
        Method m = class_getClassMethod(cls, sels[i]);   // class methods, i.e. +[NSCursor ...]
        if (m != NULL) { method_setImplementation(m, (IMP)winecursor_noop); patched++; }
    }
    os_log(OS_LOG_DEFAULT, "winecursor: neutralised %d NSCursor hide/unhide selector(s); cursor stays visible", patched);
}
