-- The audio device watcher, shared. hs.audiodevice.watcher takes one callback at a time, and
-- both the Sound card and mic mute need it, so each registers here by name. It runs while
-- anything is registered, and stops when nothing is.

local audiowatch = {}

local watchers = {}

local function onEvent(event)
  for _, onChange in pairs(watchers) do onChange(event) end
end

-- onChange gets the watcher's event, such as "dIn " when the default input changes.
function audiowatch.watch(name, onChange)
  watchers[name] = onChange
  hs.audiodevice.watcher.setCallback(onEvent)
  if not hs.audiodevice.watcher.isRunning() then hs.audiodevice.watcher.start() end
end

function audiowatch.unwatch(name)
  watchers[name] = nil
  if next(watchers) == nil and hs.audiodevice.watcher.isRunning() then hs.audiodevice.watcher.stop() end
end

return audiowatch
