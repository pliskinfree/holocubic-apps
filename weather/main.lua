local previous = rawget(_G, "WEATHER_APP")
if previous and previous.stop then
  pcall(function()
    previous.stop("reload")
  end)
end

local APP_DIR = "/sd/apps/weather"

-- 从 app 目录加载子模块，保持 SD 部署路径和 app.info 入口一致。
local function load_app_module(name)
  return dofile(APP_DIR .. "/" .. name .. ".lua")
end

local Config = load_app_module("config")
local WeatherTime = load_app_module("time")
local WeatherApi = load_app_module("api")
local WeatherUi = load_app_module("ui")

local cfg = Config.load()
local APP = {
  running = true,
  timers = {},
  ui = {},
  state = {
    valid = false,
    temp = nil,
    humidity = nil,
    wind_speed = nil,
    precip_x10 = nil,
    text = nil,
    code = nil,
    obs_time = nil,
    last_http_code = nil,
    last_error = nil,
    last_update_ms = 0,
    request_inflight = false,
    ntp_enabled = false,
    clock_valid = false,
  },
}

for k, v in pairs(cfg) do
  APP[k] = v
end

local clock = WeatherTime.new(APP)
local api = WeatherApi.new(APP)
local ui = WeatherUi.new(APP, clock)

-- 停止并注销一个定时器，重复调用也安全。
local function stop_timer(timer)
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
  end)
  pcall(function()
    timer:unregister()
  end)
end

-- 停止所有周期任务，退出或热重载时统一回收。
local function stop_timers()
  for _, timer in pairs(APP.timers) do
    stop_timer(timer)
  end
  APP.timers = {}
end

-- 如果宿主已经要求退出，主动触发 stop，避免后台定时器继续运行。
local function maybe_stop_for_exit()
  if app and app.exiting then
    local ok, exiting = pcall(function()
      return app.exiting()
    end)
    if ok and exiting then
      APP.stop("app exiting")
      return true
    end
  end
  return false
end

-- 启动时钟和天气刷新定时器，定时器引用都放进 APP.timers 方便回收。
local function start_timers()
  if not tmr or not tmr.create then
    return
  end

  APP.timers.clock = tmr.create()
  APP.timers.clock:alarm(1000, tmr.ALARM_AUTO, function()
    if not APP.running or maybe_stop_for_exit() then
      return
    end
    ui:render_clock()
  end)

  APP.timers.fetch = tmr.create()
  APP.timers.fetch:alarm(APP.WEATHER_FETCH_MS, tmr.ALARM_AUTO, function()
    if not APP.running or maybe_stop_for_exit() then
      return
    end
    api:request_now(function()
      ui:render_weather()
    end)
  end)
end

-- App 生命周期出口：停止网络回调后续渲染、释放定时器并销毁页面。
function APP.stop(reason)
  if not APP.running then
    return
  end
  APP.running = false
  APP.state.request_inflight = false
  stop_timers()
  ui:destroy()
  print("[weather] stop", tostring(reason or ""))
  if rawget(_G, "WEATHER_APP") == APP then
    _G.WEATHER_APP = nil
  end
end

WEATHER_APP = APP

if not ui:available() then
  print("[weather] required ui api missing")
  APP.stop("ui missing")
  return
end

clock:init()
ui:init()
ui:render_clock()
ui:render_weather()
api:request_now(function()
  ui:render_weather()
end)
start_timers()
