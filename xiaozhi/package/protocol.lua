local M = {}

local function json_escape(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub('"', '\\"')
  text = text:gsub("\n", "\\n")
  text = text:gsub("\r", "\\r")
  return text
end

local function json_pair(key, value)
  return '"' .. key .. '":"' .. json_escape(value) .. '"'
end

local function pick_string(raw, name)
  if type(raw) ~= "string" then
    return nil
  end
  return raw:match('"' .. name .. '"%s*:%s*"([^"]*)"')
end

local function pick_number(raw, name)
  if type(raw) ~= "string" then
    return nil
  end
  return tonumber(raw:match('"' .. name .. '"%s*:%s*(%d+)') or "")
end

local function u16be(value)
  value = tonumber(value) or 0
  local hi = math.floor(value / 256) % 256
  local lo = value % 256
  return string.char(hi, lo)
end

local function device_id(cfg)
  local ok, ident = pcall(dofile, ((cfg and cfg.APP_DIR) or "/sd/apps/xiaozhi") .. "/identity.lua")
  if ok and ident and ident.device_id then
    return ident.device_id(), ident.client_id()
  end
  return "02:00:00:00:00:01", "00000000-0000-4000-8000-020000000001"
end

function M.new(cfg)
  local self = {
    cfg = cfg,
    ws = nil,
    connected = false,
    opened = false,
    connecting = false,
    session_id = "",
    server_sample_rate = 24000,
    server_frame_duration = 60,
    last_error = "",
    callbacks = {},
  }

  function self:on(name, fn)
    self.callbacks[name] = fn
  end

  local function emit(name, ...)
    local fn = self.callbacks[name]
    if fn then
      pcall(fn, ...)
    end
  end

  local function set_error(msg)
    self.last_error = tostring(msg or "")
    if self.last_error ~= "" then
      emit("error", self.last_error)
    end
  end

  function self:info()
    return {
      connected = self.connected,
      opened = self.opened,
      connecting = self.connecting,
      session_id = self.session_id,
      server_sample_rate = self.server_sample_rate,
      server_frame_duration = self.server_frame_duration,
      last_error = self.last_error,
    }
  end

  local function send_text(text)
    if not self.ws or not self.connected then
      return false, "not connected"
    end
    local ok, err = pcall(function()
      return self.ws:send(text, websocket.TEXT)
    end)
    if not ok then
      return false, tostring(err)
    end
    if type(err) == "string" then
      return false, err
    end
    return true
  end

  function self:send_text(text)
    return send_text(text)
  end

  local function hello_json()
    return "{" ..
      json_pair("type", "hello") ..
      ',"version":' .. tostring(cfg.websocket.version or 3) ..
      ',"features":{"mcp":true}' ..
      ',"transport":"websocket"' ..
      ',"audio_params":{"format":"opus","sample_rate":' .. tostring(cfg.AUDIO.rate or 12000) ..
      ',"channels":1,"frame_duration":' ..
      tostring(cfg.AUDIO.frame_ms or 60) .. "}" ..
      "}"
  end

  local function handle_hello(raw)
    local transport = pick_string(raw, "transport")
    if transport and transport ~= "websocket" then
      set_error("unsupported transport")
      return
    end
    self.session_id = pick_string(raw, "session_id") or self.session_id
    self.server_sample_rate = pick_number(raw, "sample_rate") or self.server_sample_rate
    self.server_frame_duration = pick_number(raw, "frame_duration") or self.server_frame_duration
    self.opened = true
    self.connecting = false
    emit("opened")
  end

  local function handle_json(raw)
    local typ = pick_string(raw, "type")
    if typ == "hello" then
      handle_hello(raw)
      return
    end
    if typ == "tts" then
      local state = pick_string(raw, "state")
      if state == "start" then
        emit("tts_start")
      elseif state == "stop" then
        emit("tts_stop")
      elseif state == "sentence_start" then
        emit("chat", "assistant", pick_string(raw, "text") or "")
      end
    elseif typ == "stt" then
      emit("chat", "user", pick_string(raw, "text") or "")
    elseif typ == "llm" then
      local emotion = pick_string(raw, "emotion")
      if emotion then
        emit("emotion", emotion)
      end
    elseif typ == "alert" then
      emit("alert", pick_string(raw, "status") or "alert",
        pick_string(raw, "message") or "", pick_string(raw, "emotion") or "neutral")
    elseif typ == "mcp" then
      emit("mcp", raw)
    else
      emit("json", raw)
    end
  end

  local function parse_binary(data)
    if (cfg.websocket.version or 3) == 3 and type(data) == "string" and #data >= 4 then
      local typ, _, hi, lo = string.byte(data, 1, 4)
      local size = (hi or 0) * 256 + (lo or 0)
      if typ == 0 and size > 0 and #data >= size + 4 then
        return data:sub(5, size + 4)
      end
    end
    return data
  end

  function self:start()
    return true
  end

  function self:is_audio_channel_opened()
    return self.connected and self.opened
  end

  function self:open_audio_channel()
    if self:is_audio_channel_opened() then
      return true
    end
    if not websocket or not websocket.createClient then
      set_error("websocket api missing")
      return false
    end
    if not cfg.websocket.url or cfg.websocket.url == "" then
      set_error("websocket config missing")
      return false
    end

    self:close_audio_channel(false)
    self.connecting = true
    self.opened = false
    self.connected = false

    local ws = websocket.createClient()
    self.ws = ws
    local token = cfg.websocket.token or ""
    if token ~= "" and not token:find(" ", 1, true) then
      token = "Bearer " .. token
    end
    local id, client_id = device_id(cfg)
    local headers = {
      ["Protocol-Version"] = tostring(cfg.websocket.version or 3),
      ["Device-Id"] = id,
      ["Client-Id"] = client_id or id,
    }
    if token ~= "" then
      headers["Authorization"] = token
    end

    ws:config({
      headers = headers,
      buffer_size = cfg.websocket.buffer_size,
      task_stack = cfg.websocket.task_stack,
      network_timeout_ms = cfg.websocket.timeout_ms,
      async_send = cfg.websocket.async_send,
      send_task_core = cfg.websocket.send_task_core,
      send_queue_depth = cfg.websocket.send_queue_depth,
      send_queue_bytes = cfg.websocket.send_queue_bytes,
      send_timeout_ms = cfg.websocket.send_timeout_ms,
      auto_reconnect = false,
      use_crt_bundle = true,
    })

    ws:on("connection", function(client)
      self.connected = true
      self.connecting = false
      emit("connected")
      local ok, err = send_text(hello_json())
      if not ok then
        set_error(err)
      end
    end)

    ws:on("receive", function(_, data, opcode)
      if opcode == websocket.BINARY then
        emit("audio", parse_binary(data))
      else
        handle_json(data)
      end
    end)

    ws:on("close", function(_, status)
      self.connected = false
      self.opened = false
      self.connecting = false
      self.ws = nil
      emit("closed", status)
    end)

    local ok, err = pcall(function()
      ws:connect(cfg.websocket.url)
    end)
    if not ok then
      self.connecting = false
      set_error(tostring(err or "websocket connect failed"))
      return false
    end
    return true
  end

  function self:close_audio_channel(send_goodbye)
    if self.ws then
      pcall(function() self.ws:close() end)
    end
    self.ws = nil
    self.connected = false
    self.opened = false
    self.connecting = false
    if send_goodbye then
      emit("closed", 0)
    end
  end

  function self:send_audio(opus)
    if not self:is_audio_channel_opened() then
      return false
    end
    local packet = opus
    if (cfg.websocket.version or 3) == 3 then
      packet = string.char(0, 0) .. u16be(#opus) .. opus
    end
    local ok, err = pcall(function()
      return self.ws:send(packet, websocket.BINARY)
    end)
    if not ok or type(err) == "string" then
      set_error(tostring(err or "send audio failed"))
      return false
    end
    return true
  end

  function self:send_wake_word_detected(wake_word)
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"listen","state":"detect",' .. json_pair("text", wake_word) .. "}")
  end

  function self:send_start_listening(mode)
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"listen","state":"start","mode":"' .. json_escape(mode or "auto") .. '"}')
  end

  function self:send_stop_listening()
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"listen","state":"stop"}')
  end

  function self:send_abort_speaking(reason)
    local msg = "{" .. json_pair("session_id", self.session_id) .. ',"type":"abort"'
    if reason == "wake_word_detected" then
      msg = msg .. ',"reason":"wake_word_detected"'
    end
    return send_text(msg .. "}")
  end

  function self:send_mcp_message(payload)
    return send_text("{" .. json_pair("session_id", self.session_id) ..
      ',"type":"mcp","payload":' .. tostring(payload or "{}") .. "}")
  end

  function self:stop()
    self:close_audio_channel(false)
  end

  return self
end

return M
