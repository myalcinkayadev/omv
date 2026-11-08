-- The Sound card opened from the bar's volume item: a mute switch, the output volume and
-- devices, then the input volume, a live mic level meter and the input devices.
-- Up and Down move through the devices, Enter or a click picks one, Left and Right change
-- the output volume, M mutes, Escape closes.
-- The page sends { type, id }: output / input (id = uid), volume / inputVolume (id = 0-100),
-- mute, close. init.lua feeds the meter by calling omvLevel(0..1).
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local sound = {}

local DASH = "—"
local STEP = 5

sound.WIDTH = 420

-- Card height: the padding and header, each section's label and slider, the meter, each row.
local FRAME_HEIGHT = 44 + 66
local SECTION_HEIGHT = 74
local METER_HEIGHT = 16
local ROW_HEIGHT = 40

local HEADPHONE_NAMES = { "airpods", "headphone", "headset", "beats", "buds" }

-- Headphones by name first, since AirPods and a Bluetooth speaker share a transport.
function sound.icon(device)
  local name = device.name:lower()
  for _, word in ipairs(HEADPHONE_NAMES) do
    if name:find(word, 1, true) then return "󰋋" end
  end
  local transport = device.transport or ""
  if transport == "HDMI" or transport == "DisplayPort" or transport == "Thunderbolt" then return "󰍹" end
  if transport == "AirPlay" then return "󰄘" end
  if transport:find("Bluetooth", 1, true) then return "󰋋" end
  return "󰓃"
end

-- Virtual devices, such as the ones Zoom and Teams add, are left out unless in use.
local function shown(devices)
  local result = {}
  for _, device in ipairs(devices) do
    if device.transport ~= "Virtual" or device.current then result[#result + 1] = device end
  end
  return result
end

local function percent(volume)
  if not volume then return nil end
  return math.floor(volume + 0.5)
end

local STYLE = [[
  body { padding: 22px 24px; display: block; }
  .head { display: flex; align-items: center; gap: 16px; padding-bottom: 14px; border-bottom: 1px solid #2a2a2a; }
  .head .icon { font-size: 26px; width: 28px; text-align: center; }
  .head .title { font-size: 18px; }
  .head .sub { color: #7a7a7a; letter-spacing: 2px; font-size: 13px; margin-top: 4px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 250px; }
  .switch { margin-left: auto; width: 46px; height: 26px; background: #2a2a2a; border-radius: 3px; position: relative; cursor: default; }
  .switch i { position: absolute; top: 4px; left: 4px; width: 18px; height: 18px; background: #7a7a7a; transition: left 0.1s; }
  .switch.on i { left: 24px; background: #fff; }
  .label { display: flex; justify-content: space-between; color: #7a7a7a; font-size: 13px; letter-spacing: 1px; margin: 16px 0 10px; }
  .section + .section { border-top: 1px solid #2a2a2a; }
  input[type=range] { -webkit-appearance: none; width: 100%; height: 4px; background: #2a2a2a; border-radius: 2px; margin: 4px 0 10px; }
  input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #fff; }
  input[type=range]:disabled::-webkit-slider-thumb { background: #4a4a4a; }
  .meter { height: 6px; background: #2a2a2a; margin: 0 0 10px; }
  .meter i { display: block; height: 6px; width: 0; background: #fff; transition: width 0.08s linear; }
  .dev { display: flex; align-items: center; height: 40px; padding: 0 12px; color: #d0d0d0; cursor: default; }
  .dev .icon { width: 28px; font-size: 16px; }
  .dev .name { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .dev.current { background: #2a2a2a; color: #fff; font-weight: bold; }
  .dev.selected { outline: 1px solid #8d8d8d; }
  .none { color: #7a7a7a; padding: 8px 12px; display: block; }
]]

local SCRIPT = [==[
  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id === undefined ? "" : String(id) });
  const rows = Array.from(document.querySelectorAll(".dev"));
  const out = document.querySelector(".out"), input = document.querySelector(".in");
  let selected = -1;
  const draw = () => rows.forEach((row, index) => row.classList.toggle("selected", index === selected));
  const showLevel = (slider, value) => { slider.closest(".section").querySelector(".pct").textContent = value + "%"; };
  const setOut = (value) => {
    if (out.disabled) return;
    out.value = Math.max(0, Math.min(100, value));
    showLevel(out, out.value);
    send("volume", out.value);
  };
  [[out, "volume"], [input, "inputVolume"]].forEach(([slider, type]) => {
    slider.addEventListener("input", () => showLevel(slider, slider.value));
    slider.addEventListener("change", () => send(type, slider.value));
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") return send("close");
    if (event.key === "ArrowDown") selected = (selected + 1) % rows.length;
    else if (event.key === "ArrowUp") selected = (selected - 1 + rows.length) % rows.length;
    else if (event.key === "Enter" && rows[selected]) return send(rows[selected].dataset.kind, rows[selected].dataset.id);
    else if (event.key === "ArrowRight") return setOut(Number(out.value) + STEP);
    else if (event.key === "ArrowLeft") return setOut(Number(out.value) - STEP);
    else if (event.key === "m" || event.key === "M") return send("mute");
    else return;
    event.preventDefault();
    draw();
  });
  rows.forEach((row) => row.addEventListener("click", () => send(row.dataset.kind, row.dataset.id)));
  document.querySelector(".switch").addEventListener("click", () => send("mute"));
  const meter = document.querySelector(".meter i");
  window.omvLevel = (level) => { meter.style.width = Math.round(Math.max(0, Math.min(1, level)) * 100) + "%"; };
]==]

local function deviceRows(devices, kind, icon, empty)
  if #devices == 0 then return "<div class=none>" .. empty .. "</div>" end
  local rows = {}
  for _, device in ipairs(devices) do
    rows[#rows + 1] = '<div class="dev' .. (device.current and " current" or "") .. '" data-kind="' .. kind
      .. '" data-id="' .. card.escape(device.uid) .. '"><span class=icon>' .. (icon or sound.icon(device))
      .. "</span><span class=name>" .. card.escape(device.name) .. "</span></div>"
  end
  return table.concat(rows)
end

local function slider(class, volume)
  local level = percent(volume)
  return "<input type=range min=0 max=100 class=" .. class .. ' value="' .. (level or 0) .. '"' .. (level and "" or " disabled") .. ">"
end

local function sectionHead(name, volume)
  local level = percent(volume)
  return "<div class=label><span>" .. name .. "</span><span class=pct>" .. (level and (level .. "%") or DASH) .. "</span></div>"
end

local function currentName(devices)
  for _, device in ipairs(devices) do
    if device.current then return device.name end
  end
  return DASH
end

-- state = { outputs, inputs = { { uid, name, transport, current } }, outputVolume, inputVolume, muted }
-- A volume of nil or false means the device takes none.
function sound.html(state)
  local outputs, inputs = shown(state.outputs), shown(state.inputs)
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. STYLE .. "</style><body>"
    .. "<div class=head><div class=icon>" .. (state.muted and "󰖁" or "󰕾") .. "</div>"
    .. "<div><div class=title>Audio</div><div class=sub>" .. card.escape(currentName(outputs):upper()) .. "</div></div>"
    .. '<div class="switch' .. (state.muted and "" or " on") .. '"><i></i></div></div>'
    .. "<div class=section>" .. sectionHead("OUTPUT", state.outputVolume) .. slider("out", state.outputVolume)
    .. deviceRows(outputs, "output", nil, "No output devices") .. "</div>"
    .. "<div class=section>" .. sectionHead("INPUT", state.inputVolume) .. slider("in", state.inputVolume)
    .. "<div class=meter><i></i></div>"
    .. deviceRows(inputs, "input", "󰍬", "No input devices") .. "</div>"
    .. "<script>const STEP = " .. STEP .. ";" .. SCRIPT .. "</script></body>"
end

function sound.height(state)
  local rows = math.max(1, #shown(state.outputs)) + math.max(1, #shown(state.inputs))
  return FRAME_HEIGHT + 2 * SECTION_HEIGHT + METER_HEIGHT + rows * ROW_HEIGHT
end

return sound
