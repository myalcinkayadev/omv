// Runs omv's install for the Install screen: bin/omv install --no-setup with OMV_STEPS=1, read
// line by line into an InstallRun, and written whole to ~/.local/state/omv/install.log.
// The run ends when its output has ended and the process has exited, so no last line, often
// the error, is lost. Output and the log are handled on one queue, in order.

import Foundation

final class Installer: ObservableObject {
  @Published private(set) var run = InstallRun()
  @Published private(set) var started: Date?
  let repo: String
  let withoutApps: Bool
  let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/omv/install.log")
  private var process: Process?
  private let queue = DispatchQueue(label: "omv.setup.install")

  init(repo: String, withoutApps: Bool) {
    self.repo = repo
    self.withoutApps = withoutApps
  }

  var isRunning: Bool { process != nil }
  var succeeded: Bool { run.isFinished && run.failed == nil }

  func start() {
    guard !isRunning else { return }
    run = InstallRun()
    started = Date()
    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let logHandle = try? FileHandle(forWritingTo: log)

    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: repo + "/bin/omv")
    process.arguments = ["install", "--no-setup"] + (withoutApps ? ["--no-apps"] : [])
    var environment = ProcessInfo.processInfo.environment
    environment["OMV_STEPS"] = "1"
    // An app opened from Finder gets a bare PATH; omv and brew need Homebrew's.
    environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    // No terminal for sudo to ask in: Homebrew runs sudo -A, which asks with a dialog.
    environment["SUDO_ASKPASS"] = repo + "/install/askpass.sh"
    process.environment = environment
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice

    let ended = DispatchGroup()
    ended.enter()  // the output's end
    ended.enter()  // the process's exit
    var lines = LineSplitter()
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty { handle.readabilityHandler = nil }
      self?.queue.async {
        guard !data.isEmpty else {
          let rest = lines.finish()
          DispatchQueue.main.async { rest.forEach { self?.run.consume($0) } }
          ended.leave()
          return
        }
        logHandle?.write(data)
        let complete = lines.feed(data)
        DispatchQueue.main.async { complete.forEach { self?.run.consume($0) } }
      }
    }
    process.terminationHandler = { _ in ended.leave() }
    ended.notify(queue: queue) { [weak self] in
      try? logHandle?.close()
      DispatchQueue.main.async {
        guard let self else { return }
        self.run.finish(status: process.terminationStatus)
        self.process = nil
      }
    }
    self.process = process
    do {
      try process.run()
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      try? logHandle?.close()
      run.consume("couldn't start \(repo)/bin/omv: \(error.localizedDescription)")
      run.finish(status: 1)
      self.process = nil
    }
  }

  // Stops a running install, as when the window is closed mid-way.
  func stop() {
    guard let process, process.isRunning else { return }
    process.terminate()
  }

  // All of it: Homebrew names the app it's adopting long before the hundreds of lines its
  // refusal prints.
  var failureReason: String { InstallRun.failureReason(run.output) }

  // The file a Stow conflict names, to show in Finder.
  var conflictPath: String? {
    let reason = failureReason
    guard reason.hasPrefix("~/"), let end = reason.range(of: " already exists") else { return nil }
    return NSString(string: String(reason[..<end.lowerBound])).expandingTildeInPath
  }
}
