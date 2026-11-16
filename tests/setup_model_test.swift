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

    check("should place the helper to the right of System Settings when it fits",
      SetupModel.helperFrame(settings: CGRect(x: 100, y: 100, width: 800, height: 600),
        screen: CGRect(x: 0, y: 0, width: 1600, height: 1000), size: CGSize(width: 300, height: 400))
        == CGRect(x: 912, y: 100, width: 300, height: 400))

    check("should place the helper to the left when the right side has no room",
      SetupModel.helperFrame(settings: CGRect(x: 700, y: 100, width: 800, height: 600),
        screen: CGRect(x: 0, y: 0, width: 1600, height: 1000), size: CGSize(width: 300, height: 400))
        == CGRect(x: 388, y: 100, width: 300, height: 400))

    check("should hide the helper when System Settings isn't on screen",
      SetupModel.helperFrame(settings: nil, screen: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        size: CGSize(width: 300, height: 400)) == nil)

    check("should offer a restart on the Screen Recording step", step("screen").needsRestart)

    check("should offer no restart on other steps", !step("accessibility").needsRestart && !step("location").needsRestart)

    exit(failed == 0 ? 0 : 1)
  }
}
