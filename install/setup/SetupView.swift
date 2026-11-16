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

  // Where the meter, the agenda and Hammerspoon's Bluetooth probe write what access they have.
  static let accessDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/omv/access")

  static func readAccess() -> [String: Grant] {
    var files: [String: String] = [:]
    for name in ["microphone", "calendars", "bluetooth"] {
      if let text = try? String(contentsOf: accessDir.appendingPathComponent(name), encoding: .utf8) { files[name] = text }
    }
    return SetupModel.accessGrants(files)
  }

  // Runs the meter or the agenda in access mode, which waits for it. request brings up
  // macOS's prompt when the helper was never asked.
  static func helperAccess(_ repo: String, _ name: String, request: Bool) {
    let script = ["microphone": "meter.sh", "calendars": "agenda.sh"][name]!
    try? FileManager.default.createDirectory(at: accessDir, withIntermediateDirectories: true)
    run("/bin/sh", [repo + "/config/hammerspoon/" + script, "access", request ? "request" : "status",
      accessDir.appendingPathComponent(name).path])
  }

  // Has Hammerspoon run blueutil --power and write what it printed. Asking Bluetooth this way
  // brings up macOS's prompt for Hammerspoon when it was never asked; the task doesn't block it.
  static func bluetoothAccess() {
    guard let hs = tool("hs"), let blueutil = tool("blueutil") else { return }
    try? FileManager.default.createDirectory(at: accessDir, withIntermediateDirectories: true)
    let file = accessDir.appendingPathComponent("bluetooth").path
    run(hs, ["-t", "2", "-c", """
      omvSetupBluetooth = hs.task.new("\(blueutil)", function(_, out) local f = io.open("\(file)", "w")       if f then f:write(out or "") f:close() end end, {"--power"}) omvSetupBluetooth:start()
      """])
  }

  // Location: Hammerspoon starting its location updates brings up the prompt.
  static func locationAccess() {
    guard let hs = tool("hs") else { return }
    run(hs, ["-t", "2", "-c", "hs.location.start()"])
  }

  // System Settings' frontmost window, from the window list (top-left origin). Its owner's
  // name needs no Screen Recording permission, unlike its title.
  static func settingsFrame() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows where (window[kCGWindowOwnerName as String] as? String) == "System Settings"
      && (window[kCGWindowLayer as String] as? Int) == 0 {
      if let bounds = window[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) {
        return rect
      }
    }
    return nil
  }

  // Moves the setup window beside System Settings, so the apps can be dragged straight across.
  // AppKit counts from the bottom of the main screen, the window list from its top.
  static func moveBesideSettings(_ window: NSWindow) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    let height = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let visible = screen.visibleFrame
    let screenTopLeft = CGRect(x: visible.minX, y: height - visible.maxY, width: visible.width, height: visible.height)
    guard let frame = SetupModel.besideSettings(settings: settingsFrame(), screen: screenTopLeft, size: window.frame.size) else { return }
    window.setFrameOrigin(NSPoint(x: frame.minX, y: height - frame.minY - frame.height))
    window.orderFront(nil)
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
  @Published var asking: Set<String> = []
  let installer: Installer?
  let repo: String?
  private var timer: Timer?
  private var ticks = 0
  private var probing: Set<String> = []

  init(installer: Installer?, repo: String?) {
    self.installer = installer
    self.repo = repo
    refresh()
    for name in ["microphone", "calendars"] { probe(name) }
    if hasAsked("bluetooth") { probe("bluetooth") }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refresh()
      self?.objectWillChange.send()
    }
  }

  private func hasAsked(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: SetupChecks.accessDir.appendingPathComponent(name).path)
  }

  // Reads one helper's access again, at most one run at a time each. Bluetooth only once it
  // was asked, as a first probe would bring up the prompt unasked.
  private func probe(_ name: String, request: Bool = false) {
    guard !probing.contains(name) else { return }
    if name == "bluetooth" && !request && !hasAsked(name) { return }
    if name != "bluetooth" && repo == nil { return }
    probing.insert(name)
    let repo = repo
    DispatchQueue.global().async {
      if name == "bluetooth" { SetupChecks.bluetoothAccess() } else { SetupChecks.helperAccess(repo!, name, request: request) }
      DispatchQueue.main.async { self.probing.remove(name) }
    }
  }

  // Brings up macOS's prompt for a permission whose list has no add button.
  func ask(_ permission: SetupPermission) {
    asking.insert(permission.key)
    switch permission.key {
    case "meter.microphone": probe("microphone", request: true)
    case "agenda.calendars": probe("calendars", request: true)
    case "hammerspoon.bluetooth": probe("bluetooth", request: true)
    default: DispatchQueue.global().async { SetupChecks.locationAccess() }
    }
  }

  var screens: [String] { ["welcome", "install"] + SetupModel.steps.map(\.id) + ["done"] }

  // Hammerspoon and AeroSpace every second; the helpers' answers on their own step every 3,
  // since each one starts an app.
  func refresh() {
    ticks += 1
    if ticks % 3 == 0, ["microphone", "calendars", "bluetooth"].contains(screen) { probe(screen) }
    DispatchQueue.global().async {
      let grants = SetupChecks.read().merging(SetupChecks.readAccess()) { $1 }
      DispatchQueue.main.async {
        self.progress.grants = grants
        self.asking = self.asking.filter { grants[$0] == nil }
      }
    }
  }

  var step: SetupStep? { SetupModel.steps.first { $0.id == screen } }

  func go(_ id: String) { screen = id }

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

  // Opens the step's pane, then moves this window beside System Settings once it's on screen.
  func openSettings(_ step: SetupStep) {
    NSWorkspace.shared.open(URL(string: step.paneURL)!)
    opened.insert(step.id)
    for delay in [0.5, 1.0, 2.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard let window = NSApp.windows.first(where: { $0.title == "omv Setup" }) else { return }
        SetupChecks.moveBesideSettings(window)
      }
    }
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
      if step.permissions.allSatisfy({ $0.way == .ask }) {
        askSteps(step, complete: complete)
      } else {
        dragSteps(step, complete: complete)
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

  // Lists with an add button: open System Settings, then drag each app in.
  @ViewBuilder func dragSteps(_ step: SetupStep, complete: Bool) -> some View {
    HStack(spacing: 14) {
      number("1", done: state.opened.contains(step.id))
      secondary("Open System Settings") { state.openSettings(step) }
    }
    HStack(alignment: .top, spacing: 14) {
      number("2", done: complete)
      VStack(alignment: .leading, spacing: 12) {
        Text("Drag each app from here into the list in System Settings, then turn it on.")
          .font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
        ForEach(step.permissions, id: \.key) { AppRow(permission: $0).frame(width: 320) }
      }
    }
  }

  // Lists with no add button: the app asks, macOS shows its prompt. System Settings only
  // for an app that was refused before.
  @ViewBuilder func askSteps(_ step: SetupStep, complete: Bool) -> some View {
    HStack(alignment: .top, spacing: 14) {
      number("1", done: complete)
      VStack(alignment: .leading, spacing: 12) {
        Text("Press Allow access, then Allow in the prompt macOS shows.")
          .font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
        ForEach(step.permissions, id: \.key) { AppRow(permission: $0).frame(width: 320) }
      }
    }
    if step.permissions.contains(where: { state.progress.grants[$0.key] == .denied }) {
      HStack(alignment: .top, spacing: 14) {
        number("2", done: false)
        VStack(alignment: .leading, spacing: 10) {
          Text("Said no before? macOS won't ask again; switch it on in System Settings.")
            .font(Look.font(13)).fixedSize(horizontal: false, vertical: true)
          secondary("Open System Settings") { state.openSettings(step) }
        }
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
