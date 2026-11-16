// The setup assistant's logic, with no window: the steps, each step's permissions, when a
// step is complete, and the summary at the end. Tested by tests/setup_model_test.swift.

import Foundation

enum Grant {
  case granted, denied
}

// One app's permission within a step. checkable: omv can read whether it's granted; the
// rest the user ticks once they've turned it on.
struct SetupPermission {
  let key: String
  let app: String
  let appPath: String
  let checkable: Bool
}

struct SetupStep {
  let id: String
  let title: String
  let purpose: String
  let pane: String
  let permissions: [SetupPermission]

  var paneURL: String { "x-apple.systempreferences:com.apple.preference.security?" + pane }
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
        SetupPermission(key: "aerospace.accessibility", app: "AeroSpace", appPath: aerospace, checkable: true),
        SetupPermission(key: "hammerspoon.accessibility", app: "Hammerspoon", appPath: hammerspoon, checkable: true),
        SetupPermission(key: "swipe.accessibility", app: "SwipeAeroSpace", appPath: swipe, checkable: false),
      ]),
    SetupStep(id: "screen", title: "Screen Recording",
      purpose: "Lets the capture menu take screenshots, read text from the screen and record it.",
      pane: "Privacy_ScreenCapture", permissions: [
        SetupPermission(key: "hammerspoon.screen", app: "Hammerspoon", appPath: hammerspoon, checkable: true),
      ]),
    SetupStep(id: "location", title: "Location Services",
      purpose: "Gives the weather for where the Mac is, and the Wi-Fi network's name.",
      pane: "Privacy_LocationServices", permissions: [
        SetupPermission(key: "hammerspoon.location", app: "Hammerspoon", appPath: hammerspoon, checkable: true),
      ]),
    SetupStep(id: "microphone", title: "Microphone",
      purpose: "Lets the Sound card show your microphone's level.",
      pane: "Privacy_Microphone", permissions: [
        SetupPermission(key: "meter.microphone", app: "omv meter", appPath: home + "/.cache/omv/Meter.app", checkable: false),
      ]),
    SetupStep(id: "calendars", title: "Calendars",
      purpose: "Shows today's events in the calendar card and the next meeting in the bar.",
      pane: "Privacy_Calendars", permissions: [
        SetupPermission(key: "agenda.calendars", app: "omv agenda", appPath: home + "/.cache/omv/Agenda.app", checkable: false),
      ]),
    SetupStep(id: "bluetooth", title: "Bluetooth",
      purpose: "Lets the Bluetooth card list and connect your devices.",
      pane: "Privacy_Bluetooth", permissions: [
        SetupPermission(key: "hammerspoon.bluetooth", app: "Hammerspoon", appPath: hammerspoon, checkable: false),
      ]),
    SetupStep(id: "disk", title: "Full Disk Access",
      purpose: "Lets the bar show when Do Not Disturb is on.",
      pane: "Privacy_AllFiles", permissions: [
        SetupPermission(key: "hammerspoon.disk", app: "Hammerspoon", appPath: hammerspoon, checkable: true),
      ]),
  ]

  static let screens: [String] = ["welcome"] + steps.map(\.id) + ["done"]

  // What Hammerspoon reports, asked with SetupChecks.hammerspoonQuestion: four fields,
  // accessibility, screen recording, location, full disk access.
  static func hammerspoonGrants(_ answer: String) -> [String: Grant] {
    let fields = answer.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
    guard fields.count == 4 else { return [:] }
    func grant(_ yes: Bool) -> Grant { yes ? .granted : .denied }
    return [
      "hammerspoon.accessibility": grant(fields[0] == "true"),
      "hammerspoon.screen": grant(fields[1] == "true"),
      "hammerspoon.location": grant(fields[2] == "authorized"),
      "hammerspoon.disk": grant(fields[3] == "true"),
    ]
  }
}
