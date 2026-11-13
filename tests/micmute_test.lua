-- Behavior of the mic mute decisions: how to mute and unmute, whether the mic counts as
-- muted after a reload, and the bar item. Run through micmute_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local micmute = require("micmute")

check.that("should mute the device when it can mute", micmute.muting({ canMute = true, volume = 70 }).mute == true)
check.that("should set the volume to 0 when the device can't mute", micmute.muting({ canMute = false, volume = 70 }).volume == 0)
check.that("should remember the level when muting by volume", micmute.muting({ canMute = false, volume = 70 }).saved == 70)
check.that("should unmute the device when it can mute", micmute.unmuting({ canMute = true }, nil).mute == false)
check.that("should restore the saved level when unmuting by volume", micmute.unmuting({ canMute = false }, 70).volume == 70)
check.that("should restore 50% when the saved level is missing", micmute.unmuting({ canMute = false }, nil).volume == 50)
check.that("should restore 50% when the saved level is 0", micmute.unmuting({ canMute = false }, 0).volume == 50)

check.that("should count a muted device as muted", micmute.isMuted({ muted = true, volume = 70 }, nil))
check.that("should count a device at 0 with a saved level as muted after a reload",
  micmute.isMuted({ muted = nil, volume = 0 }, { uid = "x", volume = 70 }))
check.that("should not count a device at 0 without a saved level as muted", not micmute.isMuted({ muted = nil, volume = 0 }, nil))

local saved = micmute.decode(micmute.encode({ uid = "BuiltInMicrophoneDevice", volume = 70 }))
check.that("should read back the saved device and level", saved and saved.uid == "BuiltInMicrophoneDevice" and saved.volume == 70)
check.that("should read nothing from an empty file", micmute.decode("") == nil)

local devices = {
  { uid = "caldigit", muted = true, volume = 100 },
  { uid = "rode", muted = nil, volume = 0 },
  { uid = "builtin", muted = false, volume = 49 },
}
local plan = micmute.unmutingAll(devices, { uid = "rode", volume = 30.25 })
local function stepFor(uid) for _, step in ipairs(plan) do if step.uid == uid then return step end end end
check.that("should unmute every muted input when unmuting, so none is left silent", stepFor("caldigit") and stepFor("caldigit").mute == false)
check.that("should restore the saved level of the input muted by volume", stepFor("rode") and stepFor("rode").volume == 30.25)
check.that("should leave an input that isn't muted alone", stepFor("builtin") == nil)
check.that("should restore 50% to an input at 0 by volume when its saved level is missing",
  micmute.unmutingAll({ { uid = "rode", muted = nil, volume = 0 } }, { uid = "rode", volume = 0 })[1].volume == 50)
check.that("should leave an input at 0 alone when nothing was saved for it",
  #micmute.unmutingAll({ { uid = "zoom", muted = nil, volume = 0 } }, nil) == 0)

-- Review findings.
local twoByVolume = micmute.unmutingAll({ { uid = "a", muted = nil, volume = 0 }, { uid = "c", muted = nil, volume = 0 } },
  { uid = "a", volume = 70 }, "c")
local function stepIn(steps, uid) for _, step in ipairs(steps) do if step.uid == uid then return step end end end
check.that("should restore the default input to 50% when it was muted by volume without a saved level",
  stepIn(twoByVolume, "c") and stepIn(twoByVolume, "c").volume == 50)
check.that("should still restore the saved input when the default was muted by volume too", stepIn(twoByVolume, "a").volume == 70)
local _, keep = micmute.unmutingAll({ { uid = "builtin", muted = true, volume = 49 } }, { uid = "a", volume = 70 }, "builtin")
check.that("should keep the saved level when its mic isn't connected", keep == true)
local _, kept = micmute.unmutingAll({ { uid = "a", muted = nil, volume = 0 } }, { uid = "a", volume = 70 }, "a")
check.that("should drop the saved level once it's restored", kept == false)

local back = micmute.restoreSaved({ { uid = "a", muted = nil, volume = 0 } }, { uid = "a", volume = 70 })
check.that("should restore a returning mic's saved level when it's back at 0", back and back.uid == "a" and back.volume == 70)
local moved, drop = micmute.restoreSaved({ { uid = "a", muted = nil, volume = 40 } }, { uid = "a", volume = 70 })
check.that("should drop the saved level when the returning mic isn't at 0", moved == nil and drop == true)
local waiting, dropWaiting = micmute.restoreSaved({ { uid = "builtin", muted = false, volume = 49 } }, { uid = "a", volume = 70 })
check.that("should wait when the saved mic is still missing", waiting == nil and dropWaiting == false)

check.that("should count muting as done when the mic reads muted", micmute.worked({ muted = true, volume = 70 }))
check.that("should count muting as done when the mic is at 0", micmute.worked({ muted = nil, volume = 0 }))
check.that("should count muting as failed when the mic is neither muted nor at 0", not micmute.worked({ muted = nil, volume = nil }))

check.that("should draw the bar item while muted", micmute.barProperties(true)[1] == "drawing=on")
check.that("should hide the bar item when not muted", micmute.barProperties(false)[1] == "drawing=off")

check.finish()
