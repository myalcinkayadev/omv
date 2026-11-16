// Runs omv's install for the Install screen: bin/omv install --no-setup with OMV_STEPS=1, read
// line by line into an InstallRun, and written whole to ~/.local/state/omv/install.log.

import Foundation

final class Installer: ObservableObject {
  @Published private(set) var run = InstallRun()
  @Published private(set) var started: Date?
  let repo: String
  let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/omv/install.log")
  private var process: Process?
  private var pending = ""

  init(repo: String) { self.repo = repo }

  var isRunning: Bool { process?.isRunning ?? false }
  var succeeded: Bool { run.isFinished && run.failed == nil }

  func start() {
    guard !isRunning else { return }
    run = InstallRun()
    started = Date()
    pending = ""
    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let logHandle = try? FileHandle(forWritingTo: log)

    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: repo + "/bin/omv")
    process.arguments = ["install", "--no-setup"]
    var environment = ProcessInfo.processInfo.environment
    environment["OMV_STEPS"] = "1"
    // An app opened from Finder gets a bare PATH; omv and brew need Homebrew's.
    environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      logHandle?.write(data)
      let text = String(decoding: data, as: UTF8.self)
      DispatchQueue.main.async { self?.take(text) }
    }
    process.terminationHandler = { [weak self] finished in
      pipe.fileHandleForReading.readabilityHandler = nil
      try? logHandle?.close()
      DispatchQueue.main.async {
        guard let self else { return }
        if !self.pending.isEmpty { self.run.consume(self.pending); self.pending = "" }
        self.run.finish(status: finished.terminationStatus)
        self.process = nil
        self.objectWillChange.send()
      }
    }
    self.process = process
    do {
      try process.run()
    } catch {
      run.consume("couldn't start \(repo)/bin/omv: \(error.localizedDescription)")
      run.finish(status: 1)
      self.process = nil
    }
  }

  // Output comes in chunks; only whole lines go to the run.
  private func take(_ text: String) {
    pending += text
    while let newline = pending.firstIndex(of: "\n") {
      run.consume(String(pending[..<newline]))
      pending = String(pending[pending.index(after: newline)...])
    }
  }

  var failureReason: String { InstallRun.failureReason(Array(run.output.suffix(40))) }

  // The file a Stow conflict names, to show in Finder.
  var conflictPath: String? {
    let reason = failureReason
    guard reason.hasPrefix("~/"), let end = reason.range(of: " already exists") else { return nil }
    return NSString(string: String(reason[..<end.lowerBound])).expandingTildeInPath
  }
}
