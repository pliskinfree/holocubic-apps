local M = {}

M.VERSION = "2026-06-28-weather-modular-v1"
M.APP_DIR = "/sd/apps/weather"
M.SETTINGS_PATH = "/sd/apps/settings.json"
M.SCREEN_W = 320
M.SCREEN_H = 240
M.WEATHER_HOST = "https://r77qqrtvyu.re.qweatherapi.com"
M.WEATHER_KEY = "3f5e087b49904de8a44961597d4263db"
M.WEATHER_LOCATION = "101210401"
M.WEATHER_FETCH_MS = 60000
M.TIME_SYNC_RETRY_MS = 30000
M.TIMEZONE = "CST-8"
M.NTP_SERVER = "pool.ntp.org"
M.CITY_NAME = "Ningbo"
M.MAIN_ICON_DIR = M.APP_DIR .. "/128"
M.MINI_ICON_DIR = M.APP_DIR .. "/ui25"

-- 返回字符串或默认值，避免配置字段为空时把运行参数覆盖坏。
local function text_or(value, fallback)
  if value == nil then
    return fallback or ""
  end
  local text = tostring(value)
  if text == "" then
    return fallback or ""
  end
  return text
end

-- 去掉首尾空白，HTML 页面写入的文本框值统一先清理。
local function trim(text)
  text = text_or(text, "")
  return text:match("^%s*(.-)%s*$") or ""
end

-- 浅拷贝默认配置，避免 load 多次时污染模块默认值。
local function copy_defaults()
  local cfg = {}
  for k, v in pairs(M) do
    if type(v) ~= "function" then
      cfg[k] = v
    end
  end
  return cfg
end

-- 从 SD 读取完整文本配置，设备没有保存文件时安静回退默认值。
local function read_text(path)
  if not file then
    return nil
  end
  if file.getcontents then
    local ok, raw = pcall(function()
      return file.getcontents(path)
    end)
    if ok and type(raw) == "string" then
      return raw
    end
  end
  if not file.open then
    return nil
  end
  local fd = file.open(path, "r")
  if not fd then
    return nil
  end
  local chunks = {}
  while true do
    local part = fd:read(512)
    if not part or part == "" then
      break
    end
    chunks[#chunks + 1] = part
  end
  fd:close()
  return table.concat(chunks)
end

-- 解码 JSON，优先兼容现有 json 模块，再回退 NodeMCU 风格 sjson。
local function decode_json(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  if json and json.decode then
    local ok, doc = pcall(function()
      return json.decode(raw)
    end)
    if ok and type(doc) == "table" then
      return doc
    end
  end
  if sjson and sjson.decode then
    local ok, doc = pcall(function()
      return sjson.decode(raw)
    end)
    if ok and type(doc) == "table" then
      return doc
    end
  end
  return nil
end

-- 从天气地址推导显示名；纯 location id 保持默认城市名。
local function apply_weather_address(cfg, address)
  address = trim(address)
  if address == "" then
    return
  end
  cfg.WEATHER_LOCATION = address
  if not address:match("^%d+$") then
    cfg.CITY_NAME = address
  end
end

-- 载入 launcher 保存的设备设置，让天气 app 和主页面共用一份配置。
function M.load()
  local cfg = copy_defaults()
  local raw = read_text(cfg.SETTINGS_PATH)
  local doc = decode_json(raw)
  if type(doc) ~= "table" then
    return cfg
  end

  local timezone = trim(doc.timezone)
  if timezone ~= "" then
    cfg.TIMEZONE = timezone
  end

  apply_weather_address(cfg, doc.weather_address or doc.weatherAddress)

  local city = trim(doc.weather_city or doc.city_name or doc.city)
  if city ~= "" then
    cfg.CITY_NAME = city
  end

  return cfg
end

return M
