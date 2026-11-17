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
    check("should put Welcome, then Install, first and Done last when listing the screens",
      Array(SetupModel.screens.prefix(2)) == ["welcome", "install"] && SetupModel.screens.last == "done")

    check("should give each permission step a screen between Install and Done",
      SetupModel.screens == ["welcome", "install"] + SetupModel.steps.map(\.id) + ["done"])

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

    check("should mark no step failed when the install exits zero", {
      var run = InstallRun()
      run.consume("omv-step: taps start")
      run.finish(status: 0)
      return run.isFinished && run.failed == nil
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

    check("should keep a line's character whole when a chunk splits it", {
      var lines = LineSplitter()
      let beer = Array("🍺 done\n".utf8)
      return lines.feed(Data(beer[..<2])).isEmpty && lines.feed(Data(beer[2...])) == ["🍺 done"]
    }())

    check("should hand over the last line when output ends without a newline", {
      var lines = LineSplitter()
      _ = lines.feed(Data("first\nlast".utf8))
      return lines.finish() == ["last"]
    }())

    check("should hand over nothing at the end when the last line was complete", {
      var lines = LineSplitter()
      _ = lines.feed(Data("only\n".utf8))
      return lines.finish().isEmpty
    }())

    check("should escape quotes and backslashes when quoting a path for Lua",
      SetupModel.luaQuoted("/Users/a \"b\"\\c") == "\"/Users/a \\\"b\\\"\\\\c\"")

    check("should offer Continue again when a request ends with no answer", {
      var progress = SetupProgress()
      progress.asking = ["meter.microphone"]
      progress.requestEnded("meter.microphone")
      return progress.asking.isEmpty
    }())

    check("should stop asking when an answer arrives", {
      var progress = SetupProgress()
      progress.asking = ["agenda.calendars"]
      progress.take(["agenda.calendars": .denied])
      return progress.asking.isEmpty && progress.grants["agenda.calendars"] == .denied
    }())

    check("should keep asking while no answer has arrived", {
      var progress = SetupProgress()
      progress.asking = ["hammerspoon.bluetooth"]
      progress.take([:])
      return progress.asking == ["hammerspoon.bluetooth"]
    }())

    check("should mark only Accessibility as needed when listing the steps",
      SetupModel.steps.filter(\.needed).map(\.id) == ["accessibility"])

    check("should give every permission a role when listing the steps",
      SetupModel.steps.allSatisfy { $0.permissions.allSatisfy { !$0.role.isEmpty } })

    check("should mention the Disk card when describing Full Disk Access", step("disk").purpose.contains("Disk card"))

    check("should show tiling first on the Accessibility step", step("accessibility").parts.first?.app == "AeroSpace")

    check("should show what every step turns on", SetupModel.steps.allSatisfy { !$0.parts.isEmpty })

    check("should name a preview image that exists for every image a step shows", {
      let repo = ProcessInfo.processInfo.environment["OMV_REPO"] ?? ""
      let images = SetupModel.steps.flatMap { $0.parts.compactMap(\.image) }
      return !images.isEmpty && images.allSatisfy { image in
        SetupModel.previewPath(repo: repo, image: image).map { FileManager.default.fileExists(atPath: $0) } ?? false
      }
    }())

    check("should give no preview path when setup runs without omv's folder",
      SetupModel.previewPath(repo: nil, image: "accessibility-1") == nil)

    check("should title the button before macOS's prompt Continue, never Allow", SetupModel.askButton == "Continue")

    check("should leave the window in place when a 13-inch screen has no room beside System Settings",
      SetupModel.besideSettings(settings: CGRect(x: 380, y: 40, width: 715, height: 640),
        screen: CGRect(x: 0, y: 0, width: 1470, height: 920), size: SetupModel.windowSize) == nil)

    // A 13-inch screen with System Settings in the middle: the full window fits on neither side.
    let small = CGRect(x: 0, y: 0, width: 1470, height: 920)
    let settingsMiddle = CGRect(x: 380, y: 40, width: 715, height: 640)

    check("should collapse to the app cards when a drag step's full window has no room beside System Settings", {
      let place = SetupModel.placement(step: step("accessibility"), complete: false, settings: settingsMiddle, screen: small)
      return place.layout == .compact && place.frame?.minX == settingsMiddle.maxX + 12
    }())

    check("should keep the full window when it fits beside System Settings", {
      let settings = CGRect(x: 0, y: 40, width: 715, height: 640)
      let place = SetupModel.placement(step: step("accessibility"), complete: false, settings: settings,
        screen: CGRect(x: 0, y: 0, width: 2560, height: 1400))
      return place.layout == .full && place.frame?.minX == settings.maxX + 12
    }())

    check("should place the compact panel left of System Settings when only the left has room", {
      let settings = CGRect(x: 740, y: 40, width: 715, height: 640)
      let place = SetupModel.placement(step: step("disk"), complete: false, settings: settings, screen: small)
      return place.layout == .compact && place.frame?.maxX == settings.minX - 12
    }())

    check("should keep the full window when System Settings isn't on screen", {
      let place = SetupModel.placement(step: step("accessibility"), complete: false, settings: nil, screen: small)
      return place.layout == .full && place.frame == nil
    }())

    check("should return to the full window once the step is complete",
      SetupModel.placement(step: step("accessibility"), complete: true, settings: settingsMiddle, screen: small).layout == .full)

    check("should keep the full window on an ask step, which has no list to drag into",
      SetupModel.placement(step: step("location"), complete: false, settings: settingsMiddle, screen: small).layout == .full)

    check("should leave the window in place when even the compact panel has no room", {
      let settings = CGRect(x: 200, y: 40, width: 1100, height: 640)
      let place = SetupModel.placement(step: step("accessibility"), complete: false, settings: settings, screen: small)
      return place.layout == .full && place.frame == nil
    }())

    check("should size the compact panel to fit every app card", {
      SetupModel.compactSize(apps: 3).height > SetupModel.compactSize(apps: 1).height
        && SetupModel.compactSize(apps: 3).height <= small.height
    }())

    exit(failed == 0 ? 0 : 1)
  }
}
