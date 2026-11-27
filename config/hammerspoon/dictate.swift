// Dictation helper: hears speech on the Mac with macOS's own models, nothing sent anywhere.
// Usage:
//   dictate locales                       transcriber<tab>en-US …, dictation<tab>tr-TR …, installed<tab>…,
//                                         microphone<tab>granted, and name<tab>tr-TR<tab>Turkish (Türkiye) each
//   dictate install <locale> <engine>     gets the language's model: progress<tab>N, then ready
//   dictate listen <locale> <engine> [words]  records until "stop" or "cancel" on stdin; words,
//                                         |-separated, are names and terms to hear right
// engine is transcriber (SpeechTranscriber) or dictation (DictationTranscriber, more languages).
// While listening it prints, one per line: progress<tab>N while a model downloads, ready once
// recording, level<tab>dB and bands<tab>low mid high, each band's dB (80-300 Hz, 300-2000 Hz,
// 2-8 kHz), about thirty times a second, partial<tab>text as words come,
// and after "stop" final<tab>text, everything heard. problem<tab>no-microphone, no-input or
// language when it can't. "cancel", or stdin closing, ends it without a final line.
import Accelerate
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

func decibels(_ amplitude: Float) -> Float {
  20 * log10(max(amplitude, 0.000_01))
}

// How a buffer's energy splits between the voice's hum, its vowels and its hiss, each a part of
// 0 to 1 of the energy from 80 Hz to 8 kHz; with the level, that gives each band's loudness.
final class Bands {
  static let size = 1024
  static let edges: [Float] = [80, 300, 2000, 8000]
  let setup: FFTSetup
  let window: [Float]
  let hertzPerBin: Float

  init(sampleRate: Float) {
    setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
    var window = [Float](repeating: 0, count: Bands.size)
    vDSP_hann_window(&window, vDSP_Length(Bands.size), Int32(vDSP_HANN_NORM))
    self.window = window
    hertzPerBin = sampleRate / Float(Bands.size)
  }

  func shares(_ samples: UnsafePointer<Float>, _ count: Int) -> [Float] {
    var windowed = [Float](repeating: 0, count: Bands.size)
    vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(min(count, Bands.size)))
    var real = [Float](repeating: 0, count: Bands.size / 2)
    var imaginary = [Float](repeating: 0, count: Bands.size / 2)
    var power = [Float](repeating: 0, count: Bands.size / 2)
    real.withUnsafeMutableBufferPointer { realPart in
      imaginary.withUnsafeMutableBufferPointer { imaginaryPart in
        var split = DSPSplitComplex(realp: realPart.baseAddress!, imagp: imaginaryPart.baseAddress!)
        windowed.withUnsafeBufferPointer { input in
          input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Bands.size / 2) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Bands.size / 2))
          }
        }
        vDSP_fft_zrip(setup, &split, 1, 10, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(Bands.size / 2))
      }
    }
    var energies = [Float](repeating: 0, count: 3)
    for bin in 1..<(Bands.size / 2) {
      let hertz = Float(bin) * hertzPerBin
      for band in 0..<3 where hertz >= Bands.edges[band] && hertz < Bands.edges[band + 1] { energies[band] += power[bin] }
    }
    let total = energies.reduce(0, +)
    return total > 0 ? energies.map { $0 / total } : [0, 0, 0]
  }
}

func listen(_ module: any SpeechModule, words: [String]) async throws {
  guard await AVCaptureDevice.requestAccess(for: .audio) else { emit("problem", "no-microphone"); exit(1) }
  try await install(module)
  let analyzer = SpeechAnalyzer(modules: [module])
  // Only the dictation model takes them; the transcriber ignores contextual strings.
  if !words.isEmpty && module is DictationTranscriber {
    let context = AnalysisContext()
    context.contextualStrings = [.general: words]
    try await analyzer.setContext(context)
  }
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
  let bands = Bands(sampleRate: Float(micFormat.sampleRate))
  node.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { buffer, _ in
    if Date().timeIntervalSince(lastLevel) >= 0.033, let samples = buffer.floatChannelData?[0] {
      let count = Int(buffer.frameLength)
      var sum: Float = 0
      for index in 0..<count { sum += samples[index] * samples[index] }
      let rms = (sum / Float(max(count, 1))).squareRoot()
      emit("level", String(format: "%.1f", decibels(rms)))
      let shares = bands.shares(samples, count)
      emit("bands", shares.map { String(format: "%.1f", decibels(rms * $0.squareRoot())) }.joined(separator: " "))
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
    if mode == "install" { try await install(module); emit("ready") } else { try await listen(module, words: arguments.count > 4 ? arguments[4].split(separator: "|").map(String.init) : []) }
  } catch {
    emit("problem", error.localizedDescription)
    exit(1)
  }
} else {
  FileHandle.standardError.write("usage: dictate locales | install <locale> <engine> | listen <locale> <engine>\n".data(using: .utf8)!)
  exit(2)
}
