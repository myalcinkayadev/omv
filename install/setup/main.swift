// Starts the setup assistant. With --install <repo> it runs omv's install first, as omv install
// opens it; without, as omv setup does, it goes straight to the permissions.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "omv Setup"
    let arguments = CommandLine.arguments
    let installer = arguments.firstIndex(of: "--install").flatMap { $0 + 1 < arguments.count ? Installer(repo: arguments[$0 + 1]) : nil }
    window.contentView = NSHostingView(rootView: SetupView(state: SetupState(installer: installer)))
    window.backgroundColor = .black
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
