// Helper for translate.sh. Built with swiftc on first use.
//   translate names <code>...  prints each language's name, one a line
//   translate languages <from>  prints the languages <from> can go into, one a line:
//                          "code<TAB>Name<TAB>installed", or "supported" when not downloaded
//   translate download <from> <to>  opens a small window where macOS asks to download the
//                          two languages; prints "ready" and exits 0 once they're
//                          downloaded, exits 1 when the window is closed first
// The two below read the text on stdin.
//   translate detect       prints the text's language code, or "unknown"
//   translate <from> <to>  prints "ok<TAB>From<TAB>To" and the translation on the lines
//                          after it, or "missing<TAB>From<TAB>To" when a language isn't
//                          downloaded in Translation Languages. From and To are the
//                          languages' names.
// Translation runs on the Mac with Apple's own models: nothing is sent anywhere. A helper
// can't download a language, only a window in an app can, so the user does that once.

import AppKit
import Foundation
import NaturalLanguage
import SwiftUI
import Translation

let arguments = CommandLine.arguments

func name(_ code: String) -> String {
  Locale.current.localizedString(forIdentifier: code) ?? code
}

if arguments.count >= 3 && arguments[1] == "names" {
  for code in arguments.dropFirst(2) { print(name(code)) }
  exit(0)
}

if arguments.count == 3 && arguments[1] == "languages" {
  let availability = LanguageAvailability()
  let source = Locale.Language(identifier: arguments[2])
  for language in await availability.supportedLanguages {
    let code = language.minimalIdentifier
    switch await availability.status(from: source, to: language) {
    case .installed: print("\(code)\t\(name(code))\tinstalled")
    case .supported: print("\(code)\t\(name(code))\tsupported")
    default: continue
    }
  }
  exit(0)
}

// Only a window in an app may download a language: preparing a translation there makes
// macOS show its own download sheet.
struct DownloadView: View {
  let configuration: TranslationSession.Configuration

  var body: some View {
    Text("Downloading languages to translate on this Mac…")
      .frame(width: 420, height: 120)
      .translationTask(configuration) { session in
        do {
          try await session.prepareTranslation()
          print("ready")
          exit(0)
        } catch {
          exit(1)
        }
      }
  }
}

final class DownloadWindow: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let configuration: TranslationSession.Configuration
  var window: NSWindow?

  init(from: String, to: String) {
    configuration = TranslationSession.Configuration(source: Locale.Language(identifier: from),
                                                     target: Locale.Language(identifier: to))
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Translation languages"
    window.contentView = NSHostingView(rootView: DownloadView(configuration: configuration))
    window.delegate = self
    window.level = .floating
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
  }

  func windowWillClose(_ notification: Notification) {
    exit(1)
  }
}

if arguments.count == 4 && arguments[1] == "download" {
  let app = NSApplication.shared
  let delegate = DownloadWindow(from: arguments[2], to: arguments[3])
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
}

let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)

if arguments.count == 2 && arguments[1] == "detect" {
  let recognizer = NLLanguageRecognizer()
  recognizer.processString(text)
  print(recognizer.dominantLanguage?.rawValue ?? "unknown")
  exit(0)
}

guard arguments.count == 3 else {
  FileHandle.standardError.write(Data("usage: translate detect | translate <from> <to>\n".utf8))
  exit(2)
}

let (from, to) = (arguments[1], arguments[2])
let session = TranslationSession(installedSource: Locale.Language(identifier: from),
                                 target: Locale.Language(identifier: to))
do {
  let response = try await session.translate(text)
  print("ok\t\(name(from))\t\(name(to))")
  print(response.targetText)
} catch TranslationError.notInstalled {
  print("missing\t\(name(from))\t\(name(to))")
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
