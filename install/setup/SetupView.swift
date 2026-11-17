// The setup assistant's window: steps on the left, the current one on the right, in omv's
// look (black, gray borders, white, JetBrainsMono). In install mode it runs the install first,
// showing each step; then the permissions, which it checks every second, so a step ticks
// itself as the user turns a switch on in System Settings.

import AppKit
import Combine
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

  static let aerospaceID = SetupModel.aerospaceID

  // Opens an app in the background, by its bundle ID.
  static func openApp(_ bundleID: String) {
    run("/usr/bin/open", ["-g", "-b", bundleID])
  }

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
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return (-1, "") }
    // Read to the end first: a full pipe would otherwise keep the process from exiting.
    let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    return (process.terminationStatus, text)
  }

  static func read() -> [String: Grant] {
    var grants: [String: Grant] = [:]
    if let hs = tool("hs") {
      let answer = run(hs, ["-t", "2", "-c", hammerspoonQuestion]).1
      grants = SetupModel.hammerspoonGrants(answer.split(separator: "\n").last.map(String.init) ?? "")
    }
    if let aerospace = tool("aerospace") {
      let running = !NSRunningApplication.runningApplications(withBundleIdentifier: aerospaceID).isEmpty
      grants["aerospace.accessibility"] = SetupModel.aerospaceGrant(running: running,
        listed: running && run(aerospace, ["list-windows", "--all"]).0 == 0)
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
  // Says what's missing when it can't ask.
  static func bluetoothAccess() -> String? {
    guard let hs = tool("hs") else { return "Hammerspoon's hs command is missing: omv install" }
    guard let blueutil = tool("blueutil") else { return "blueutil is missing: brew install blueutil" }
    try? FileManager.default.createDirectory(at: accessDir, withIntermediateDirectories: true)
    let file = SetupModel.luaQuoted(accessDir.appendingPathComponent("bluetooth").path)
    let lua = "omvSetupBluetooth = hs.task.new(\(SetupModel.luaQuoted(blueutil)), function(_, out) "
      + "local f = io.open(\(file), \"w\") if f then f:write(out or \"\") f:close() end end, {\"--power\"}) "
      + "omvSetupBluetooth:start()"
    return run(hs, ["-t", "2", "-c", lua]).0 == 0 ? nil : "Hammerspoon didn't answer; is it running?"
  }

  // Location: Hammerspoon starting its location updates brings up the prompt.
  static func locationAccess() -> String? {
    guard let hs = tool("hs") else { return "Hammerspoon's hs command is missing: omv install" }
    return run(hs, ["-t", "2", "-c", "hs.location.start()"]).0 == 0 ? nil : "Hammerspoon didn't answer; is it running?"
  }

  // System Settings' frontmost window, from the window list (top-left origin). Its owner needs
  // no Screen Recording permission, unlike its title.
  static func settingsFrame() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // By its process, not its name, which is translated on a Mac in another language.
    let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
      .map(\.processIdentifier)
    for window in windows where settings.contains(window[kCGWindowOwnerPID as String] as? pid_t ?? -1)
      && (window[kCGWindowLayer as String] as? Int) == 0 {
      if let bounds = window[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) {
        return rect
      }
    }
    return nil
  }

  // Moves the setup window beside System Settings, so the apps can be dragged straight across.
  // AppKit counts from the bottom of the main screen, the window list from its top.
  // The window's screen, with a top-left origin like the window list's, or nil off screen.
  static func screenTopLeft(_ window: NSWindow) -> CGRect? {
    guard let screen = window.screen ?? NSScreen.main else { return nil }
    let visible = screen.visibleFrame
    return CGRect(x: visible.minX, y: mainHeight(screen) - visible.maxY, width: visible.width, height: visible.height)
  }

  static func mainHeight(_ screen: NSScreen) -> CGFloat {
    NSScreen.screens.first?.frame.height ?? screen.frame.height
  }

  // Puts the window at a top-left frame, resizing it when the layout changes.
  static func place(_ window: NSWindow, at frame: CGRect) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    let bottomLeft = NSRect(x: frame.minX, y: mainHeight(screen) - frame.minY - frame.height, width: frame.width, height: frame.height)
    window.setFrame(bottomLeft, display: true, animate: window.frame.size != bottomLeft.size)
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
  // Compact while a drag step's apps are dragged into System Settings beside it.
  @Published var layout = SetupLayout.full
  private var fullOrigin: NSPoint?
  private var expandedByHand: Set<String> = []
  // Why a permission can't be asked for, by its key.
  @Published var problems: [String: String] = [:]
  let installer: Installer?
  let repo: String?
  private var timer: Timer?
  private var ticks = 0
  private var probing: Set<String> = []
  private var reading = false
  private var installerChanges: AnyCancellable?

  init(installer: Installer?, repo: String?) {
    self.installer = installer
    self.repo = repo
    // The install's steps redraw as they change, not only on the next tick.
    installerChanges = installer?.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
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

  static let helperKeys = ["microphone": "meter.microphone", "calendars": "agenda.calendars", "bluetooth": "hammerspoon.bluetooth"]

  // Reads one helper's access again, at most one run at a time each. Bluetooth only once it
  // was asked, as a first probe would bring up the prompt unasked. The meter and the agenda
  // wait for the prompt's answer, so once one ends a request with no answer is offered again.
  private func probe(_ name: String, request: Bool = false) {
    guard !probing.contains(name) else { return }
    if name == "bluetooth" && !request && !hasAsked(name) { return }
    let key = SetupState.helperKeys[name]!
    guard name == "bluetooth" || repo != nil else {
      if request { cannotAsk(key, "opened without omv's folder: run omv setup") }
      return
    }
    probing.insert(name)
    let repo = repo
    DispatchQueue.global().async {
      var problem: String?
      if name == "bluetooth" { problem = SetupChecks.bluetoothAccess() } else { SetupChecks.helperAccess(repo!, name, request: request) }
      let answers = SetupChecks.readAccess()
      DispatchQueue.main.async {
        self.probing.remove(name)
        guard request else { return }
        if let problem { self.cannotAsk(key, problem); return }
        guard name != "bluetooth" else { return }
        self.progress.take(self.progress.grants.merging(answers) { $1 })
        self.progress.requestEnded(key)
      }
    }
  }

  private func cannotAsk(_ key: String, _ problem: String) {
    problems[key] = problem
    progress.requestEnded(key)
  }

  // Brings up macOS's prompt for a permission whose list has no add button.
  func ask(_ permission: SetupPermission) {
    problems[permission.key] = nil
    progress.asking.insert(permission.key)
    if let name = SetupState.helperKeys.first(where: { $0.value == permission.key })?.key {
      probe(name, request: true)
      return
    }
    DispatchQueue.global().async {
      let problem = SetupChecks.locationAccess()
      DispatchQueue.main.async { if let problem { self.cannotAsk(permission.key, problem) } }
    }
  }

  var screens: [String] { SetupModel.screens }

  // Hammerspoon and AeroSpace every second; the helpers' answers on their own step every 3,
  // since each one starts an app.
  func refresh() {
    ticks += 1
    if ticks % 3 == 0, SetupState.helperKeys[screen] != nil { probe(screen) }
    if layout == .compact { arrange() }
    // One reading at a time: hs can take 2 seconds, and an older answer mustn't land last.
    guard !reading else { return }
    reading = true
    DispatchQueue.global().async {
      let grants = SetupChecks.read().merging(SetupChecks.readAccess()) { $1 }
      DispatchQueue.main.async {
        self.progress.take(grants)
        self.reading = false
        self.openAppsOnce()
      }
    }
  }

  var step: SetupStep? { SetupModel.steps.first { $0.id == screen } }

  // Apps already opened by this window, each once; after that, AeroSpace's card offers to.
  private var openedApps: Set<String> = []

  // On the Accessibility step, AeroSpace and SwipeAeroSpace are opened if they're closed.
  private func openAppsOnce() {
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    for bundleID in SetupModel.appsToOpen(screen: screen, running: running) where !openedApps.contains(bundleID) {
      openedApps.insert(bundleID)
      DispatchQueue.global().async { SetupChecks.openApp(bundleID) }
    }
  }

  func go(_ id: String) {
    screen = id
    if layout == .compact { restoreFull() }
  }

  func next() {
    let index = screens.firstIndex(of: screen) ?? 0
    go(screens[min(index + 1, screens.count - 1)])
  }

  func back() {
    let index = screens.firstIndex(of: screen) ?? 0
    go(screens[max(index - 1, 0)])
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
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.arrange() }
    }
  }

  var window: NSWindow? { NSApp.windows.first { $0.title == "omv Setup" } }

  // Moves the window beside System Settings, collapsing it to the compact panel when the full
  // window has no room there, and back to the full window when the step is done or System
  // Settings is gone.
  func arrange() {
    guard let window, let step, let screen = SetupChecks.screenTopLeft(window) else { return }
    let place = SetupModel.placement(step: step, complete: progress.isComplete(step),
      settings: SetupChecks.settingsFrame(), screen: screen)
    if place.layout == .compact && !expandedByHand.contains(step.id) {
      if layout == .full { fullOrigin = window.frame.origin }
      layout = .compact
      if let frame = place.frame { SetupChecks.place(window, at: frame) }
      return
    }
    if layout == .compact { restoreFull(); return }
    if let frame = place.frame { SetupChecks.place(window, at: frame) }
  }

  // Show all, from the compact panel: the full window, and no collapsing again on this step.
  func expand() {
    if let step { expandedByHand.insert(step.id) }
    restoreFull()
  }

  private func restoreFull() {
    layout = .full
    guard let window else { return }
    let origin = fullOrigin ?? window.frame.origin
    let top = window.frame.maxY
    window.setFrame(NSRect(x: origin.x, y: fullOrigin == nil ? top - SetupModel.windowSize.height : origin.y,
      width: SetupModel.windowSize.width, height: SetupModel.windowSize.height), display: true, animate: true)
    fullOrigin = nil
  }

  // Install is reached through Welcome's button, which starts it; before that, the sidebar
  // would show an install screen with nothing running.
  func canGo(_ id: String) -> Bool {
    id != "install" || installer == nil || installer?.started != nil
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
    if state.layout == .compact, let step = state.step {
      compactPanel(step)
        .frame(width: SetupModel.compactSize(apps: 0).width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Look.ground)
        .foregroundColor(.white)
        .environmentObject(state)
    } else {
      fullWindow
    }
  }

  // Only the step's apps, to drag into System Settings beside it, and a way back.
  func compactPanel(_ step: SetupStep) -> some View {
    let complete = state.progress.isComplete(step)
    let granted = step.permissions.filter(state.progress.isGranted).count
    return VStack(alignment: .leading, spacing: 12) {
      Text(step.title).font(Look.font(16, .bold))
      Text("Drag each app into the list in System Settings, then turn it on.")
        .font(Look.font(12)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      ForEach(step.permissions, id: \.key) { AppRow(permission: $0) }
      if step.needsRestart && !complete {
        Text("macOS applies Screen Recording only when Hammerspoon starts again.")
          .font(Look.font(11)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
        secondary("Restart Hammerspoon") { SetupChecks.restartHammerspoon() }
      }
      Spacer(minLength: 0)
      HStack {
        link("Show all") { state.expand() }
        Spacer()
        Text("\(granted) of \(step.permissions.count) granted").font(Look.font(11)).foregroundColor(Look.faint)
      }
    }
    .padding(20)
  }

  var fullWindow: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(Look.line).frame(width: 1)
      VStack(alignment: .leading, spacing: 16) { content }
        .padding(EdgeInsets(top: 32, leading: 40, bottom: 24, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: SetupModel.windowSize.width, height: SetupModel.windowSize.height)
    .background(Look.ground)
    .foregroundColor(.white)
    .environmentObject(state)
  }

  var sidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(state.screens, id: \.self) { id in
        if let group = group(before: id) {
          Text(group.uppercased()).font(Look.font(10)).tracking(1.4).foregroundColor(Color(white: 0.44))
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 2, trailing: 10))
        }
        Button { if state.canGo(id) { state.go(id) } } label: {
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
      tally
    }
    .font(Look.font(13))
    .padding(16)
    .frame(width: 220)
  }

  // A label above the first needed step and the first optional one.
  func group(before id: String) -> String? {
    guard let index = SetupModel.steps.firstIndex(where: { $0.id == id }) else { return nil }
    let step = SetupModel.steps[index]
    if index == 0 { return step.needed ? "Needed" : "Optional" }
    return SetupModel.steps[index - 1].needed && !step.needed ? "Optional" : nil
  }

  var tally: some View {
    let granted = SetupModel.steps.filter(state.progress.isComplete).count
    let total = SetupModel.steps.count
    return VStack(alignment: .leading, spacing: 8) {
      Rectangle().fill(Look.line).frame(height: 1)
      Text("\(granted) of \(total) granted").font(Look.font(11)).foregroundColor(Look.faint).padding(.horizontal, 10)
      GeometryReader { box in
        ZStack(alignment: .leading) {
          Rectangle().fill(Color(white: 0.16))
          Rectangle().fill(Color.white).frame(width: box.size.width * CGFloat(granted) / CGFloat(total))
        }
      }
      .frame(height: 4).padding(.horizontal, 10)
    }
    .accessibilityElement(children: .combine)
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
      Text("Only Accessibility is needed: it lets AeroSpace tile your windows. The other six each turn on one extra, and the window shows which.")
        .font(Look.font(14)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      Text("Skip any permission and come back with omv setup.").font(Look.font(13)).foregroundColor(Look.faint)
      Spacer()
      if !installing { HStack { Spacer(); installedStatus; Spacer() } }
      Spacer()
      HStack { Spacer(); primary(installing ? "Install  →" : "Start  →") { state.start() } }
    }
  }

  // Where omv stands when setup opens on an installed Mac: a large tick for what's done, then
  // what's done and what's left, read from the permissions as they are now.
  var installedStatus: some View {
    let needed = SetupModel.steps.filter(\.needed)
    let optional = SetupModel.steps.filter { !$0.needed }
    let neededDone = needed.allSatisfy(state.progress.isComplete)
    let optionalDone = optional.filter(state.progress.isComplete).count
    return VStack(spacing: 18) {
      Text("✓").font(Look.font(34, .bold)).foregroundColor(.black)
        .frame(width: 76, height: 76).background(Circle().fill(Color.white))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        statusRow(done: true, "omv", "tools, apps and configs in place")
        statusRow(done: neededDone, needed.map(\.title).joined(separator: ", "), neededDone ? "granted" : "needed, not granted yet")
        statusRow(done: optionalDone == optional.count, "Optional", "\(optionalDone) of \(optional.count) granted")
      }
      .frame(width: 440)
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Look.line))
    }
  }

  func statusRow(done: Bool, _ name: String, _ detail: String) -> some View {
    HStack(spacing: 12) {
      Text(done ? "✓" : "○").frame(width: 16).foregroundColor(done ? .white : Look.faint)
      Text(name).foregroundColor(.white)
      Spacer()
      Text(detail).foregroundColor(done ? Look.soft : Look.faint)
    }
    .font(Look.font(13))
    .padding(.horizontal, 16).frame(height: 44)
    .accessibilityElement(children: .combine)
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
    let index = (SetupModel.steps.firstIndex { $0.id == step.id } ?? 0) + 1
    return VStack(spacing: 0) {
      ScrollView {
        HStack(alignment: .top, spacing: 28) {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
              Text("\(step.needed ? "Needed" : "Optional") · \(index) of \(SetupModel.steps.count)".uppercased())
                .font(Look.font(11)).tracking(1.5).foregroundColor(Look.faint)
              Text(step.title).font(Look.font(24, .bold))
              Text(step.purpose).font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 6)
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
                    .fixedSize(horizontal: false, vertical: true)
                  primary("Restart Hammerspoon") { SetupChecks.restartHammerspoon() }
                }
              }
            }
          }
          .frame(width: 300, alignment: .leading)
          TurnsOn(step: step).frame(width: 370, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      Rectangle().fill(Look.line).frame(height: 1).padding(.horizontal, -40)
      HStack(spacing: 10) {
        secondary("Skip") { state.skip() }
        Spacer()
        secondary("←  Back") { state.back() }
        primary("Next  →", enabled: complete) { state.next() }
      }
      .padding(.top, 14)
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
        ForEach(step.permissions, id: \.key) { AppRow(permission: $0) }
      }
    }
  }

  // Lists with no add button: the app asks, macOS shows its prompt. System Settings only
  // for an app that was refused before.
  @ViewBuilder func askSteps(_ step: SetupStep, complete: Bool) -> some View {
    HStack(alignment: .top, spacing: 14) {
      number("1", done: complete)
      VStack(alignment: .leading, spacing: 12) {
        Text("Press \(SetupModel.askButton), and macOS asks you about \(step.permissions[0].app).")
          .font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
        ForEach(step.permissions, id: \.key) { AppRow(permission: $0) }
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
