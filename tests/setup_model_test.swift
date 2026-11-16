// The setup assistant's logic: its steps, when a step is complete, and the summary.
// Compiled with install/setup/SetupModel.swift and run by setup_model_test.sh.

import Foundation

var failed = 0

func check(_ name: String, _ passed: Bool) {
  print((passed ? "ok   - " : "FAIL - ") + name)
  if !passed { failed += 1 }
}

func step(_ id: String) -> SetupStep { SetupModel.steps.first { $0.id == id }! }

@main
struct SetupModelTests {
  static func main() {
    check("should put Welcome first and Done last when listing the screens",
      SetupModel.screens.first == "welcome" && SetupModel.screens.last == "done")

    check("should give each permission step a screen between Welcome and Done",
      SetupModel.screens == ["welcome"] + SetupModel.steps.map(\.id) + ["done"])

    check("should cover every permission omv needs",
      SetupModel.steps.map(\.id) == ["accessibility", "screen", "location", "microphone", "calendars", "bluetooth", "disk"])

    check("should complete a step when every permission it can check is granted", {
      var progress = SetupProgress()
      progress.grants = ["hammerspoon.screen": .granted]
      return progress.isComplete(step("screen"))
    }())

    check("should keep a step open while a permission it can check isn't granted", {
      var progress = SetupProgress()
      progress.grants = ["aerospace.accessibility": .granted, "hammerspoon.accessibility": .denied]
      progress.ticked = ["swipe.accessibility"]
      return !progress.isComplete(step("accessibility"))
    }())

    check("should count a permission it can't check once it's ticked", {
      var progress = SetupProgress()
      progress.grants = ["aerospace.accessibility": .granted, "hammerspoon.accessibility": .granted]
      progress.ticked = ["swipe.accessibility"]
      return progress.isComplete(step("accessibility"))
    }())

    check("should keep a step open while a permission it can't check isn't ticked", {
      var progress = SetupProgress()
      progress.grants = ["aerospace.accessibility": .granted, "hammerspoon.accessibility": .granted]
      return !progress.isComplete(step("accessibility"))
    }())

    check("should count granted, skipped and by-hand steps in the summary", {
      var progress = SetupProgress()
      progress.grants = ["hammerspoon.screen": .granted, "hammerspoon.location": .granted]
      progress.skipped = ["bluetooth"]
      let summary = progress.summary(SetupModel.steps)
      return summary.granted == 2 && summary.skipped == 1 && summary.byHand == ["microphone", "calendars"]
        && summary.missing == ["accessibility", "disk"]
    }())

    check("should start at the first open step when a later run finds earlier ones done", {
      var progress = SetupProgress()
      progress.grants = ["aerospace.accessibility": .granted, "hammerspoon.accessibility": .granted, "hammerspoon.screen": .granted]
      progress.ticked = ["swipe.accessibility"]
      return progress.firstOpenStep(SetupModel.steps) == "location"
    }())

    check("should read Hammerspoon's answer into grants", {
      let grants = SetupModel.hammerspoonGrants("true,false,authorized,true")
      return grants["hammerspoon.accessibility"] == .granted && grants["hammerspoon.screen"] == .denied
        && grants["hammerspoon.location"] == .granted && grants["hammerspoon.disk"] == .granted
    }())

    check("should read nothing from Hammerspoon when it doesn't answer", SetupModel.hammerspoonGrants("").isEmpty)

    check("should open each step's Privacy pane", step("disk").paneURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    exit(failed == 0 ? 0 : 1)
  }
}
