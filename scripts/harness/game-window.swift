// Window helper for the HorizonXI menu-run driver.
//
//   game-window find PID            print the game's window id and bounds as JSON
//   game-window activate PID        bring the game window to the front
//   game-window return PID          send exactly one Return to the game window
//
// The Return path clicks the title bar, activates the application, and then refuses to post
// the key unless the game is frontmost. It posts one key press and exits. It never reads the
// process argument list, so account credentials in the loader command line are never touched.
//
// Build: swiftc -O -o game-window game-window.swift   (menu-run.py does this on demand)

import AppKit
import CoreGraphics
import Foundation

struct GameWindow {
    let id: CGWindowID
    let bounds: CGRect
    let name: String
}

func usage() -> Never {
    FileHandle.standardError.write("usage: game-window find|activate|return PID\n".data(using: .utf8)!)
    exit(64)
}

func findWindow(pid: Int32) -> GameWindow? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    var best: GameWindow?
    for window in windows {
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else { continue }
        let name = (window[kCGWindowName as String] as? String) ?? ""
        // The lobby titles the window "FINAL FANTASY XI"; in the world Ashita may retitle it,
        // so accept any sizeable window the game process owns and prefer the largest.
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard name.uppercased().contains("FINAL FANTASY XI") || layer == 0 else { continue }
        guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dictionary),
              let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
        guard bounds.width >= 400, bounds.height >= 300 else { continue }
        let candidate = GameWindow(id: CGWindowID(number.uint32Value), bounds: bounds, name: name)
        if let current = best, current.bounds.width * current.bounds.height
            >= bounds.width * bounds.height {
            continue
        }
        best = candidate
    }
    return best
}

func frontmostPid() -> Int32 {
    NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
}

func activate(pid: Int32, window: GameWindow) -> Bool {
    // A click on the title bar focuses a Wine window more reliably than activation alone.
    let point = CGPoint(x: window.bounds.midX, y: window.bounds.minY + 12)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return false }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }
    Thread.sleep(forTimeInterval: 0.8)
    if frontmostPid() != pid, let app = NSRunningApplication(processIdentifier: pid) {
        _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.8)
    }
    return frontmostPid() == pid
}

guard CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[2]) else { usage() }
let command = CommandLine.arguments[1]

guard let window = findWindow(pid: pid) else {
    FileHandle.standardError.write("no visible FINAL FANTASY XI window for pid \(pid)\n".data(using: .utf8)!)
    exit(1)
}

switch command {
case "find":
    let payload: [String: Any] = [
        "pid": Int(pid), "window_id": Int(window.id), "name": window.name,
        "x": window.bounds.minX, "y": window.bounds.minY,
        "width": window.bounds.width, "height": window.bounds.height,
        "frontmost": frontmostPid() == pid,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
case "activate":
    guard activate(pid: pid, window: window) else {
        FileHandle.standardError.write("game pid \(pid) is not frontmost, frontmost pid is \(frontmostPid())\n".data(using: .utf8)!)
        exit(1)
    }
    print("game pid \(pid) is frontmost")
case "return":
    guard activate(pid: pid, window: window) else {
        FileHandle.standardError.write("refusing Return: game pid \(pid) is not frontmost, frontmost pid is \(frontmostPid())\n".data(using: .utf8)!)
        exit(1)
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else { exit(1) }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.1)
    up.post(tap: .cghidEventTap)
    print("sent one Return to game pid \(pid)")
default:
    usage()
}
