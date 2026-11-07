// Helper for capture.sh. Built with swiftc on first use.
//   capture ocr <image>   prints the text found in the image, one line per text line
//   capture color         shows the macOS color sampler and prints the pick as #RRGGBB
// Exits non-zero when nothing is found or the sampler is cancelled.

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
    app.stop(nil)
    // stop only takes effect after another event, so post one.
    app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
  }
  app.run()
  return status
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "ocr" where arguments.count > 2: exit(readText(at: arguments[2]))
case "color": exit(pickColor())
default:
  FileHandle.standardError.write("usage: capture ocr <image> | capture color\n".data(using: .utf8)!)
  exit(2)
}
