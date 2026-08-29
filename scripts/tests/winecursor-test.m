// Verifies winecursor.dylib neutralises +[NSCursor hide]. Build native, run with and without the
// dylib inserted: without it, hide() drops CGCursorIsVisible() to 0; with it, it stays 1.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        int before = CGCursorIsVisible();
        [NSCursor hide];
        int after = CGCursorIsVisible();
        [NSCursor unhide];   // restore, in case the swizzle is NOT active
        printf("visible before=%d after_hide=%d  => hide %s\n",
               before, after, after ? "NEUTRALISED (cursor stayed visible)" : "took effect (cursor hidden)");
        return after ? 0 : 1;
    }
}
