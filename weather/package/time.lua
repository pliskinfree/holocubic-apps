local M = {}
M.__index = M

-- 安全取得毫秒时间，用于限制 NTP 重试频率。
local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and type(value) == "number" then
      return value
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(function()
      return tmr.now()
    end)
    if ok and type(value) == "number" then
      return math.floor(value / 1000)
    end
  end
  return 0
end

-- 把数字补成两位，用于时间和日期显示。
local function two(n)
  n = tonumber(n) or 0
  if n < 10 then
    return "0" .. tostring(n)
  end
  return tostring(n)
end

-- 创建时间服务实例，状态保存在 app.state 中便于 UI 显示。
function M.new(app)
  return setmetatable({
    app = app,
    last_ntp_retry_ms = 0,
  }, M)
end

-- 设置 POSIX TZ；底层 time.settimezone 会走 tzset，可支持冬夏令时规则。
function M:set_timezone()
  local app = self.app
  if not time or not time.settimezone then
    return false
  end
  local ok, err = pcall(function()
    time.settimezone(app.TIMEZONE)
  end)
  if not ok then
    print("[weather.time] settimezone failed", tostring(err))
  end
  return ok
end

-- 按需启动 NTP，对时失败不会阻塞页面渲染。
function M:sync(force)
  local app = self.app
  if not time then
    return
  end

  local now = now_ms()
  if not force and (now - self.last_ntp_retry_ms) < app.TIME_SYNC_RETRY_MS then
    return
  end
  self.last_ntp_retry_ms = now

  self:set_timezone()

  if not time.initntp then
    return
  end
  local ok, err = pcall(function()
    time.initntp(app.NTP_SERVER)
  end)
  if ok then
    app.state.ntp_enabled = true
  else
    print("[weather.time] initntp failed", tostring(err))
  end
end

-- 初始化时区和 NTP 状态；时区必须先设置，后续 getlocal 才能处理 DST。
function M:init()
  local app = self.app
  self:set_timezone()

  if not time or not time.ntpenabled then
    return
  end
  local ok, enabled = pcall(function()
    return time.ntpenabled()
  end)
  if ok then
    app.state.ntp_enabled = enabled and true or false
    if not enabled then
      self:sync(true)
    end
  else
    print("[weather.time] ntp check failed", tostring(enabled))
  end
end

-- 从 time.getlocal 取得本地时间，这是支持 POSIX TZ 和冬夏令时的主路径。
function M:tm_from_time()
  if not time or not time.getlocal then
    return nil
  end
  local ok, t = pcall(function()
    return time.getlocal()
  end)
  if ok and type(t) == "table" and t.year and t.mon and t.day and t.year >= 2024 then
    return {
      year = t.year,
      mon = t.mon,
      day = t.day,
      hour = t.hour or 0,
      min = t.min or 0,
      sec = t.sec or 0,
    }
  end
  return nil
end

-- PC 模拟或兼容环境下用 os.date 兜底，真实设备优先不用它。
function M:tm_from_os()
  if not os or not os.date then
    return nil
  end
  local ok, t = pcall(os.date, "*t")
  if ok and type(t) == "table" and t.year and t.mon and t.day then
    return {
      year = t.year,
      mon = t.mon,
      day = t.day,
      hour = t.hour or 0,
      min = t.min or 0,
      sec = t.sec or 0,
    }
  end
  return nil
end

-- 无有效时间源时用开机时长兜底，保证 UI 不出现空白。
function M:tm_from_uptime()
  local total_sec = math.floor(now_ms() / 1000)
  return {
    hour = math.floor(total_sec / 3600) % 24,
    min = math.floor(total_sec / 60) % 60,
    sec = total_sec % 60,
  }
end

-- 统一本地时间入口，并在时间无效时触发一次异步对时。
function M:local_tm()
  local app = self.app
  local t = self:tm_from_time()
  if t then
    app.state.clock_valid = true
    return t
  end

  t = self:tm_from_os()
  if t then
    app.state.clock_valid = true
    return t
  end

  app.state.clock_valid = false
  self:sync(false)
  return self:tm_from_uptime()
end

-- 格式化主时钟文本。
function M:clock_text()
  local t = self:local_tm()
  return string.format("%s:%s", two(t.hour), two(t.min))
end

-- 格式化日期文本，时间未同步时显示占位。
function M:date_text()
  local t = self:local_tm()
  if t.year and t.mon and t.day then
    return string.format("%d/%d/%04d", t.day, t.mon, t.year)
  end
  return "--/--/----"
end

-- 根据本地小时判断夜间图标或背景使用场景。
function M:is_night()
  local t = self:local_tm()
  local hour = t.hour or 12
  return hour >= 19 or hour < 6
end

return M
