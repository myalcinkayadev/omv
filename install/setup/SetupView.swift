// The setup assistant's window: steps on the left, the current one on the right, in omv's
// look (black, gray borders, white, JetBrainsMono). In install mode it runs the install first,
// showing each step; then the permissions, which it checks every second, so a step ticks
// itself as the user turns a switch on in System Settings.

import AppKit
import SwiftUI

enum Look {
  static let ground = Color.black
  static let line = Color(white: 0.23)
  static let soft = Color(white: 0.74)
  static let faint = Color(white: 0.6)
  static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("JetBrainsMono Nerd Font Mono", size: size).weight(weight)
  }
}

// Reads what macOS lets omv read: Hammerspoon's own permissions through its hs command, and
// AeroSpace's Accessibility by whether it can list windows.
enum SetupChecks {
  static let hammerspoonQuestion = """
    return table.concat({tostring(hs.accessibilityState(false)), tostring(hs.screenRecordingState(false)), \
    hs.location.authorizationStatus(), tostring((pcall(hs.fs.dir, os.getenv("HOME") .. "/Library/DoNotDisturb/DB")))}, ",")
    """

  static func tool(_ name: String) -> String? {
    ["/opt/homebrew/bin/", "/usr/local/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  @discardableResult
  static func run(_ path: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return (-1, "") }
    process.waitUntilExit()
    let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, text)
  }

  static func read() -> [String: Grant] {
    var grants: [String: Grant] = [:]
    if let hs = tool("hs") {
      let answer = run(hs, ["-t", "2", "-c", hammerspoonQuestion]).1
      grants = SetupModel.hammerspoonGrants(answer.split(separator: "\n").last.map(String.init) ?? "")
    }
    if let aerospace = tool("aerospace") {
      grants["aerospace.accessibility"] = run(aerospace, ["list-windows", "--all"]).0 == 0 ? .granted : .denied
    }
    return grants
  }

  // Screen Recording applies when Hammerspoon starts again.
  static func restartHammerspoon() {
    DispatchQueue.global().async {
      run("/usr/bin/pkill", ["-x", "Hammerspoon"])
      Thread.sleep(forTimeInterval: 1)
      run("/usr/bin/open", ["-a", "Hammerspoon"])
    }
  }
}

final class SetupState: ObservableObject {
  @Published var progress = SetupProgress()
  @Published var screen = "welcome"
  @Published var opened: Set<String> = []
  @Published var showDetails = false
  let installer: Installer?
  let helper = HelperController()
  private var timer: Timer?

  init(installer: Installer?) {
    self.installer = installer
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refresh()
      self?.objectWillChange.send()
    }
  }

  var screens: [String] { ["welcome", "install"] + SetupModel.steps.map(\.id) + ["done"] }

  func refresh() {
    DispatchQueue.global().async {
      let grants = SetupChecks.read()
      DispatchQueue.main.async { self.progress.grants = grants }
    }
  }

  var step: SetupStep? { SetupModel.steps.first { $0.id == screen } }

  func go(_ id: String) {
    helper.hide()
    screen = id
  }

  func next() {
    let index = screens.firstIndex(of: screen) ?? 0
    go(screens[min(index + 1, screens.count - 1)])
  }

  // Install mode runs the install first; otherwise straight to the first step not yet done.
  func start() {
    if let installer {
      go("install")
      installer.start()
    } else {
      go(progress.firstOpenStep(SetupModel.steps))
    }
  }

  func afterInstall() { go(progress.firstOpenStep(SetupModel.steps)) }

  func skip() {
    if let step { progress.skipped.insert(step.id) }
    next()
  }

  func openSettings(_ step: SetupStep) {
    NSWorkspace.shared.open(URL(string: step.paneURL)!)
    opened.insert(step.id)
    helper.show(step, state: self)
  }

  func mark(_ id: String) -> String {
    if id == screen { return "●" }
    if id == "install" {
      guard let installer else { return "✓" }
      if installer.run.failed != nil { return "✗" }
      return installer.succeeded ? "✓" : "○"
    }
    if let step = SetupModel.steps.first(where: { $0.id == id }) {
      if progress.isComplete(step) { return "✓" }
      if progress.skipped.contains(id) { return "–" }
      return "○"
    }
    return (screens.firstIndex(of: id) ?? 0) < (screens.firstIndex(of: screen) ?? 0) ? "✓" : "○"
  }
}

struct SetupView: View {
  @StateObject var state: SetupState

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(Look.line).frame(width: 1)
      VStack(alignment: .leading, spacing: 16) { content }
        .padding(EdgeInsets(top: 32, leading: 40, bottom: 24, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: 860, height: 560)
    .background(Look.ground)
    .foregroundColor(.white)
    .environmentObject(state)
  }

  var sidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(state.screens, id: \.self) { id in
        Button { state.go(id) } label: {
          HStack(spacing: 10) {
            Text(state.mark(id)).frame(width: 16)
            Text(title(id))
            Spacer()
          }
          .padding(.horizontal, 10).padding(.vertical, 7)
          .background(id == state.screen ? Color(white: 0.12) : .clear)
          .cornerRadius(6)
          .foregroundColor(id == state.screen ? .white : Look.faint)
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .font(Look.font(13))
    .padding(16)
    .frame(width: 220)
  }

  func title(_ id: String) -> String {
    switch id {
    case "welcome": return "Welcome"
    case "install": return "Install"
    case "done": return "Done"
    default: return SetupModel.steps.first { $0.id == id }?.title ?? id
    }
  }

  @ViewBuilder var content: some View {
    switch state.screen {
    case "welcome": welcome
    case "install": install
    case "done": done
    default: if let step = state.step { stepView(step) }
    }
  }

  var welcome: some View {
    let installing = state.installer != nil
    return Group {
      Text(installing ? "Set up omv" : "omv is installed.").font(Look.font(26, .bold))
      if installing {
        Text("First omv installs its tools and apps with Homebrew, links its configs and sets a few macOS settings. You'll see each step as it runs.")
          .font(Look.font(14)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      }
      Text("Then a few permissions only you can grant. This window opens the right place and ticks each one off as you go.")
        .font(Look.font(14)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      Text("Skip any permission and come back with omv setup.").font(Look.font(13)).foregroundColor(Look.faint)
      Spacer()
      HStack { Spacer(); primary(installing ? "Install  →" : "Start  →") { state.start() } }
    }
  }

  // The install's six steps, the running one with its live detail and time, a failed one with
  // its reason, Retry and the details.
  @ViewBuilder var install: some View {
    if let installer = state.installer {
      let run = installer.run
      Text(run.failed != nil ? "One step needs you" : installer.succeeded ? "Installed" : "Installing").font(Look.font(24, .bold))
      ForEach(InstallRun.steps, id: \.id) { step in installRow(step, installer) }
      Spacer()
      HStack {
        link("Show install log") { NSWorkspace.shared.open(installer.log) }
        Spacer()
        primary("Continue  →", enabled: installer.succeeded) { state.afterInstall() }
      }
    } else {
      Text("Installed").font(Look.font(24, .bold))
      Text("omv was installed in the terminal. Run omv install again to repeat it here.").font(Look.font(13)).foregroundColor(Look.soft)
      Spacer()
      HStack { Spacer(); primary("Continue  →") { state.afterInstall() } }
    }
  }

  @ViewBuilder func installRow(_ step: InstallStep, _ installer: Installer) -> some View {
    let run = installer.run
    let stepState = run.state(step.id)
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(icon(stepState)).frame(width: 18)
        Text(step.title).frame(width: 160, alignment: .leading).font(Look.font(13, stepState == .running ? .bold : .regular))
        Text(rowDetail(step, stepState, installer)).foregroundColor(stepState == .pending ? Look.faint : Look.soft).lineLimit(1)
      }
      .font(Look.font(13))
      .foregroundColor(stepState == .pending ? Look.faint : .white)
      if stepState == .failed {
        VStack(alignment: .leading, spacing: 10) {
          Text(installer.failureReason).font(Look.font(12)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 10) {
            primary("Retry") { installer.start() }
            if let path = installer.conflictPath {
              secondary("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            link(state.showDetails ? "▾ Hide details" : "▸ Show details") { state.showDetails.toggle() }
          }
        }
        .padding(.leading, 30)
      }
      if state.showDetails && (stepState == .running || stepState == .failed) {
        Text(run.output.suffix(8).joined(separator: "\n"))
          .font(Look.font(11)).foregroundColor(Look.faint)
          .frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Look.line))
          .padding(.leading, 30)
      } else if stepState == .running {
        link("▸ Show details") { state.showDetails = true }.padding(.leading, 30)
      }
    }
  }

  func icon(_ stepState: StepState) -> String {
    switch stepState {
    case .pending: return "○"
    case .running: return "◐"
    case .done: return "✓"
    case .failed: return "✗"
    }
  }

  func rowDetail(_ step: InstallStep, _ stepState: StepState, _ installer: Installer) -> String {
    switch stepState {
    case .done: return installer.run.summary(step.id) ?? "done"
    case .running:
      let seconds = Int(Date().timeIntervalSince(installer.started ?? Date()))
      return (installer.run.detail(step.id) ?? step.about) + String(format: " · %d:%02d", seconds / 60, seconds % 60)
    case .failed: return "stopped"
    case .pending: return installer.run.failed != nil ? "waits for the step above" : step.about
    }
  }

  func stepView(_ step: SetupStep) -> some View {
    let complete = state.progress.isComplete(step)
    return Group {
      Text(step.title).font(Look.font(24, .bold))
      Text(step.purpose).font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 14) {
        number("1", done: state.opened.contains(step.id))
        secondary("Open System Settings") { state.openSettings(step) }
      }
      HStack(alignment: .top, spacing: 14) {
        number("2", done: complete)
        VStack(alignment: .leading, spacing: 12) {
          Text("Drag each app into the list, then turn it on. A helper sits beside System Settings too.")
            .font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
          ForEach(step.permissions, id: \.key) { AppRow(permission: $0).frame(width: 320) }
        }
      }
      if step.needsRestart && state.opened.contains(step.id) && !complete {
        HStack(alignment: .top, spacing: 14) {
          number("3", done: false)
          VStack(alignment: .leading, spacing: 10) {
            Text("macOS applies Screen Recording only when Hammerspoon starts again.").font(Look.font(13))
            primary("Restart Hammerspoon") { SetupChecks.restartHammerspoon() }
          }
        }
      }
      Spacer()
      HStack {
        secondary("Skip") { state.skip() }
        Spacer()
        primary("Next  →", enabled: complete) { state.next() }
      }
    }
  }

  var done: some View {
    let summary = state.progress.summary(SetupModel.steps)
    return Group {
      Text(summary.missing.isEmpty ? "You're set." : "Almost there.").font(Look.font(26, .bold))
      VStack(alignment: .leading, spacing: 10) {
        Text("✓  \(summary.granted) granted")
        if summary.skipped > 0 { Text("–  \(summary.skipped) skipped").foregroundColor(Look.soft) }
        if !summary.byHand.isEmpty { Text("?  to check by hand: " + summary.byHand.map(title).joined(separator: ", ")).foregroundColor(Look.soft) }
        if !summary.missing.isEmpty { Text("✗  not yet: " + summary.missing.map(title).joined(separator: ", ")).foregroundColor(Look.soft) }
      }.font(Look.font(14))
      Rectangle().fill(Look.line).frame(height: 1)
      Text("Try it: Option+/ shows every key.").font(Look.font(13)).foregroundColor(Look.soft)
      Text("The rest later: Option+Escape, then Permissions, or omv setup.").font(Look.font(13)).foregroundColor(Look.soft)
      if let installer = state.installer { link("Show install log") { NSWorkspace.shared.open(installer.log) } }
      Spacer()
      HStack { Spacer(); primary("Finish") { NSApp.terminate(nil) } }
    }
  }

  func number(_ text: String, done: Bool) -> some View {
    Text(done ? "✓" : text).font(Look.font(12, done ? .bold : .regular))
      .foregroundColor(done ? .black : Look.soft)
      .frame(width: 26, height: 26)
      .background(Circle().fill(done ? Color.white : Color.clear))
      .overlay(Circle().stroke(done ? Color.white : Color(white: 0.35)))
  }

  func primary(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(Look.font(14, .bold)).padding(.horizontal, 22).frame(height: 44)
        .background(enabled ? Color.white : Color(white: 0.12))
        .foregroundColor(enabled ? .black : Look.faint).cornerRadius(8)
    }
    .buttonStyle(.plain).disabled(!enabled)
  }

  func secondary(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(Look.font(13)).padding(.horizontal, 18).frame(height: 44)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.35)))
    }
    .buttonStyle(.plain)
  }

  func link(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).font(Look.font(12)).foregroundColor(Look.soft).underline() }
      .buttonStyle(.plain)
  }
}
