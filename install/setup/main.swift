// Starts the setup assistant. With --install <repo> it runs omv's install first, as omv install
// opens it; with --repo <repo>, as omv setup does, it goes straight to the permissions.

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
    func value(_ flag: String) -> String? {
      arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }
    let installer = value("--install").map { Installer(repo: $0) }
    let repo = value("--install") ?? value("--repo")
    window.contentView = NSHostingView(rootView: SetupView(state: SetupState(installer: installer, repo: repo)))
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
