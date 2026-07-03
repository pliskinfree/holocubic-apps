local WAKE_PROBE = {}

WAKE_PROBE.MODULE_PATH = "/sd/apps/xiaozhi/wake.so"

local function dump_table(prefix, t)
  if type(t) ~= "table" then
    print(prefix, tostring(t))
    return
  end

  for k, v in pairs(t) do
    print(prefix, tostring(k) .. "=" .. tostring(v))
  end
end

print("[wake-probe] require", WAKE_PROBE.MODULE_PATH)
local ok, wake = pcall(require, WAKE_PROBE.MODULE_PATH)
if not ok then
  print("[wake-probe] require failed", tostring(wake))
  return
end

print("[wake-probe] model", tostring(wake.MODEL), "word", tostring(wake.WORD))
dump_table("[wake-probe][info]", wake.info())

local started, err = wake.start()
print("[wake-probe] start", tostring(started), tostring(err))
dump_table("[wake-probe][info_started]", wake.info())

local result = wake.selftest()
dump_table("[wake-probe][selftest]", result)

local stopped, stop_err = wake.stop()
print("[wake-probe] stop", tostring(stopped), tostring(stop_err))
