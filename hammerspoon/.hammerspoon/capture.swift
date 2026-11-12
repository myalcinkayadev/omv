// Helper for capture.sh. Built with swiftc on first use.
//   capture ocr <image>   prints the text found in the image, one line per text line
//   capture qr <image>    prints the QR codes found in the image, one per line
//   capture color         shows the macOS color sampler and prints the pick as #RRGGBB
//   capture select        dims the screen under the pointer, lets a region be dragged, and
//                         prints it as x,y,w,h for screencapture -R; Escape cancels
// Exits non-zero when nothing is found or the sampler or selection is cancelled.

import AppKit
import Vision

func readText(at path: String) -> Int32 {
  guard let image = NSImage(contentsOfFile: path),
        let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true
  request.automaticallyDetectsLanguage = true
  try? VNImageRequestHandler(cgImage: picture).perform([request])
  let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
  guard !lines.isEmpty else { return 1 }
  print(lines.joined(separator: "\n"))
  return 0
}

func readQRCodes(at path: String) -> Int32 {
  guard let image = NSImage(contentsOfFile: path),
        let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
  let request = VNDetectBarcodesRequest()
  request.symbologies = [.qr]
  try? VNImageRequestHandler(cgImage: picture).perform([request])
  let codes = (request.results ?? []).compactMap { $0.payloadStringValue }
  guard !codes.isEmpty else { return 1 }
  print(codes.joined(separator: "\n"))
  return 0
}

// Ends app.run(): stop only takes effect after another event, so post one.
func stopRunning(_ app: NSApplication) {
  app.stop(nil)
  app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
}

// A borderless window can't take key presses unless it says so; Escape needs them.
final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

// The screen dimmed, with the dragged region cut out of the dimming and outlined.
final class RegionView: NSView {
  var start: NSPoint?
  var current: NSPoint?
  var finished: ((NSRect?) -> Void)?

  var region: NSRect? {
    guard let start, let current else { return nil }
    let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    return rect.width >= 4 && rect.height >= 4 ? rect : nil
  }

  override var acceptsFirstResponder: Bool { true }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

  override func mouseDown(with event: NSEvent) {
    start = convert(event.locationInWindow, from: nil)
    current = start
  }

  override func mouseDragged(with event: NSEvent) {
    current = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    current = convert(event.locationInWindow, from: nil)
    finished?(region)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { finished?(nil) }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.35).setFill()
    bounds.fill()
    guard let region else { return }
    NSColor.clear.setFill()
    region.fill(using: .copy)
    NSColor.white.setStroke()
    NSBezierPath(rect: region).stroke()
  }
}

// screencapture -R counts from the top left of the main display, AppKit from its bottom left.
func selectRegion() -> Int32 {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let pointer = NSEvent.mouseLocation
  guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main,
        let mainScreen = NSScreen.screens.first else { return 1 }
  let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
  window.level = .screenSaver
  window.isOpaque = false
  window.backgroundColor = .clear
  let view = RegionView(frame: NSRect(origin: .zero, size: screen.frame.size))
  window.contentView = view
  var status: Int32 = 1
  view.finished = { region in
    if let region {
      let left = screen.frame.minX + region.minX
      let top = mainScreen.frame.maxY - (screen.frame.minY + region.maxY)
      print("\(Int(left)),\(Int(top)),\(Int(region.width)),\(Int(region.height))")
      status = 0
    }
    window.orderOut(nil)
    stopRunning(app)
  }
  window.makeKeyAndOrderFront(nil)
  window.makeFirstResponder(view)
  app.activate(ignoringOtherApps: true)
  app.run()
  return status
}

func pickColor() -> Int32 {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  var status: Int32 = 1
  NSColorSampler().show { picked in
    if let color = picked?.usingColorSpace(.sRGB) {
      let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
      print(String(format: "#%02X%02X%02X", channel(color.redComponent), channel(color.greenComponent), channel(color.blueComponent)))
      status = 0
    }
    stopRunning(app)
  }
  app.run()
  return status
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "ocr" where arguments.count > 2: exit(readText(at: arguments[2]))
case "qr" where arguments.count > 2: exit(readQRCodes(at: arguments[2]))
case "color": exit(pickColor())
case "select": exit(selectRegion())
default:
  FileHandle.standardError.write("usage: capture ocr <image> | capture qr <image> | capture color | capture select\n".data(using: .utf8)!)
  exit(2)
}
