-- Behavior of the Sound card. Run through sound_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local sound = require("sound")

local function state(overrides)
  local base = {
    outputs = {
      { uid = "BuiltInSpeakerDevice", name = "MacBook Pro Speakers", transport = "Built-in", current = false },
      { uid = "aa-bb", name = "Mehmet's AirPods Pro", transport = "Bluetooth", current = true },
      { uid = "dell", name = "DELL U2723QE", transport = "DisplayPort", current = false },
      { uid = "zoom", name = "ZoomAudioDevice", transport = "Virtual", current = false },
    },
    inputs = {
      { uid = "BuiltInMicrophoneDevice", name = "MacBook Pro Microphone", transport = "Built-in", current = true },
      { uid = "zoom-in", name = "ZoomAudioDevice", transport = "Virtual", current = false },
    },
    outputVolume = 42.6,
    inputVolume = 80,
    muted = false,
  }
  for key, value in pairs(overrides or {}) do base[key] = value end
  return base
end

local page = sound.html(state())
local visible = check.visible(page)

check.that("should show the current output's name uppercased when it opens", check.contains(visible, "MEHMET'S AIRPODS PRO"))
check.that("should highlight the current output row when it opens", check.contains(page, 'class="dev current" data-kind="output" data-id="aa-bb"'))
check.that("should highlight the current input row when it opens",
  check.contains(page, 'class="dev current" data-kind="input" data-id="BuiltInMicrophoneDevice"'))
check.that("should highlight only one row per section when it opens", select(2, page:gsub('class="dev current"', "")) == 2)
check.that("should leave out a virtual output when it is not in use", not check.contains(page, 'data-id="zoom"'))
check.that("should leave out a virtual input when it is not in use", not check.contains(page, 'data-id="zoom-in"'))
check.that("should keep a virtual output when it is in use",
  check.contains(sound.html(state({ outputs = { { uid = "zoom", name = "ZoomAudioDevice", transport = "Virtual", current = true } } })), 'data-id="zoom"'))
check.that("should round the output volume when it has a fraction", check.contains(visible, "43%"))
check.that("should show the input volume when it opens", check.contains(visible, "80%"))
check.that("should set the output slider to the volume when it opens", check.contains(page, 'class=out value="43"'))
check.that("should show a dash when the output takes no volume", check.contains(check.visible(sound.html(state({ outputVolume = false }))), "—"))
check.that("should disable the output slider when the output takes no volume",
  check.contains(sound.html(state({ outputVolume = false })), "class=out value=\"0\" disabled"))
check.that("should show the mute switch on when sound is on", check.contains(page, 'class="switch on"'))
check.that("should show the mute switch off when muted", check.contains(sound.html(state({ muted = true })), 'class="switch"'))
check.that("should have a level meter for the input", check.contains(page, "class=meter"))
check.that("should list no Sources section", not check.contains(visible, "SOURCES"))
check.that("should say so when there are no outputs", check.contains(check.visible(sound.html(state({ outputs = {} }))), "No output devices"))

local tricky = sound.html(state({ outputs = { { uid = 'x"<y', name = "Mehmet's <AirPods> & co", transport = "Bluetooth", current = true } } }))
check.that("should escape markup in a device name", check.contains(tricky, "Mehmet's &lt;AirPods&gt; &amp; co"))
check.that("should escape markup in a device id", check.contains(tricky, 'data-id="x&quot;&lt;y"'))

check.that("should grow taller when there are more devices",
  sound.height(state()) > sound.height(state({ outputs = { { uid = "a", name = "a", transport = "Built-in", current = true } } })))

check.that("should show headphones for AirPods", sound.icon({ name = "Mehmet's AirPods Pro", transport = "Bluetooth" }) == "󰋋")
check.that("should show a monitor for a display", sound.icon({ name = "DELL U2723QE", transport = "DisplayPort" }) == "󰍹")
check.that("should show a speaker for built-in speakers", sound.icon({ name = "MacBook Pro Speakers", transport = "Built-in" }) == "󰓃")
check.that("should show AirPlay for an AirPlay device", sound.icon({ name = "Living Room", transport = "AirPlay" }) == "󰄘")

-- The open card follows the volume keys and mute without being redrawn.
local live = sound.update(state({ outputVolume = 40, inputVolume = 25, muted = true }))
check.that("should update the output volume in place", check.contains(live, '"output":40'))
check.that("should update the input volume in place", check.contains(live, '"input":25'))
check.that("should update the mute switch in place", check.contains(live, '"muted":true'))
check.that("should send no volume for a device that takes none", check.contains(sound.update(state({ outputVolume = false })), '"output":null'))
local before = state()
local plugged = state({ outputs = { before.outputs[1], { uid = "airpods", name = "AirPods", transport = "Bluetooth" } } })
check.that("should redraw the card when a device is added or removed", not sound.sameDevices(before, plugged))
local switched = state()
switched.outputs[1].current = false
check.that("should keep the card when only the volume or the current device changes", sound.sameDevices(before, state()))

check.finish()
