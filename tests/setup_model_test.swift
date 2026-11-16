// The setup assistant's logic: its steps, when a step is complete, and the summary.
// Compiled with install/setup/SetupModel.swift and run by setup_model_test.sh.

import CoreGraphics
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
      progress.grants = ["hammerspoon.screen": .granted, "hammerspoon.location": .granted,
        "aerospace.accessibility": .granted, "hammerspoon.accessibility": .granted]
      progress.skipped = ["bluetooth"]
      let summary = progress.summary(SetupModel.steps)
      return summary.granted == 2 && summary.skipped == 1 && summary.byHand == ["accessibility"]
        && summary.missing == ["microphone", "calendars", "disk"]
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

    check("should leave location open when Hammerspoon was never asked",
      SetupModel.hammerspoonGrants("true,true,notDetermined,true")["hammerspoon.location"] == nil)

    check("should read nothing from Hammerspoon when it doesn't answer", SetupModel.hammerspoonGrants("").isEmpty)

    check("should open each step's Privacy pane", step("disk").paneURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    check("should read a step's start and done markers into its state", {
      var run = InstallRun()
      run.consume("omv-step: taps start")
      run.consume("omv-step: taps done 4 trusted")
      run.consume("omv-step: tools start")
      return run.state("taps") == .done && run.summary("taps") == "4 trusted" && run.state("tools") == .running
        && run.state("configs") == .pending
    }())

    check("should keep a step's last output line as its live detail", {
      var run = InstallRun()
      run.consume("omv-step: tools start")
      run.consume("Installing hammerspoon")
      run.consume("")
      return run.detail("tools") == "Installing hammerspoon"
    }())

    check("should mark the running step failed when the install exits non-zero", {
      var run = InstallRun()
      run.consume("omv-step: configs start")
      run.finish(status: 1)
      return run.state("configs") == .failed
    }())

    check("should finish every step when the install exits zero", {
      var run = InstallRun()
      for step in InstallRun.steps { run.consume("omv-step: \(step.id) start"); run.consume("omv-step: \(step.id) done ok") }
      run.finish(status: 0)
      return run.isFinished && InstallRun.steps.allSatisfy { run.state($0.id) == .done }
    }())

    check("should explain a Stow conflict with the file in the way",
      InstallRun.failureReason([
        "WARNING! stowing sketchybar would cause conflicts:",
        "  * cannot stow config/sketchybar/.config/sketchybar/sketchybarrc over existing target .config/sketchybar/sketchybarrc since neither a link nor a directory and --adopt not specified",
      ]) == "~/.config/sketchybar/sketchybarrc already exists, where omv links its own.")

    check("should explain a failed brew bundle",
      InstallRun.failureReason(["Installing foo has failed!", "`brew bundle` failed! 1 Brewfile dependency failed to install"])
        == "Homebrew couldn't install everything in the Brewfile.")

    check("should fall back to the last error line for an unknown failure",
      InstallRun.failureReason(["working", "something broke", ""]) == "something broke")

    check("should place the window to the right of System Settings when it fits",
      SetupModel.besideSettings(settings: CGRect(x: 100, y: 100, width: 800, height: 600),
        screen: CGRect(x: 0, y: 0, width: 1600, height: 1000), size: CGSize(width: 300, height: 400))
        == CGRect(x: 912, y: 100, width: 300, height: 400))

    check("should place the window to the left when only the left has room",
      SetupModel.besideSettings(settings: CGRect(x: 700, y: 100, width: 800, height: 600),
        screen: CGRect(x: 0, y: 0, width: 1600, height: 1000), size: CGSize(width: 300, height: 400))
        == CGRect(x: 388, y: 100, width: 300, height: 400))

    check("should leave the window where it is when neither side has room",
      SetupModel.besideSettings(settings: CGRect(x: 400, y: 100, width: 800, height: 600),
        screen: CGRect(x: 0, y: 0, width: 1600, height: 1000), size: CGSize(width: 860, height: 560)) == nil)

    check("should keep the window on screen when System Settings sits low",
      SetupModel.besideSettings(settings: CGRect(x: 100, y: 700, width: 800, height: 600),
        screen: CGRect(x: 0, y: 0, width: 1600, height: 1000), size: CGSize(width: 300, height: 400))
        == CGRect(x: 912, y: 600, width: 300, height: 400))

    check("should leave the window where it is when System Settings isn't on screen",
      SetupModel.besideSettings(settings: nil, screen: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        size: CGSize(width: 300, height: 400)) == nil)

    check("should offer a restart on the Screen Recording step", step("screen").needsRestart)

    check("should offer no restart on other steps", !step("accessibility").needsRestart && !step("location").needsRestart)

    check("should read the meter's granted into a microphone grant",
      SetupModel.accessGrants(["microphone": "granted\n"])["meter.microphone"] == .granted)

    check("should read the meter's denied into a denied microphone grant",
      SetupModel.accessGrants(["microphone": "denied"])["meter.microphone"] == .denied)

    check("should leave the microphone open when the meter hasn't been asked",
      SetupModel.accessGrants(["microphone": "undetermined"])["meter.microphone"] == nil)

    check("should leave the microphone open when the meter's answer is empty",
      SetupModel.accessGrants(["microphone": ""])["meter.microphone"] == nil)

    check("should read the agenda's granted into a calendars grant",
      SetupModel.accessGrants(["calendars": "granted"])["agenda.calendars"] == .granted)

    check("should read the agenda's denied into a denied calendars grant",
      SetupModel.accessGrants(["calendars": "denied"])["agenda.calendars"] == .denied)

    check("should leave calendars open when the agenda hasn't been asked",
      SetupModel.accessGrants(["calendars": "undetermined"])["agenda.calendars"] == nil)

    check("should leave calendars open when the agenda's answer is empty",
      SetupModel.accessGrants(["calendars": ""])["agenda.calendars"] == nil)

    check("should grant Bluetooth when blueutil reports the power state",
      SetupModel.accessGrants(["bluetooth": "0\n"])["hammerspoon.bluetooth"] == .granted)

    check("should deny Bluetooth when blueutil's answer is empty",
      SetupModel.accessGrants(["bluetooth": ""])["hammerspoon.bluetooth"] == .denied)

    check("should leave Bluetooth open when it was never asked",
      SetupModel.accessGrants([:])["hammerspoon.bluetooth"] == nil)

    check("should complete the Microphone step when the meter is granted", {
      var progress = SetupProgress()
      progress.grants = ["meter.microphone": .granted]
      return progress.isComplete(step("microphone"))
    }())

    check("should not complete the Microphone step with a tick", {
      var progress = SetupProgress()
      progress.ticked = ["meter.microphone"]
      return !progress.isComplete(step("microphone"))
    }())

    check("should list a step as missing when access it asks for is denied", {
      var progress = SetupProgress()
      progress.grants = ["agenda.calendars": .denied]
      return progress.summary(SetupModel.steps).missing.contains("calendars")
    }())

    check("should ask for access on the steps whose list has no add button",
      ["location", "microphone", "calendars", "bluetooth"].allSatisfy { id in step(id).permissions.allSatisfy { $0.way == .ask } })

    check("should still need a tick for SwipeAeroSpace",
      step("accessibility").permissions.first { $0.key == "swipe.accessibility" }?.way == .tick)

    check("should offer drag where the list has an add button",
      ["screen", "disk"].allSatisfy { id in step(id).permissions.allSatisfy { $0.way == .drag } })

    exit(failed == 0 ? 0 : 1)
  }
}
