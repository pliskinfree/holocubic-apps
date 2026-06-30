local M = {}
M.__index = M

-- 转成 number，接口字段缺失或格式异常时返回 nil。
local function get_number(v)
  if v == nil then
    return nil
  end
  if type(v) == "number" then
    return v
  end
  return tonumber(v)
end

-- 转成一位小数的 x10 定点值，减少 UI 层浮点处理。
local function to_x10(v)
  local n = get_number(v)
  if n == nil then
    return nil
  end
  if n >= 0 then
    return math.floor(n * 10 + 0.5)
  end
  return math.ceil(n * 10 - 0.5)
end

-- URL 参数编码，支持城市名、经纬度和 location id。
local function url_encode(text)
  text = tostring(text or "")
  return (text:gsub("([^%w%-%._~])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

-- 解码 JSON，兼容 json 和 sjson 两种全局模块。
local function decode_json(raw)
  if type(raw) ~= "string" or raw == "" then
    return nil, "empty body"
  end
  if json and json.decode then
    local ok, doc, err = pcall(function()
      local value, decode_err = json.decode(raw)
      return value, decode_err
    end)
    if ok and type(doc) == "table" then
      return doc, nil
    end
    if not ok then
      return nil, tostring(doc)
    end
    return nil, tostring(err or "decode failed")
  end
  if sjson and sjson.decode then
    local ok, doc = pcall(function()
      return sjson.decode(raw)
    end)
    if ok and type(doc) == "table" then
      return doc, nil
    end
    return nil, tostring(doc)
  end
  return nil, "json missing"
end

-- 服务端返回 gzip 时先解压，普通文本直接返回原 body。
local function maybe_gunzip_body(body)
  if not body then
    return nil, "body is nil"
  end
  if not zlib or not zlib.isgzip or not zlib.isgzip(body) then
    return body, nil
  end
  if not zlib.gunzip then
    return nil, "gunzip missing"
  end
  local plain, err = zlib.gunzip(body)
  if not plain then
    return nil, "gunzip failed: " .. tostring(err)
  end
  return plain, nil
end

-- 创建天气接口客户端，直接更新 app.state 以减少跨模块数据复制。
function M.new(app)
  return setmetatable({
    app = app,
  }, M)
end

-- 拼接当前天气接口地址，location 使用 launcher 保存的天气地址。
function M:now_url()
  local app = self.app
  return app.WEATHER_HOST
    .. "/v7/weather/now?location="
    .. url_encode(app.WEATHER_LOCATION)
    .. "&key="
    .. url_encode(app.WEATHER_KEY)
end

-- 解析 QWeather now 响应，并把结果写入 app.state。
function M:parse_now(status_code, body)
  local app = self.app
  local state = app.state
  state.last_http_code = status_code

  if status_code ~= 200 or not body then
    state.valid = false
    state.last_error = "HTTP " .. tostring(status_code)
    return false
  end

  local doc, err = decode_json(body)
  if not doc then
    state.valid = false
    state.last_error = "JSON " .. tostring(err)
    return false
  end

  local api_code = tostring(doc.code or "")
  if api_code ~= "200" then
    state.valid = false
    state.last_error = "API " .. api_code
    return false
  end

  local now = doc.now
  if type(now) ~= "table" then
    state.valid = false
    state.last_error = "NO NOW"
    return false
  end

  state.valid = true
  state.last_error = nil
  state.temp = get_number(now.temp)
  state.humidity = get_number(now.humidity)
  state.wind_speed = get_number(now.windSpeed)
  state.precip_x10 = to_x10(now.precip)
  state.text = tostring(now.text or "--")
  state.code = tostring(now.icon or "")
  state.obs_time = tostring(now.obsTime or "")
  state.last_update_ms = millis and (millis() or 0) or 0
  return true
end

-- 发起当前天气请求；上一轮未返回时跳过，避免堆积 HTTP 回调。
function M:request_now(on_done)
  local app = self.app
  local state = app.state
  if not app.running then
    return
  end

  if not http or not http.get then
    state.valid = false
    state.last_error = "HTTP missing"
    if on_done then
      on_done(false)
    end
    return
  end

  if state.request_inflight then
    return
  end

  state.request_inflight = true
  http.get(self:now_url(), "Accept-Encoding: gzip\r\n", function(status_code, body, headers)
    state.request_inflight = false
    if not app.running then
      return
    end

    local plain, err = maybe_gunzip_body(body)
    if not plain then
      state.valid = false
      state.last_http_code = status_code
      state.last_error = tostring(err)
      if on_done then
        on_done(false)
      end
      return
    end

    local ok = self:parse_now(status_code, plain)
    if on_done then
      on_done(ok)
    end
  end)
end

return M
