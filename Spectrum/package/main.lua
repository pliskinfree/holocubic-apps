local prev = rawget(_G, "RING_BAR_SPEC_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop()
  end)
end

RING_BAR_SPEC_APP = {}
RING_BAR_SPEC_APP.VERSION = "2026-05-10-spectrum-v20-i2s-np-fft-modules"

local APP_STATE = RING_BAR_SPEC_APP
local MODULES = {}

local function app_dir()
  local cur = app and app.current and app.current() or nil
  local entry = cur and cur.entry or "/sd/spectrum/main.lua"
  local dir = entry:match("^(.*)/[^/]*$")
  if not dir or dir == "" then
    error("cannot resolve app dir")
  end
  return dir
end

local APP_DIR = app_dir()

local function load_local(name, ...)
  if type(name) ~= "string" or name:find("..", 1, true) or name:sub(1, 1) == "/" then
    error("bad module name: " .. tostring(name))
  end

  if MODULES[name] ~= nil then
    return MODULES[name]
  end

  local path = APP_DIR .. "/" .. name
  local src = file.getcontents(path)
  if not src then
    error("read lua failed: " .. path)
  end

  local fn, err = load(src, "@" .. path, "t", _ENV)
  if not fn then
    error("compile lua failed: " .. path .. ": " .. tostring(err))
  end

  local ret = fn(...)
  if ret == nil then
    ret = true
  end

  MODULES[name] = ret
  return ret
end

local audio = load_local("fft.lua", APP_STATE)
APP_STATE.audio = audio
APP_STATE.ui = load_local("ui.lua", APP_STATE, audio)

return APP_STATE