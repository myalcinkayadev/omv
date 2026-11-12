// The lyrics window, like Ghostty's with its title bar hidden: rounded corners, no title,
// no buttons, the page filling it. A normal titled window underneath, so AeroSpace tiles it.
// Reads commands from stdin, one JSON object per line:
//   {"html": "<page>"} shows a page, {"js": "<script>"} runs a script in it,
//   {"background": "#rrggbb"} colors the window under the page in the theme's background.
// Prints "loaded" when a page has finished loading. Exits when stdin closes, which is how
// Hammerspoon closes it, or when the window is closed.
import AppKit
import WebKit

final class Window: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered, defer: false)
  let page = WKWebView()

  func applicationDidFinishLaunching(_ notification: Notification) {
    window.title = "Lyrics"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.backgroundColor = .black
    window.appearance = NSAppearance(named: .darkAqua)
    for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(button)?.isHidden = true
    }
    // Black until the first page arrives, rather than a white flash.
    page.setValue(false, forKey: "drawsBackground")
    page.navigationDelegate = self
    window.contentView = page
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    readCommands()
  }

  func readCommands() {
    Thread.detachNewThread {
      while let line = readLine() {
        guard let data = line.data(using: .utf8),
          let command = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { continue }
        DispatchQueue.main.async { self.run(command) }
      }
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }

  func run(_ command: [String: String]) {
    if let code = command["background"], let color = Window.color(code) { paint(color) }
    if let html = command["html"] { page.loadHTMLString(html, baseURL: nil) }
    if let script = command["js"] { page.evaluateJavaScript(script) }
  }

  // A light background gets a light title bar, so the rounded corners match it.
  func paint(_ color: NSColor) {
    window.backgroundColor = color
    let light = color.brightnessComponent > 0.5
    window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
  }

  static func color(_ code: String) -> NSColor? {
    guard code.count == 7, code.hasPrefix("#"), let value = UInt32(code.dropFirst(), radix: 16) else { return nil }
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
      blue: CGFloat(value & 0xff) / 255, alpha: 1)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    print("loaded")
    fflush(stdout)
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.terminate(nil)
  }
}

let app = NSApplication.shared
let delegate = Window()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
