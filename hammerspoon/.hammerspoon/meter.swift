// Mic level helper for the Sound card's meter. Usage: meter <file>
// Writes the default input's level to <file> about ten times a second, as one line from
// 0.000 to 1.000, or "denied" when microphone access was refused.
// It stops by itself once <file>.alive is more than 3 seconds old, so it never outlives
// the card, even if Hammerspoon stops touching that file without stopping it.
import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else { exit(2) }
let output = URL(fileURLWithPath: arguments[1])
let alive = URL(fileURLWithPath: arguments[1] + ".alive")
let staleAfter: TimeInterval = 3

func write(_ line: String) {
  try? (line + "\n").write(to: output, atomically: true, encoding: .utf8)
}

// Speech sits around -30 dB, silence below -60 dB, so -60...0 dB fills the meter.
func level(_ buffer: AVAudioPCMBuffer) -> Float {
  guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
  var sum: Float = 0
  for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
  let rms = (sum / Float(buffer.frameLength)).squareRoot()
  let decibels = 20 * log10(max(rms, 0.000_001))
  return min(1, max(0, (decibels + 60) / 60))
}

let engine = AVAudioEngine()
var latest: Float = 0
var shown: Float = 0

func start() {
  let input = engine.inputNode
  input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
    latest = level(buffer)
  }
  do { try engine.start() } catch { write("0.000"); exit(1) }
  Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    // Rises at once, falls gently, like a VU meter.
    shown = latest > shown ? latest : shown * 0.7 + latest * 0.3
    write(String(format: "%.3f", shown))
  }
}

Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
  let touched = (try? alive.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
  if touched == nil || Date().timeIntervalSince(touched!) > staleAfter { exit(0) }
}

AVCaptureDevice.requestAccess(for: .audio) { granted in
  DispatchQueue.main.async {
    if granted { start() } else { write("denied"); exit(0) }
  }
}

RunLoop.main.run()
