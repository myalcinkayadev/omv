// The setup assistant's logic, with no window: the steps, each step's permissions, when a
// step is complete, and the summary at the end. Tested by tests/setup_model_test.swift.

import CoreGraphics
import Foundation

enum Grant {
  case granted, denied
}

// How the user grants a permission: drag the app into a System Settings list that has an add
// button; ask, where the list has none and the app itself must bring up macOS's prompt; or
// tick, where omv can't read the permission at all.
enum GrantWay {
  case drag, ask, tick
}

// One app's permission within a step. omv reads whether it's granted unless it's a tick.
struct SetupPermission {
  let key: String
  let app: String
  let appPath: String
  let way: GrantWay

  var checkable: Bool { way != .tick }
}

struct SetupStep {
  let id: String
  let title: String
  let purpose: String
  let pane: String
  let permissions: [SetupPermission]

  var paneURL: String { "x-apple.systempreferences:com.apple.preference.security?" + pane }

  // macOS applies Screen Recording only when the app starts again.
  var needsRestart: Bool { id == "screen" }
}

struct SetupSummary {
  let granted: Int
  let skipped: Int
  let byHand: [String]
  let missing: [String]
}

struct SetupProgress {
  var grants: [String: Grant] = [:]
  var ticked: Set<String> = []
  var skipped: Set<String> = []
  // Permissions whose prompt omv brought up and whose answer hasn't come yet.
  var asking: Set<String> = []

  // New readings; a permission with an answer is no longer being asked.
  mutating func take(_ readings: [String: Grant]) {
    grants = readings
    asking = asking.filter { grants[$0] == nil }
  }

  // A request that ended with no answer, say a helper that couldn't build: offer it again.
  mutating func requestEnded(_ key: String) {
    if grants[key] == nil { asking.remove(key) }
  }

  func isGranted(_ permission: SetupPermission) -> Bool {
    permission.checkable ? grants[permission.key] == .granted : ticked.contains(permission.key)
  }

  func isComplete(_ step: SetupStep) -> Bool {
    step.permissions.allSatisfy(isGranted)
  }

  // The first step neither complete nor skipped, or "done" when there's none.
  func firstOpenStep(_ steps: [SetupStep]) -> String {
    steps.first { !isComplete($0) && !skipped.contains($0.id) }?.id ?? "done"
  }

  // A step that's neither complete nor skipped is "by hand" when only unticked permissions
  // omv can't read hold it back, else "missing".
  func summary(_ steps: [SetupStep]) -> SetupSummary {
    var granted = 0, skippedCount = 0
    var byHand: [String] = [], missing: [String] = []
    for step in steps {
      if isComplete(step) { granted += 1; continue }
      if skipped.contains(step.id) { skippedCount += 1; continue }
      let blockedByCheck = step.permissions.contains { $0.checkable && !isGranted($0) }
      if blockedByCheck { missing.append(step.id) } else { byHand.append(step.id) }
    }
    return SetupSummary(granted: granted, skipped: skippedCount, byHand: byHand, missing: missing)
  }
}

enum SetupModel {
  static let hammerspoon = "/Applications/Hammerspoon.app"
  static let aerospace = "/Applications/AeroSpace.app"
  static let swipe = "/Applications/SwipeAeroSpace.app"
  static let home = FileManager.default.homeDirectoryForCurrentUser.path

  static let steps: [SetupStep] = [
    SetupStep(id: "accessibility", title: "Accessibility",
      purpose: "Lets AeroSpace tile windows, SwipeAeroSpace follow your swipes, and Hammerspoon show the volume and brightness pop-ups.",
      pane: "Privacy_Accessibility", permissions: [
        SetupPermission(key: "aerospace.accessibility", app: "AeroSpace", appPath: aerospace, way: .drag),
        SetupPermission(key: "hammerspoon.accessibility", app: "Hammerspoon", appPath: hammerspoon, way: .drag),
        SetupPermission(key: "swipe.accessibility", app: "SwipeAeroSpace", appPath: swipe, way: .tick),
      ]),
    SetupStep(id: "screen", title: "Screen Recording",
      purpose: "Lets the capture menu take screenshots, read text from the screen and record it.",
      pane: "Privacy_ScreenCapture", permissions: [
        SetupPermission(key: "hammerspoon.screen", app: "Hammerspoon", appPath: hammerspoon, way: .drag),
      ]),
    SetupStep(id: "location", title: "Location Services",
      purpose: "Gives the weather for where the Mac is, and the Wi-Fi network's name.",
      pane: "Privacy_LocationServices", permissions: [
        SetupPermission(key: "hammerspoon.location", app: "Hammerspoon", appPath: hammerspoon, way: .ask),
      ]),
    SetupStep(id: "microphone", title: "Microphone",
      purpose: "Lets the Sound card show your microphone's level.",
      pane: "Privacy_Microphone", permissions: [
        SetupPermission(key: "meter.microphone", app: "omv meter", appPath: home + "/.cache/omv/Meter.app", way: .ask),
      ]),
    SetupStep(id: "calendars", title: "Calendars",
      purpose: "Shows today's events in the calendar card and the next meeting in the bar.",
      pane: "Privacy_Calendars", permissions: [
        SetupPermission(key: "agenda.calendars", app: "omv agenda", appPath: home + "/.cache/omv/Agenda.app", way: .ask),
      ]),
    SetupStep(id: "bluetooth", title: "Bluetooth",
      purpose: "Lets the Bluetooth card list and connect your devices.",
      pane: "Privacy_Bluetooth", permissions: [
        SetupPermission(key: "hammerspoon.bluetooth", app: "Hammerspoon", appPath: hammerspoon, way: .ask),
      ]),
    SetupStep(id: "disk", title: "Full Disk Access",
      purpose: "Lets the bar show when Do Not Disturb is on.",
      pane: "Privacy_AllFiles", permissions: [
        SetupPermission(key: "hammerspoon.disk", app: "Hammerspoon", appPath: hammerspoon, way: .drag),
      ]),
  ]

  static let screens: [String] = ["welcome", "install"] + steps.map(\.id) + ["done"]

  // A string as a Lua literal, for paths sent to Hammerspoon in hs -c.
  static func luaQuoted(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\"" + escaped + "\""
  }

  // Where the setup window goes when System Settings opens: beside it, on the right when it
  // fits, else on the left, top edges aligned and kept on screen. Nothing when neither side
  // has room or System Settings isn't on screen; the window then stays put. Frames use a
  // top-left origin, as the window list reports them.
  static func besideSettings(settings: CGRect?, screen: CGRect, size: CGSize, gap: CGFloat = 12) -> CGRect? {
    guard let settings else { return nil }
    let right = settings.maxX + gap
    let left = settings.minX - gap - size.width
    let x: CGFloat
    if right + size.width <= screen.maxX {
      x = right
    } else if left >= screen.minX {
      x = left
    } else {
      return nil
    }
    let y = max(screen.minY, min(settings.minY, screen.maxY - size.height))
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  // What Hammerspoon reports, asked with SetupChecks.hammerspoonQuestion: four fields,
  // accessibility, screen recording, location, full disk access.
  static func hammerspoonGrants(_ answer: String) -> [String: Grant] {
    let fields = answer.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
    guard fields.count == 4 else { return [:] }
    func grant(_ yes: Bool) -> Grant { yes ? .granted : .denied }
    var grants = [
      "hammerspoon.accessibility": grant(fields[0] == "true"),
      "hammerspoon.screen": grant(fields[1] == "true"),
      "hammerspoon.disk": grant(fields[3] == "true"),
    ]
    // Never asked: left open, so the step offers to ask.
    if fields[2] != "notDetermined" { grants["hammerspoon.location"] = grant(fields[2] == "authorized") }
    return grants
  }

  // What the access files in ~/.local/state/omv/access say, by file name. The meter and the
  // agenda write granted, denied or undetermined; for Bluetooth, Hammerspoon writes what
  // blueutil --power printed, which is empty when Hammerspoon has no access. A file that
  // isn't there, or says nothing it knows, leaves its permission open.
  static func accessGrants(_ files: [String: String]) -> [String: Grant] {
    var grants: [String: Grant] = [:]
    for (helper, key) in [("microphone", "meter.microphone"), ("calendars", "agenda.calendars")] {
      switch files[helper]?.trimmingCharacters(in: .whitespacesAndNewlines) {
      case "granted": grants[key] = .granted
      case "denied": grants[key] = .denied
      default: break
      }
    }
    if let power = files["bluetooth"] {
      let first = power.trimmingCharacters(in: .whitespacesAndNewlines).first
      grants["hammerspoon.bluetooth"] = first == "0" || first == "1" ? .granted : .denied
    }
    return grants
  }
}
