// Helper for translate.sh. Built with swiftc on first use. Both read the text on stdin.
//   translate detect       prints the text's language code, or "unknown"
//   translate <from> <to>  prints "ok<TAB>From<TAB>To" and the translation on the lines
//                          after it, or "missing<TAB>From<TAB>To" when a language isn't
//                          downloaded in Translation Languages. From and To are the
//                          languages' names.
// Translation runs on the Mac with Apple's own models: nothing is sent anywhere. A helper
// can't download a language, only a window in an app can, so the user does that once.

import Foundation
import NaturalLanguage
import Translation

let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
let arguments = CommandLine.arguments

func name(_ code: String) -> String {
  Locale.current.localizedString(forLanguageCode: code) ?? code
}

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
