// The setup assistant's window: steps on the left, the current step on the right, in omv's
// look (black, gray borders, white, JetBrainsMono). Checks the permissions it can read every
// second, so a step ticks itself as the user turns a switch on in System Settings.

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
}

final class SetupState: ObservableObject {
  @Published var progress = SetupProgress()
  @Published var screen = "welcome"
  private var timer: Timer?

  init() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
  }

  func refresh() {
    DispatchQueue.global().async {
      let grants = SetupChecks.read()
      DispatchQueue.main.async { self.progress.grants = grants }
    }
  }

  var step: SetupStep? { SetupModel.steps.first { $0.id == screen } }

  func go(_ id: String) { screen = id }

  func next() {
    let index = SetupModel.screens.firstIndex(of: screen) ?? 0
    screen = SetupModel.screens[min(index + 1, SetupModel.screens.count - 1)]
  }

  // A later run starts at the first step not yet done.
  func start() { screen = progress.firstOpenStep(SetupModel.steps) }

  func skip() {
    if let step { progress.skipped.insert(step.id) }
    next()
  }

  func mark(_ id: String) -> String {
    if id == screen { return "●" }
    if let step = SetupModel.steps.first(where: { $0.id == id }) {
      if progress.isComplete(step) { return "✓" }
      if progress.skipped.contains(id) { return "–" }
      return "○"
    }
    return SetupModel.screens.firstIndex(of: id)! < SetupModel.screens.firstIndex(of: screen)! ? "✓" : "○"
  }
}

struct SetupView: View {
  @StateObject var state = SetupState()

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(Look.line).frame(width: 1)
      VStack(alignment: .leading, spacing: 18) { content }
        .padding(EdgeInsets(top: 36, leading: 40, bottom: 28, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: 860, height: 520)
    .background(Look.ground)
    .foregroundColor(.white)
  }

  var sidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(SetupModel.screens, id: \.self) { id in
        Button { state.go(id) } label: {
          HStack(spacing: 10) {
            Text(state.mark(id)).frame(width: 16)
            Text(title(id))
            Spacer()
          }
          .padding(.horizontal, 10).padding(.vertical, 8)
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
    if id == "welcome" { return "Welcome" }
    if id == "done" { return "Done" }
    return SetupModel.steps.first { $0.id == id }?.title ?? id
  }

  @ViewBuilder var content: some View {
    if state.screen == "welcome" { welcome } else if state.screen == "done" { done } else if let step = state.step { stepView(step) }
  }

  var welcome: some View {
    Group {
      Text("omv is installed.").font(Look.font(26, .bold))
      Text("A few macOS permissions let it work: tiling windows, the bar, the capture menu, weather. Each takes about 10 seconds.")
        .font(Look.font(14)).foregroundColor(Look.soft)
      Text("macOS only lets you grant them yourself. This window opens the right place and ticks each one off as you go.")
        .font(Look.font(14)).foregroundColor(Look.soft)
      Text("Skip any step. Come back with omv setup.").font(Look.font(13)).foregroundColor(Look.faint)
      Spacer()
      HStack { Spacer(); primary("Start  →") { state.start() } }
    }
  }

  func stepView(_ step: SetupStep) -> some View {
    let complete = state.progress.isComplete(step)
    return Group {
      Text(step.title).font(Look.font(24, .bold))
      Text(step.purpose).font(Look.font(13)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 14) {
        number("1")
        secondary("Open System Settings") { NSWorkspace.shared.open(URL(string: step.paneURL)!) }
      }
      HStack(alignment: .top, spacing: 14) {
        number("2")
        VStack(alignment: .leading, spacing: 12) {
          Text("Drag each app into the list, then turn it on.").font(Look.font(13)).foregroundColor(Look.soft)
          HStack(spacing: 16) { ForEach(step.permissions, id: \.key) { appTile($0) } }
          if step.permissions.contains(where: { !$0.checkable }) {
            Text("Ticks itself a second after you flip the switch, where macOS lets omv read it.")
              .font(Look.font(11)).foregroundColor(Look.faint)
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

  func appTile(_ permission: SetupPermission) -> some View {
    let granted = state.progress.isGranted(permission)
    return VStack(spacing: 8) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: permission.appPath))
        .resizable().frame(width: 52, height: 52)
        .onDrag { NSItemProvider(object: URL(fileURLWithPath: permission.appPath) as NSURL) }
        .accessibilityLabel("Drag \(permission.app) into the list")
      Text(permission.app).font(Look.font(12)).lineLimit(1)
      if permission.checkable {
        Text(granted ? "✓ granted" : "◌ waiting").font(Look.font(11)).foregroundColor(granted ? .white : Look.faint)
      } else {
        Toggle("I turned it on", isOn: Binding(
          get: { state.progress.ticked.contains(permission.key) },
          set: { on in
            if on { state.progress.ticked.insert(permission.key) } else { state.progress.ticked.remove(permission.key) }
          }))
          .toggleStyle(.checkbox).font(Look.font(11))
      }
    }
    .frame(width: 124).padding(.vertical, 14)
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(granted ? Color.white : Look.line, style: StrokeStyle(lineWidth: 1, dash: granted ? [] : [4])))
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
      Text("Try it: Option+/ shows every key. Run omv setup any time to come back.").font(Look.font(13)).foregroundColor(Look.soft)
      Spacer()
      HStack { Spacer(); primary("Finish") { NSApp.terminate(nil) } }
    }
  }

  func number(_ text: String) -> some View {
    Text(text).font(Look.font(12)).foregroundColor(Look.soft)
      .frame(width: 26, height: 26).overlay(Circle().stroke(Color(white: 0.35)))
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
}
