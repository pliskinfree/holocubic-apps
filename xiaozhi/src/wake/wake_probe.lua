local RESULT_PATH = "/sd/wake_probe_result.txt"
local MODULE_PATH = "/sd/apps/xiaozhi/wake.so"

local lines = {}

local function log(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  local line = table.concat(parts, " ")
  print(line)
  lines[#lines + 1] = line
end

local function write_result()
  local fd, err = file.open(RESULT_PATH, "w")
  if not fd then
    print("[wake-probe] result open failed", tostring(err))
    return
  end
  fd:write(table.concat(lines, "\n"))
  fd:write("\n")
  fd:close()
end

local function dump_table(prefix, t)
  if type(t) ~= "table" then
    log(prefix, tostring(t))
    return
  end
  for k, v in pairs(t) do
    log(prefix, tostring(k) .. "=" .. tostring(v))
  end
end

log("[wake-probe] begin")
log("[wake-probe] require", MODULE_PATH)
local ok, wake = pcall(require, MODULE_PATH)
if not ok then
  log("[wake-probe] require failed", tostring(wake))
  write_result()
  return
end

log("[wake-probe] loaded", tostring(wake), "version", tostring(wake.VERSION))
log("[wake-probe] model", tostring(wake.MODEL), "word", tostring(wake.WORD))
dump_table("[wake-probe][info0]", wake.info())

local started, start_err = wake.start()
log("[wake-probe] start", tostring(started), tostring(start_err))
dump_table("[wake-probe][info1]", wake.info())

local self_ok, self_result = pcall(function()
  return wake.selftest(4)
end)
log("[wake-probe] selftest pcall", tostring(self_ok))
dump_table("[wake-probe][selftest]", self_result)

local stopped, stop_err = wake.stop()
log("[wake-probe] stop", tostring(stopped), tostring(stop_err))
dump_table("[wake-probe][info2]", wake.info())
log("[wake-probe] done")
write_result()
