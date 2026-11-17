// Starts the setup assistant. With --install <repo> it runs omv's install first, as omv install
// opens it, with --no-apps passed on; with --repo <repo>, as omv setup does, it goes straight
// to the permissions.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow?
  var installer: Installer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: SetupModel.windowSize),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "omv Setup"
    window.delegate = self
    let arguments = CommandLine.arguments
    func value(_ flag: String) -> String? {
      arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }
    let installer = value("--install").map { Installer(repo: $0, withoutApps: arguments.contains("--no-apps")) }
    self.installer = installer
    let repo = value("--install") ?? value("--repo")
    window.contentView = NSHostingView(rootView: SetupView(state: SetupState(installer: installer, repo: repo)))
    window.backgroundColor = .black
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  // Closing the window quits, through the same question, so a kept install keeps its window.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(nil)
    return false
  }

  // Quitting, or closing the window, mid-install would leave omv half installed: ask first,
  // and stop the install when the answer is to quit.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let installer, installer.isRunning else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "omv is still installing"
    alert.informativeText = "Quitting stops the install part way. Run omv install again to finish it."
    alert.addButton(withTitle: "Keep installing")
    alert.addButton(withTitle: "Quit")
    guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
    installer.stop()
    return .terminateNow
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
