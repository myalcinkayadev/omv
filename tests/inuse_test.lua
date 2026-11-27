-- Behavior of the camera and mic in-use dots: what is in use, and what the bar is sent.
-- Run through inuse_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local inuse = require("inuse")

local function joined(arguments)
  return arguments and table.concat(arguments, " ") or ""
end

local NOTHING = { camera = false, mic = false }

check.that("should show the camera dot when any camera reports in use",
  inuse.state({ false, true }, {}, false).camera)
check.that("should hide the camera dot when no camera is in use",
  not inuse.state({ false, false }, {}, false).camera)
check.that("should hide the camera dot when there are no cameras",
  not inuse.state({}, {}, false).camera)
check.that("should hide the camera dot when the cameras can't be read",
  not inuse.state(nil, nil, false).camera)
check.that("should show the mic dot when an input device is running",
  inuse.state({}, { false, true }, false).mic)
check.that("should hide the mic dot when no input device is running",
  not inuse.state({}, { false, false }, false).mic)
check.that("should hide the mic dot when there are no input devices",
  not inuse.state({}, {}, false).mic)
check.that("should read a device that answers nil as not in use",
  not inuse.state({ nil, nil }, { nil }, false).mic)
check.that("should ignore mic use when omv's own meter or dictation is listening",
  not inuse.state({}, { true }, true).mic)
check.that("should still show the camera dot when omv's own mic user is listening",
  inuse.state({ true }, { true }, true).camera)

check.that("should produce no bar change when the state is unchanged",
  inuse.barArguments({ camera = true, mic = false }, { camera = true, mic = false }) == nil)
check.that("should set only the camera item when only the camera changes",
  joined(inuse.barArguments(NOTHING, { camera = true, mic = false })) == "--set camera_in_use drawing=on")
check.that("should set only the mic item when only the mic changes",
  joined(inuse.barArguments({ camera = true, mic = true }, { camera = true, mic = false })) == "--set mic_in_use drawing=off")
check.that("should set both items in one call when both change",
  joined(inuse.barArguments(NOTHING, { camera = true, mic = true })) == "--set camera_in_use drawing=on --set mic_in_use drawing=on")
check.that("should set both items when nothing has been drawn yet",
  joined(inuse.barArguments(nil, NOTHING)) == "--set camera_in_use drawing=off --set mic_in_use drawing=off")

local ownmic = require("ownmic")
local changes = 0
ownmic.onChange = function() changes = changes + 1 end

check.that("should count omv as not listening when none of its mic users has started", not ownmic.any())
ownmic.set("meter", true)
check.that("should count omv as listening when one of its mic users listens", ownmic.any())
ownmic.set("dictation", true)
ownmic.set("meter", false)
check.that("should count omv as listening while another of its mic users still listens", ownmic.any())
ownmic.set("dictation", false)
check.that("should count omv as not listening when all of its mic users stopped", not ownmic.any())
ownmic.set("dictation", false)
check.that("should report a change only when one of its mic users starts or stops", changes == 4)

check.finish()
