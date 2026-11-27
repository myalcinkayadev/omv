// Dictation helper: hears speech on the Mac with macOS's own models, nothing sent anywhere.
// Usage:
//   dictate locales                       transcriber<tab>en-US …, dictation<tab>tr-TR …, installed<tab>…,
//                                         microphone<tab>granted, and name<tab>tr-TR<tab>Turkish (Türkiye) each
//   dictate install <locale> <engine>     gets the language's model: progress<tab>N, then ready
//   dictate listen <locale> <engine> [words]  records until "stop" or "cancel" on stdin; words,
//                                         |-separated, are names and terms to hear right; draws
//                                         the pill's wave where "wave" lines on stdin say (below)
//   dictate wave <x> <y> <w> <low> <mid> <high>  a still wave there until stdin closes
//   dictate selftest                      checks the wave's rules
// engine is transcriber (SpeechTranscriber) or dictation (DictationTranscriber, more languages).
// While listening it prints, one per line: progress<tab>N while a model downloads, ready once
// recording, level<tab>dB about twenty times a second, partial<tab>text as words come,
// and after "stop" final<tab>text, everything heard. problem<tab>no-microphone, no-input or
// language when it can't. "cancel", or stdin closing, ends it without a final line.
import Accelerate
import AppKit
import AVFoundation
import Foundation
import QuartzCore
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


// MARK: The wave
// The meter in the dictation pill: three sine curves layered, as Siri's is, each following one
// band of your voice: the bright one the vowels (mid), the next the hum under them (low), the
// faint one hiss like s, sh and t (high). Drawn here, in a window of the helper's own over the
// pill's strip, by Core Animation on the GPU: drawn by Hammerspoon it cost a fifth of a core.
// Hammerspoon says where the strip is and what state the pill is in, as a line on stdin:
//   wave <x> <y> <w> <listening|locked|finishing> <seconds left, or -1> <fg> <accent> <warning> <still>
// with x and y the strip's top left in Hammerspoon's coordinates; "hide" hides it.

struct WaveSpot: Equatable {
  var x = 0.0, y = 0.0, w = 0.0
  var state = "listening"
  var left: Double? = nil
  var fg = "ffffff", accent = "8d8d8d", warning = "f0a35e"
  var still = false
}

// A wave line from Hammerspoon as a WaveSpot, or nil for any other line.
func parseWave(_ line: String) -> WaveSpot? {
  let parts = line.split(separator: " ").map(String.init)
  guard parts.count == 10, parts[0] == "wave", let x = Double(parts[1]), let y = Double(parts[2]), let w = Double(parts[3]),
        ["listening", "locked", "finishing"].contains(parts[4]), let left = Double(parts[5]) else { return nil }
  return WaveSpot(x: x, y: y, w: w, state: parts[4], left: left < 0 ? nil : left, fg: parts[6], accent: parts[7],
                  warning: parts[8], still: parts[9] == "1")
}

struct WaveCurve { let band: Int; let cycles: Double; let speed: Double; let alpha: Double; let stroke: Double }

// Each curve: its band (0 low, 1 mid, 2 high), cycles across the strip, its speed, brightness, stroke.
let waveCurves = [WaveCurve(band: 1, cycles: 1.6, speed: 1, alpha: 1, stroke: 2),
                  WaveCurve(band: 0, cycles: 2.3, speed: -1.4, alpha: 0.5, stroke: 1.5),
                  WaveCurve(band: 2, cycles: 3.2, speed: 1.9, alpha: 0.25, stroke: 1.2)]
let waveCenterY = 25.0, waveRipple = 1.5, waveRise = 9.5, waveFinishingHeight = 2.5, waveStep = 4.0
let countdownSeconds = 10.0
// How far the hump moves from the middle, as a part of the strip, for pure hum or pure hiss.
let waveSway = 0.3

// A curve's height in points: low while finishing, a ripple during the countdown, else the
// ripple plus its band.
func waveAmplitude(_ bands: [Double], _ spot: WaveSpot, _ curve: WaveCurve) -> Double {
  if spot.state == "finishing" { return waveFinishingHeight }
  if spot.left != nil { return waveRipple }
  return waveRipple + waveRise * bands[curve.band]
}

// The curves' phases after seconds at bands: each faster as its band is louder; still with Reduce Motion.
func advance(_ phases: [Double], _ bands: [Double], _ seconds: Double, still: Bool) -> [Double] {
  if still { return phases }
  return waveCurves.enumerated().map { index, curve in phases[index] + seconds * (1.5 + 6 * bands[curve.band]) }
}

// Where the hump sits, as a part of the strip: right of the middle for hiss, left for hum.
func humpAt(_ bands: [Double]) -> Double {
  let total = bands.reduce(0, +)
  if total <= 0 { return 0.5 }
  return 0.5 + waveSway * (bands[2] - bands[0]) / total
}

// How much of its height a curve has at part of its width: 0 at both ends, 1 at the hump.
func taper(_ part: Double, hump: Double) -> Double {
  let shaped = part <= hump ? part / hump * 0.5 : 0.5 + (part - hump) / (1 - hump) * 0.5
  return pow(sin(Double.pi * shaped), 2)
}

// A curve's points across the strip, from x = margin: during the countdown it shrinks to the
// left, a tenth each second.
func wavePoints(_ bands: [Double], _ spot: WaveSpot, _ phases: [Double], curve index: Int, margin: Double) -> [CGPoint] {
  let curve = waveCurves[index]
  let width = spot.w * (spot.left.map { max(0, $0) / countdownSeconds } ?? 1)
  let height = waveAmplitude(bands, spot, curve), hump = humpAt(bands)
  let steps = max(1, Int(width / waveStep))
  return (0...steps).map { step in
    let x = width * Double(step) / Double(steps)
    let part = width > 0 ? x / width : 0
    let y = waveCenterY + height * taper(part, hump: hump) * sin(2 * Double.pi * curve.cycles * x / max(1, spot.w) + phases[index] * curve.speed)
    return CGPoint(x: margin + x, y: y)
  }
}

// Each band's loudness above the room, scaled by its own recent peak, so the wave shows how
// your voice changes however loud you speak and however loud your mic is. The room's level is
// learned as it goes: it falls at once to anything quieter and creeps up, doubling every 8 s,
// so a pause sets it again. Only sound twice the room's counts; the peak never goes under ten
// times the room's, so a quiet room isn't blown up. The peak halves every 1.5 s, and a steady
// voice reaches 0.8, leaving the top for a new peak.
struct Gain {
  static let quietest = pow(10, -90.0 / 20), margin = 2.0, peakOverRoom = 10.0, headroom = 1.25, halfLife = 1.5, roomDoubling = 8.0
  var peaks = [0.0, 0.0, 0.0]
  var rooms: [Double?] = [nil, nil, nil]

  // The bands in dB as 0 to 1, seconds after the last.
  mutating func values(_ decibels: [Double], _ seconds: Double) -> [Double] {
    (0..<3).map { band in
      let heard = max(Gain.quietest, pow(10, decibels[band] / 20))
      let room = min(heard, (rooms[band] ?? heard) * pow(2, seconds / Gain.roomDoubling))
      rooms[band] = room
      let amplitude = max(0, heard - Gain.margin * room)
      let peak = max(Gain.peakOverRoom * room, peaks[band] * pow(0.5, seconds / Gain.halfLife))
      peaks[band] = max(peak, amplitude)
      return min(1, (amplitude / peak).squareRoot() / Gain.headroom)
    }
  }
}

// The shown level moved towards target: at once going up, slower coming down, so it doesn't flicker.
func smooth(_ shown: Double, _ target: Double) -> Double {
  shown + (target - shown) * (target > shown ? 0.6 : 0.25)
}


// MARK: The wave's window
// The bands now, written as the mic's buffers come in and read by the wave 30 times a second.
final class Levels: @unchecked Sendable {
  private let lock = NSLock()
  private var bands = [0.0, 0.0, 0.0]
  func set(_ values: [Double]) { lock.lock(); bands = values; lock.unlock() }
  func get() -> [Double] { lock.lock(); defer { lock.unlock() }; return bands }
}

func cgColor(_ hex: String, _ alpha: Double) -> CGColor {
  let value = UInt32(hex, radix: 16) ?? 0xffffff
  return CGColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                 blue: CGFloat(value & 0xff) / 255, alpha: CGFloat(alpha))
}

// A transparent window over the pill's strip that never takes focus or the pointer, one
// level above the pill, with a CAShapeLayer per curve. Used on the main thread only.
final class WaveView: @unchecked Sendable {
  static let margin = 4.0, height = 50.0, fps = 30.0
  private let levels: Levels
  private var window: NSWindow?
  private var layers: [CAShapeLayer] = []
  private var spot: WaveSpot?
  private var phases = [0.0, 0.0, 0.0]
  private var timer: Timer?

  init(levels: Levels) { self.levels = levels }

  func show(_ next: WaveSpot) {
    let window = self.window ?? makeWindow()
    // Hammerspoon's y runs down from the top of the main screen; AppKit's runs up from its bottom.
    let top = NSScreen.screens.first?.frame.height ?? 0
    window.setFrame(NSRect(x: next.x - WaveView.margin, y: top - next.y - WaveView.height,
                           width: next.w + 2 * WaveView.margin, height: WaveView.height), display: false)
    spot = next
    draw()
    window.orderFrontRegardless()
    if timer == nil {
      timer = Timer.scheduledTimer(withTimeInterval: 1 / WaveView.fps, repeats: true) { [weak self] _ in self?.tick() }
    }
  }

  func hide() {
    timer?.invalidate()
    timer = nil
    window?.orderOut(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
    window.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
    let view = NSView()
    view.wantsLayer = true
    view.layer?.isGeometryFlipped = true
    window.contentView = view
    layers = waveCurves.map { curve in
      let layer = CAShapeLayer()
      layer.fillColor = nil
      layer.lineWidth = curve.stroke
      layer.lineCap = .round
      layer.lineJoin = .round
      view.layer?.addSublayer(layer)
      return layer
    }
    self.window = window
    return window
  }

  private func tick() {
    guard let spot else { return }
    phases = advance(phases, levels.get(), 1 / WaveView.fps, still: spot.still)
    draw()
  }

  private func draw() {
    guard let spot, let view = window?.contentView else { return }
    let bands = levels.get()
    let hex = spot.state == "finishing" ? spot.accent : (spot.left != nil ? spot.warning : spot.fg)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, layer) in layers.enumerated() {
      layer.frame = view.bounds
      layer.strokeColor = cgColor(hex, waveCurves[index].alpha)
      let path = CGMutablePath()
      path.addLines(between: wavePoints(bands, spot, phases, curve: index, margin: WaveView.margin))
      layer.path = path
    }
    CATransaction.commit()
  }
}

// How a listen ends: "stop" or "cancel" from Hammerspoon, or cancel when stdin closes.
final class Commands: @unchecked Sendable {
  private let lock = NSLock()
  private var ended: String?
  private var waiter: CheckedContinuation<String, Never>?

  func end(_ word: String) {
    lock.lock()
    guard ended == nil else { lock.unlock(); return }
    ended = word
    let waiting = waiter
    waiter = nil
    lock.unlock()
    waiting?.resume(returning: word)
  }

  func next() async -> String {
    await withCheckedContinuation { continuation in
      lock.lock()
      if let ended { lock.unlock(); continuation.resume(returning: ended); return }
      waiter = continuation
      lock.unlock()
    }
  }
}

// Signalled when Hammerspoon closes the helper's stdin.
let inputClosed = DispatchSemaphore(value: 0)
// The wave of a listen, hidden as it ends.
nonisolated(unsafe) var shownWave: WaveView?

// Reads Hammerspoon's lines on a thread of their own, so the main thread draws: stop and
// cancel end the listen, wave and hide move the wave, which keeps going while finishing.
func readCommands(_ commands: Commands, _ wave: WaveView) {
  shownWave = wave
  Thread {
    while let line = readLine() {
      let word = line.trimmingCharacters(in: .whitespaces)
      if word == "stop" || word == "cancel" { commands.end(word) }
      else if word == "hide" { DispatchQueue.main.async { wave.hide() } }
      else if let spot = parseWave(word) { DispatchQueue.main.async { wave.show(spot) } }
    }
    commands.end("cancel")
    inputClosed.signal()
  }.start()
}

// Ends a listen after its last line: the wave goes at once, but the helper reads on until
// Hammerspoon closes its stdin, 2 s at most, since Hammerspoon may still be writing, and
// writing to a pipe nobody reads kills the writer.
func leave(_ code: Int32) -> Never {
  DispatchQueue.main.async { shownWave?.hide() }
  _ = inputClosed.wait(timeout: .now() + 2)
  exit(code)
}

// MARK: Checks
// dictate selftest: the wave's rules, run by tests/dictate_wave_test.sh.
func selftest() -> Int32 {
  var failed = 0
  func check(_ name: String, _ passed: Bool) {
    print((passed ? "ok   - " : "FAIL - ") + name)
    if !passed { failed += 1 }
  }
  let spot = WaveSpot(w: 200)
  let phases = [0.3, 0.3, 0.3]
  func height(_ bands: [Double], _ spot: WaveSpot = spot, curves: [Int] = [0, 1, 2]) -> Double {
    curves.flatMap { wavePoints(bands, spot, phases, curve: $0, margin: 0) }.map { abs($0.y - waveCenterY) }.max() ?? 0
  }
  func humpX(_ bands: [Double]) -> Double {
    let points = wavePoints(bands, spot, phases, curve: 0, margin: 0)
    return points.max { taper($0.x / 200, hump: humpAt(bands)) < taper($1.x / 200, hump: humpAt(bands)) }!.x
  }
  let loud = wavePoints([1, 1, 1], spot, phases, curve: 0, margin: 0)
  check("should taper the wave to the centre line at both ends", abs(loud.first!.y - 25) < 1e-6 && abs(loud.last!.y - 25) < 1e-6)
  check("should raise the wave when the voice is louder", height([1, 1, 1]) > height([0.2, 0.2, 0.2]))
  check("should leave a small ripple when silent", waveAmplitude([0, 0, 0], spot, waveCurves[0]) == 1.5 && height([0, 0, 0]) > 0)
  check("should move each curve faster when its band is louder",
        advance([0, 0, 0], [1, 1, 1], 0.05, still: false)[0] > advance([0, 0, 0], [0.2, 0.2, 0.2], 0.05, still: false)[0])
  check("should drive each curve by its own band", height([0, 0, 1], curves: [2]) > 5 && height([0, 0, 1], curves: [0]) <= 1.5
        && height([0, 0, 1], curves: [1]) <= 1.5)
  check("should move the hump right for hiss", humpX([0, 0, 1]) > 102)
  check("should move the hump left for hum", humpX([1, 0, 0]) < 98)
  check("should keep the hump in the middle when silent", abs(humpX([0, 0, 0]) - 100) <= 2)
  var counting = spot
  counting.state = "locked"
  counting.left = 7
  check("should shrink the wave to the left during the countdown", abs(wavePoints([1, 1, 1], counting, phases, curve: 0, margin: 0).last!.x - 140) < 0.01)
  check("should lower the wave to a ripple during the countdown", waveAmplitude([1, 1, 1], counting, waveCurves[0]) == 1.5)
  var finishing = spot
  finishing.state = "finishing"
  check("should draw a low wave while finishing", waveAmplitude([1, 1, 1], finishing, waveCurves[0]) == 2.5)
  check("should hold the wave still when Reduce Motion is on", advance([1, 2, 3], [1, 1, 1], 0.05, still: true) == [1, 2, 3])
  check("should draw three curves at 1, 0.5 and 0.25 brightness", waveCurves.map(\.alpha) == [1, 0.5, 0.25])
  check("should draw a curve point every 4 pt", loud.count == 200 / 4 + 1)

  func decibels(_ amplitude: Double) -> Double { 20 * log10(amplitude) }
  func room(_ gain: inout Gain) { for _ in 0..<10 { _ = gain.values([-70, -70, -70], 0.05) } }
  var gain = Gain()
  room(&gain)
  for _ in 0..<20 { _ = gain.values([decibels(0.1), decibels(0.1), decibels(0.1)], 0.05) }
  check("should keep headroom above the recent peak", abs(gain.values([decibels(0.1), decibels(0.1), decibels(0.1)], 0.05)[1] - 0.8) < 0.01)
  check("should rise to the top only on a new peak", gain.values([decibels(0.1), decibels(0.2), decibels(0.1)], 0.05)[1] == 1)
  var fading = Gain()
  room(&fading)
  _ = fading.values([decibels(0.1), decibels(0.1), decibels(0.1)], 0.05)
  for _ in 0..<60 { _ = fading.values([-90, -90, -90], 0.05) }
  check("should let the peak fall slowly so a quieter voice fills the wave again",
        fading.values([decibels(0.05), decibels(0.05), decibels(0.05)], 0.05)[1] > 0.6)
  var quiet = Gain()
  room(&quiet)
  check("should keep room noise as a ripple", quiet.values([-70, -70, -70], 0.05)[1] == 0)
  check("should hear a quiet voice well above a quiet room", quiet.values([-50, -50, -50], 0.05)[1] > 0.5)
  var noisy = Gain()
  for _ in 0..<10 { _ = noisy.values([-45, -45, -45], 0.05) }
  check("should learn a noisy room's level as its floor", noisy.values([-45, -45, -45], 0.05)[1] == 0)
  check("should rise at once", abs(smooth(0, 1) - 0.6) < 1e-9)
  check("should fall slower than it rises", abs(smooth(1, 0) - 0.75) < 1e-9)

  let parsed = parseWave("wave 1190 1240 262 locked 7 ffffff 8d8d8d f0a35e 0")
  check("should read a wave line", parsed == WaveSpot(x: 1190, y: 1240, w: 262, state: "locked", left: 7, fg: "ffffff",
                                                       accent: "8d8d8d", warning: "f0a35e", still: false))
  check("should read no time left as -1", parseWave("wave 0 0 100 listening -1 ffffff 8d8d8d f0a35e 1")?.left == nil)
  check("should read Reduce Motion", parseWave("wave 0 0 100 listening -1 ffffff 8d8d8d f0a35e 1")?.still == true)
  check("should ignore a line it doesn't know", parseWave("stop") == nil && parseWave("wave 1 2") == nil
        && parseWave("wave 0 0 100 dancing -1 ffffff 8d8d8d f0a35e 0") == nil)
  print("\(failed == 0 ? "all" : "\(failed) failed of") checks")
  return failed == 0 ? 0 : 1
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

func listen(_ module: any SpeechModule, words: [String], levels: Levels, commands: Commands) async throws {
  guard await AVCaptureDevice.requestAccess(for: .audio) else { emit("problem", "no-microphone"); leave(1) }
  try await install(module)
  let analyzer = SpeechAnalyzer(modules: [module])
  // Only the dictation model takes them; the transcriber ignores contextual strings.
  if !words.isEmpty && module is DictationTranscriber {
    let context = AnalysisContext()
    context.contextualStrings = [.general: words]
    try await analyzer.setContext(context)
  }
  guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
    emit("problem", "no-input"); leave(1)
  }
  let engine = AVAudioEngine()
  let node = engine.inputNode
  let micFormat = node.outputFormat(forBus: 0)
  guard micFormat.channelCount > 0, let converter = AVAudioConverter(from: micFormat, to: format) else {
    emit("problem", "no-input"); leave(1)
  }
  let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
  var lastLevel = Date.distantPast
  let bands = Bands(sampleRate: Float(micFormat.sampleRate))
  var gain = Gain()
  var shown = [0.0, 0.0, 0.0]
  node.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { buffer, _ in
    if Date().timeIntervalSince(lastLevel) >= 0.05, let samples = buffer.floatChannelData?[0] {
      let count = Int(buffer.frameLength)
      var sum: Float = 0
      for index in 0..<count { sum += samples[index] * samples[index] }
      let rms = (sum / Float(max(count, 1))).squareRoot()
      emit("level", String(format: "%.1f", decibels(rms)))
      let shares = bands.shares(samples, count)
      let values = gain.values(shares.map { Double(decibels(rms * $0.squareRoot())) }, Date().timeIntervalSince(lastLevel) > 1 ? 0.05 : Date().timeIntervalSince(lastLevel))
      shown = zip(shown, values).map { smooth($0, $1) }
      levels.set(shown)
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
  let command = await commands.next()
  engine.stop()
  node.removeTap(onBus: 0)
  input.finish()
  if command == "cancel" { leave(0) }
  try await analyzer.finalizeAndFinishThroughEndOfInput()
  _ = try? await reader.value
  emit("final", heard.finished())
}

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : ""
// listen and wave draw, so they run AppKit on the main thread and do the rest in a task.
func runWithWindow(_ work: @escaping @Sendable (Levels, WaveView, Commands) async -> Void) -> Never {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let levels = Levels()
  let wave = WaveView(levels: levels)
  let commands = Commands()
  readCommands(commands, wave)
  Task { await work(levels, wave, commands) }
  app.run()
  exit(0)
}

if mode == "locales" {
  await locales()
} else if mode == "selftest" {
  exit(selftest())
} else if mode == "wave" && arguments.count > 6 {
  // A still wave with bands low, mid and high at x, y and w until stdin closes, for the README's picture.
  let values = arguments[5...7].map { Double($0) ?? 0 }
  runWithWindow { levels, wave, commands in
    levels.set(values)
    let x = Double(arguments[2]) ?? 0, y = Double(arguments[3]) ?? 0, w = Double(arguments[4]) ?? 0
    await MainActor.run { wave.show(WaveSpot(x: x, y: y, w: w, still: true)) }
    _ = await commands.next()
    exit(0)
  }
} else if mode == "listen" && arguments.count > 3 {
  runWithWindow { levels, _, commands in
    guard let module = await makeModule(arguments[2], arguments[3]) else { emit("problem", "language"); leave(1) }
    do {
      try await listen(module, words: arguments.count > 4 ? arguments[4].split(separator: "|").map(String.init) : [],
                       levels: levels, commands: commands)
    } catch {
      emit("problem", error.localizedDescription)
      leave(1)
    }
    leave(0)
  }
} else if mode == "install" && arguments.count > 3 {
  guard let module = await makeModule(arguments[2], arguments[3]) else { emit("problem", "language"); exit(1) }
  do {
    try await install(module)
    emit("ready")
  } catch {
    emit("problem", error.localizedDescription)
    exit(1)
  }
} else {
  FileHandle.standardError.write("usage: dictate locales | install <locale> <engine> | listen <locale> <engine> [words] | wave <x> <y> <w> <low> <mid> <high> | selftest\n".data(using: .utf8)!)
  exit(2)
}
