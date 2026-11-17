// The install as omv Setup shows it: six steps, read from the "omv-step:" lines install.sh
// prints with OMV_STEPS=1, each with its state, its live detail and, once done, a summary.

import Foundation

enum StepState {
  case pending, running, done, failed
}

struct InstallStep {
  let id: String
  let title: String
  let about: String
}

struct InstallRun {
  static let steps: [InstallStep] = [
    InstallStep(id: "taps", title: "Homebrew taps", about: "the third-party taps omv installs from"),
    InstallStep(id: "tools", title: "Tools and apps", about: "brew bundle"),
    InstallStep(id: "configs", title: "Configs", about: "Stow links, Hammerspoon, aerospace.toml"),
    InstallStep(id: "command", title: "omv command", about: "on your PATH"),
    InstallStep(id: "agents", title: "Agents", about: "hooks for the agents found"),
    InstallStep(id: "settings", title: "macOS settings", about: "menu bar, Spaces, swipe"),
  ]

  private var states: [String: StepState] = [:]
  private var summaries: [String: String] = [:]
  private var details: [String: String] = [:]
  private(set) var running: String?
  private(set) var output: [String] = []
  private(set) var isFinished = false

  func state(_ id: String) -> StepState { states[id] ?? .pending }
  func summary(_ id: String) -> String? { summaries[id] }
  func detail(_ id: String) -> String? { details[id] }

  mutating func consume(_ line: String) {
    output.append(line)
    let marker = "omv-step: "
    guard line.hasPrefix(marker) else {
      let text = line.trimmingCharacters(in: .whitespaces)
      if let running, !text.isEmpty { details[running] = text }
      return
    }
    let parts = line.dropFirst(marker.count).split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return }
    if parts[1] == "start" {
      states[parts[0]] = .running
      running = parts[0]
    } else if parts[1] == "done" {
      states[parts[0]] = .done
      summaries[parts[0]] = parts.count > 2 ? parts[2] : nil
      if running == parts[0] { running = nil }
    }
  }

  // A failure lands on the step that was running, else on the first one not done.
  mutating func finish(status: Int32) {
    isFinished = true
    guard status != 0 else { return }
    let failed = running ?? InstallRun.steps.first { state($0.id) != .done }?.id
    if let failed { states[failed] = .failed }
    running = nil
  }

  var failed: String? { InstallRun.steps.first { state($0.id) == .failed }?.id }

  // One plain sentence for what went wrong, from the install's output.
  static func failureReason(_ lines: [String]) -> String {
    for line in lines {
      if let range = line.range(of: "over existing target "),
         let end = line.range(of: " since", range: range.upperBound..<line.endIndex) {
        return "~/" + line[range.upperBound..<end.lowerBound] + " already exists, where omv links its own."
      }
      if line.contains("existing target is neither a link nor a directory: ") {
        let path = line.components(separatedBy: "existing target is neither a link nor a directory: ").last ?? ""
        return "~/" + path + " already exists, where omv links its own."
      }
    }
    // An app installed another way, which macOS won't let Homebrew take over.
    if lines.contains(where: { $0.contains("Operation not permitted") }),
       let adopting = lines.first(where: { $0.contains("Adopting existing App at '") }),
       let app = adopting.components(separatedBy: "'").dropFirst().first {
      return "Homebrew couldn't take over \(app), which macOS protects. It's installed already: run omv install --no-apps."
    }
    if lines.contains(where: { $0.contains("`brew bundle` failed") }) {
      return "Homebrew couldn't install everything in the Brewfile."
    }
    return lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "The install stopped."
  }
}

// Output arrives in chunks that can end mid-line, or mid-character: brew prints 🍺. Lines are
// cut as bytes and decoded whole.
struct LineSplitter {
  private var pending = Data()

  mutating func feed(_ data: Data) -> [String] {
    pending.append(data)
    var lines: [String] = []
    while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
      lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
      pending = Data(pending[pending.index(after: newline)...])
    }
    return lines
  }

  // What's left once the output has ended: a last line with no newline.
  mutating func finish() -> [String] {
    defer { pending = Data() }
    return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
  }
}
