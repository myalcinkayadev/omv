// Dictation helper: hears speech on the Mac with macOS's own models, nothing sent anywhere.
// Usage:
//   dictate locales                       transcriber<tab>en-US …, dictation<tab>tr-TR …, installed<tab>…,
//                                         microphone<tab>granted, and name<tab>tr-TR<tab>Turkish (Türkiye) each
//   dictate install <locale> <engine>     gets the language's model: progress<tab>N, then ready
//   dictate listen <locale> <engine>      records until "stop" or "cancel" on stdin
// engine is transcriber (SpeechTranscriber) or dictation (DictationTranscriber, more languages).
// While listening it prints, one per line: progress<tab>N while a model downloads, ready once
// recording, level<tab>dB about twenty times a second, partial<tab>text as words come,
// and after "stop" final<tab>text, everything heard. problem<tab>no-microphone, no-input or
// language when it can't. "cancel", or stdin closing, ends it without a final line.
import AVFoundation
import Foundation
import Speech

func emit(_ kind: String, _ value: String = "") {
  print(kind + "\t" + value.replacingOccurrences(of: "\n", with: " "))
  fflush(stdout)
}

func makeModule(_ localeId: String, _ engine: String) async -> (any SpeechModule)? {
  let wanted = Locale(identifier: localeId)
  if engine == "transcriber" {
    let listed = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted),
          listed.contains(locale.identifier(.bcp47)) else { return nil }
    return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
  }
  guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: wanted) else { return nil }
  return DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                              reportingOptions: [.volatileResults], attributeOptions: [])
}

// Gets the module's model when it isn't on the Mac yet, printing its progress.
func install(_ module: any SpeechModule) async throws {
  guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
  let progress = request.progress
  let reporter = Task {
    var last = -1
    while !Task.isCancelled {
      let percent = Int(progress.fractionCompleted * 100)
      if percent != last { emit("progress", String(percent)); last = percent }
      try? await Task.sleep(for: .milliseconds(250))
    }
  }
  defer { reporter.cancel() }
  try await request.downloadAndInstall()
}

func locales() async {
  let transcriber = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
  let dictation = await DictationTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
  let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
    + DictationTranscriber.installedLocales.map { $0.identifier(.bcp47) }
  emit("transcriber", transcriber.joined(separator: " "))
  emit("dictation", dictation.joined(separator: " "))
  emit("installed", Array(Set(installed)).sorted().joined(separator: " "))
  let access: [AVAuthorizationStatus: String] = [.authorized: "granted", .denied: "denied", .restricted: "denied"]
  emit("microphone", access[AVCaptureDevice.authorizationStatus(for: .audio)] ?? "undetermined")
  for id in Set(transcriber + dictation).sorted() {
    emit("name", id + "\t" + (Locale.current.localizedString(forIdentifier: id) ?? id))
  }
}

// The words heard so far: each finished stretch, then the one still being heard.
final class Heard: @unchecked Sendable {
  private let lock = NSLock()
  private var settled: [String] = []
  private var current = ""

  func add(_ text: String, final: Bool) -> String {
    lock.lock(); defer { lock.unlock() }
    if final { settled.append(text); current = "" } else { current = text }
    return all(including: current)
  }

  func finished() -> String {
    lock.lock(); defer { lock.unlock() }
    return all(including: current)
  }

  private func all(including tail: String) -> String {
    (settled + [tail]).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
  }
}

func listen(_ module: any SpeechModule) async throws {
  guard await AVCaptureDevice.requestAccess(for: .audio) else { emit("problem", "no-microphone"); exit(1) }
  try await install(module)
  let analyzer = SpeechAnalyzer(modules: [module])
  guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
    emit("problem", "no-input"); exit(1)
  }
  let engine = AVAudioEngine()
  let node = engine.inputNode
  let micFormat = node.outputFormat(forBus: 0)
  guard micFormat.channelCount > 0, let converter = AVAudioConverter(from: micFormat, to: format) else {
    emit("problem", "no-input"); exit(1)
  }
  let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
  var lastLevel = Date.distantPast
  node.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { buffer, _ in
    if Date().timeIntervalSince(lastLevel) >= 0.05, let samples = buffer.floatChannelData?[0] {
      var sum: Float = 0
      for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
      let rms = (sum / Float(max(buffer.frameLength, 1))).squareRoot()
      emit("level", String(format: "%.1f", 20 * log10(max(rms, 0.000_01))))
      lastLevel = Date()
    }
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / micFormat.sampleRate) + 16
    guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
    var given = false
    converter.convert(to: converted, error: nil) { _, status in
      if given { status.pointee = .noDataNow; return nil }
      given = true
      status.pointee = .haveData
      return buffer
    }
    input.yield(AnalyzerInput(buffer: converted))
  }
  let heard = Heard()
  let reader = Task {
    func show(_ text: AttributedString, _ final: Bool) { emit("partial", heard.add(String(text.characters), final: final)) }
    if let transcriber = module as? SpeechTranscriber {
      for try await result in transcriber.results { show(result.text, result.isFinal) }
    } else if let dictation = module as? DictationTranscriber {
      for try await result in dictation.results { show(result.text, result.isFinal) }
    }
  }
  engine.prepare()
  try engine.start()
  try await analyzer.start(inputSequence: stream)
  emit("ready")
  // stop types what was heard; cancel, or Hammerspoon going away, drops it.
  var command = "cancel"
  while let line = readLine() {
    let word = line.trimmingCharacters(in: .whitespaces)
    if word == "stop" || word == "cancel" { command = word; break }
  }
  engine.stop()
  node.removeTap(onBus: 0)
  input.finish()
  if command == "cancel" { exit(0) }
  try await analyzer.finalizeAndFinishThroughEndOfInput()
  _ = try? await reader.value
  emit("final", heard.finished())
}

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : ""
if mode == "locales" {
  await locales()
} else if (mode == "listen" || mode == "install") && arguments.count > 3 {
  guard let module = await makeModule(arguments[2], arguments[3]) else { emit("problem", "language"); exit(1) }
  do {
    if mode == "install" { try await install(module); emit("ready") } else { try await listen(module) }
  } catch {
    emit("problem", error.localizedDescription)
    exit(1)
  }
} else {
  FileHandle.standardError.write("usage: dictate locales | install <locale> <engine> | listen <locale> <engine>\n".data(using: .utf8)!)
  exit(2)
}
