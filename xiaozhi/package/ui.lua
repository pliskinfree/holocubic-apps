local M = {}

local SEL_MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local LV_LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or 1
local LV_LABEL_LONG_WRAP = rawget(_G, "LV_LABEL_LONG_WRAP") or LV_LABEL_LONG_CLIP
local LV_LABEL_LONG_SCROLL_CIRCULAR = rawget(_G, "LV_LABEL_LONG_SCROLL_CIRCULAR") or LV_LABEL_LONG_CLIP
local LV_TEXT_ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local LV_IMG_SIZE_MODE_REAL = rawget(_G, "LV_IMG_SIZE_MODE_REAL") or 0
local LV_OBJ_FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") or 0
local LV_OBJ_FLAG_HIDDEN = rawget(_G, "LV_OBJ_FLAG_HIDDEN") or 0
local LV_DIR_VER = rawget(_G, "LV_DIR_VER") or 0
local LV_ANIM_ON = rawget(_G, "LV_ANIM_ON") or 1
local lv_obj_has_flag_fn = rawget(_G, "lv_obj_has_flag")

-- 官方默认 LCD 深色主题：纯黑背景、白色文字。
local C = {
  bg = 0x000000,
  text = 0xFFFFFF,
  muted = 0xB8B8B8,
  user = 0x00FF00,
  assistant = 0x222222,
  system = 0x000000,
}

local active_text_font = nil

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

local function path_exists(path)
  if not path or path == "" then
    return false
  end
  if file and file.exists then
    local ok, ret = pcall(function()
      return file.exists(path)
    end)
    if ok then
      return ret and true or false
    end
  end
  if file and file.stat then
    local ok, st = pcall(function()
      return file.stat(path)
    end)
    return ok and st ~= nil
  end
  return false
end

local function load_text_font(cfg)
  if not lv_font_load then
    return nil
  end
  local path = cfg and cfg.TEXT_FONT_PATH or nil
  if not path_exists(path) then
    return nil
  end
  local ok, handle = pcall(function()
    return lv_font_load(path)
  end)
  if ok and type(handle) == "number" and handle > 0 then
    print("[xiaozhi] font loaded", path)
    return handle
  end
  print("[xiaozhi] font load failed", tostring(path), tostring(handle))
  return nil
end

local function set_label(id, text)
  if id and lv_label_set_text then
    pcall(function()
      lv_label_set_text(id, text_or(text, ""))
    end)
  end
end

local function disable_scroll(id)
  if id and lv_obj_clear_flag and LV_OBJ_FLAG_SCROLLABLE ~= 0 then
    pcall(function()
      lv_obj_clear_flag(id, LV_OBJ_FLAG_SCROLLABLE)
    end)
  end
end

local function enable_scroll_y(id)
  if not id then
    return
  end
  if lv_obj_add_flag and LV_OBJ_FLAG_SCROLLABLE ~= 0 then
    pcall(function()
      lv_obj_add_flag(id, LV_OBJ_FLAG_SCROLLABLE)
    end)
  end
  if lv_obj_set_scroll_dir and LV_DIR_VER ~= 0 then
    pcall(function()
      lv_obj_set_scroll_dir(id, LV_DIR_VER)
    end)
  end
end

local function style_rect(id, bg, opa, scrollable)
  if not id then
    return
  end
  lv_obj_set_style_bg_color(id, bg or C.bg, SEL_MAIN)
  lv_obj_set_style_bg_opa(id, opa == nil and 255 or opa, SEL_MAIN)
  lv_obj_set_style_border_width(id, 0, SEL_MAIN)
  lv_obj_set_style_radius(id, 0, SEL_MAIN)
  if lv_obj_set_style_pad_all then
    lv_obj_set_style_pad_all(id, 0, SEL_MAIN)
  end
  if scrollable then
    enable_scroll_y(id)
  else
    disable_scroll(id)
  end
end

local function style_transparent(id)
  style_rect(id, C.bg, 0, false)
end

local function style_round(id, bg, radius)
  style_rect(id, bg, 255, false)
  lv_obj_set_style_radius(id, radius or 8, SEL_MAIN)
end

local function style_label(id, color, align)
  if not id then
    return
  end
  lv_obj_set_style_text_color(id, color or C.text, SEL_MAIN)
  if active_text_font and lv_obj_set_style_text_font then
    pcall(function()
      lv_obj_set_style_text_font(id, active_text_font, SEL_MAIN)
    end)
  end
  if lv_obj_set_style_text_align then
    lv_obj_set_style_text_align(id, align or LV_TEXT_ALIGN_CENTER, SEL_MAIN)
  end
end

local function label(parent, x, y, w, h, text, color, align, long_mode)
  local id = lv_label_create(parent)
  lv_obj_set_pos(id, x, y)
  lv_obj_set_size(id, w, h)
  if lv_label_set_long_mode then
    lv_label_set_long_mode(id, long_mode or LV_LABEL_LONG_CLIP)
  end
  style_label(id, color, align)
  set_label(id, text)
  return id
end

local function set_hidden(id, hidden)
  if not id or LV_OBJ_FLAG_HIDDEN == 0 then
    return
  end
  if lv_obj_has_flag_fn then
    local ok, has = pcall(lv_obj_has_flag_fn, id, LV_OBJ_FLAG_HIDDEN)
    if ok and has == hidden then
      return
    end
  end
  if hidden and lv_obj_add_flag then
    pcall(function() lv_obj_add_flag(id, LV_OBJ_FLAG_HIDDEN) end)
  elseif (not hidden) and lv_obj_clear_flag then
    pcall(function() lv_obj_clear_flag(id, LV_OBJ_FLAG_HIDDEN) end)
  end
end

local function utf8_len(text)
  text = text_or(text, "")
  local count = 0
  for i = 1, #text do
    local b = string.byte(text, i)
    if b < 0x80 or b >= 0xC0 then
      count = count + 1
    end
  end
  return count
end

local function bubble_size(text, max_w, min_w)
  local chars = utf8_len(text)
  local has_wide = #text > chars
  local unit_w = has_wide and 14 or 8
  local width = math.max(min_w or 44, math.min(max_w, chars * unit_w + 24))
  local per_line = math.max(1, math.floor((width - 18) / unit_w))
  local lines = math.ceil(math.max(chars, 1) / per_line)
  if lines > 3 then
    lines = 3
  end
  return width, 14 + lines * 18
end

local emotion_alias = {
  microchip_ai = "neutral",
  listening = "thinking",
  speaking = "happy",
  download = "thinking",
  link = "happy",
  triangle_exclamation = "confused",
  circle_xmark = "sad",
  cloud_slash = "sad",
}

local emotion_text = {
  neutral = "AI",
  listening = "听",
  speaking = "说",
  sleepy = "休",
  happy = "笑",
  laughing = "笑",
  funny = "乐",
  sad = "忧",
  angry = "怒",
  crying = "哭",
  loving = "爱",
  embarrassed = "羞",
  surprised = "惊",
  shocked = "惊",
  thinking = "想",
  winking = "眨",
  cool = "酷",
  relaxed = "松",
  delicious = "馋",
  kissy = "亲",
  confident = "稳",
  silly = "玩",
  confused = "?",
  microchip_ai = "AI",
  triangle_exclamation = "!",
  circle_xmark = "!",
  cloud_slash = "云",
  download = "↓",
  link = "链",
}

local function emotion_name(emotion)
  local name = text_or(emotion, "neutral")
  return emotion_alias[name] or name
end

local function find_asset(candidates)
  for i = 1, #candidates do
    if path_exists(candidates[i]) then
      return candidates[i]
    end
  end
  return nil
end

local function now_clock()
  if time and time.getlocal then
    local ok, t = pcall(time.getlocal)
    if ok and type(t) == "table" and t.hour then
      return string.format("%02d:%02d", tonumber(t.hour) or 0, tonumber(t.min) or 0)
    end
  end
  if time and time.get and time.epoch2cal then
    local ok, sec = pcall(time.get)
    if ok and type(sec) == "number" then
      local ok_cal, cal = pcall(time.epoch2cal, sec)
      if ok_cal and type(cal) == "table" and cal.hour then
        return string.format("%02d:%02d", tonumber(cal.hour) or 0, tonumber(cal.min) or 0)
      end
    end
  end
  return ""
end

local function now_ms()
  if millis then
    local ok, value = pcall(millis)
    if ok and tonumber(value) then
      return tonumber(value)
    end
  end
  if tmr and tmr.now then
    local ok, value = pcall(tmr.now)
    if ok and tonumber(value) then
      return math.floor(tonumber(value) / 1000)
    end
  end
  return 0
end

function M.new(cfg)
  local self = {
    cfg = cfg,
    root = nil,
    notification_timer = nil,
    text_font = nil,
    ui = {},
    messages = {},
    view_mode = "default",
    last_state = "",
    last_status = "正在初始化",
    last_status_ms = 0,
    last_emotion = "microchip_ai",
    last_role = "system",
    last_message = "",
    current_emotion_name = "",
    current_media_kind = "",
    current_media_src = "",
    gif_loaded_src = "",
    last_emotion_ms = 0,
    metrics = {},
  }

  local function append_message(role, content)
    content = text_or(content, "")
    if content == "" then
      return
    end
    role = text_or(role, "system")
    local last = self.messages[#self.messages]
    if role == "system" and last and last.role == "system" then
      last.content = content
    else
      self.messages[#self.messages + 1] = { role = role, content = content }
    end
    while #self.messages > 20 do
      table.remove(self.messages, 1)
    end
  end

  local function draw_bubble(role, content, y)
    local max_w = role == "system" and 236 or 230
    local min_w = role == "system" and 52 or 48
    local w, h = bubble_size(content, max_w, min_w)
    local x = 12
    local bg = C.assistant
    if role == "user" then
      x = 320 - 12 - w
      bg = C.user
    elseif role == "system" then
      x = math.floor((320 - w) / 2)
      bg = C.system
    end

    local bubble = lv_obj_create(self.ui.chat_area)
    lv_obj_set_pos(bubble, x, y)
    lv_obj_set_size(bubble, w, h)
    style_round(bubble, bg, 8)

    local txt = label(bubble, 9, 7, w - 18, h - 12, content, C.text,
      LV_TEXT_ALIGN_CENTER, LV_LABEL_LONG_WRAP)
    if role ~= "system" and lv_obj_set_style_text_align then
      lv_obj_set_style_text_align(txt, LV_TEXT_ALIGN_CENTER, SEL_MAIN)
    end
    return bubble, h
  end

  -- 重绘微信气泡列表；列表对象较少，重建比维护局部状态更稳定。
  local function refresh_chat_area()
    if not self.ui.chat_area or not lv_obj_clean then
      return
    end
    pcall(function()
      lv_obj_clean(self.ui.chat_area)
    end)
    local y = 10
    local last = nil
    for _, item in ipairs(self.messages) do
      local bubble, h = draw_bubble(item.role, item.content, y)
      last = bubble
      y = y + h + 8
    end
    if last and lv_obj_scroll_to_view_recursive then
      pcall(function()
        lv_obj_scroll_to_view_recursive(last, LV_ANIM_ON)
      end)
    end
  end

  -- 切换官方字幕模式 / 微信气泡模式，不重建页面以避免 GIF 资源抖动。
  function self:set_view_mode(mode, quiet)
    mode = mode == "wechat" and "wechat" or "default"
    if self.view_mode == mode and self.ui.chat_area then
      return
    end
    self.view_mode = mode
    set_hidden(self.ui.chat_area, mode ~= "wechat")
    set_hidden(self.ui.emoji_box, mode == "wechat")
    if mode == "wechat" then
      set_hidden(self.ui.bottom_bar, true)
      refresh_chat_area()
      if not quiet then
        self:show_notification("微信气泡模式", 1200)
      end
    else
      set_hidden(self.ui.bottom_bar, self.last_message == "")
      if not quiet then
        self:show_notification("官方字幕模式", 1200)
      end
    end
  end

  -- 更新顶部居中的状态文字；通知显示时会临时覆盖它。
  function self:set_status(status)
    self.last_status = text_or(status, "")
    self.last_status_ms = now_ms()
    set_label(self.ui.status, self.last_status)
    set_hidden(self.ui.notify, true)
    set_hidden(self.ui.status, false)
  end

  -- 显示官方同款顶部通知，超时后恢复状态文字。
  function self:show_notification(text, duration_ms)
    duration_ms = tonumber(duration_ms) or 3000
    set_label(self.ui.notify, text_or(text, ""))
    set_hidden(self.ui.status, true)
    set_hidden(self.ui.notify, false)
    if self.notification_timer then
      pcall(function() self.notification_timer:stop() end)
      pcall(function() self.notification_timer:unregister() end)
      self.notification_timer = nil
    end
    if tmr and tmr.create then
      self.notification_timer = tmr.create()
      self.notification_timer:alarm(duration_ms, tmr.ALARM_SINGLE, function()
        self.notification_timer = nil
        set_hidden(self.ui.notify, true)
        set_hidden(self.ui.status, false)
      end)
    end
  end

  -- 先使用官方表情 GIF，再退回 PNG，最后退回白色文字占位。
  function self:set_emotion(emotion)
    self.last_emotion = text_or(emotion, "neutral")
    local name = emotion_name(self.last_emotion)
    local ts = now_ms()
    if self.current_emotion_name == name and self.current_media_kind ~= "" then
      return
    end
    local min_ms = self.cfg.UI and tonumber(self.cfg.UI.emotion_min_ms) or 0
    local important = (name == "sad" or name == "confused" or name == "shocked" or name == "circle_xmark")
    if not important and self.current_emotion_name ~= "" and min_ms > 0 and
        ts > 0 and (ts - self.last_emotion_ms) < min_ms then
      return
    end

    local gif_path = find_asset({
      (self.cfg.EMOJI_GIF_DIR or "") .. "/" .. name .. ".gif",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".gif",
    })
    local gif_enabled = not (self.cfg.UI and self.cfg.UI.gif_enabled == false)
    if gif_enabled and gif_path and self.ui.emotion_gif and lv_gif_set_src then
      -- GIF 解码器设置 src 会从第一帧重启；同一路径已加载时只切可见性。
      local ok = true
      if self.gif_loaded_src ~= gif_path then
        ok = pcall(function()
          lv_gif_set_src(self.ui.emotion_gif, gif_path)
        end)
      end
      if ok then
        self.current_emotion_name = name
        self.current_media_kind = "gif"
        self.current_media_src = gif_path
        self.gif_loaded_src = gif_path
        self.last_emotion_ms = ts
        set_hidden(self.ui.emotion_gif, false)
        set_hidden(self.ui.emotion_img, true)
        set_hidden(self.ui.emotion, true)
        return
      end
    end

    local img_path = find_asset({
      (self.cfg.EMOJI_PNG_DIR or "") .. "/" .. name .. ".png",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".png",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".jpg",
      (self.cfg.ASSET_DIR or "") .. "/emojis/" .. name .. ".bmp",
    })
    if img_path and self.ui.emotion_img and lv_img_set_src then
      local ok = true
      if self.current_media_kind ~= "img" or self.current_media_src ~= img_path then
        ok = pcall(function()
          lv_img_set_src(self.ui.emotion_img, img_path)
          if lv_img_set_size_mode then
            lv_img_set_size_mode(self.ui.emotion_img, LV_IMG_SIZE_MODE_REAL)
          end
          if lv_img_set_zoom then
            lv_img_set_zoom(self.ui.emotion_img, 256)
          end
          if lv_img_set_antialias then
            lv_img_set_antialias(self.ui.emotion_img, true)
          end
        end)
      end
      if ok then
        if self.ui.emotion_gif and lv_gif_set_src and self.current_media_kind == "gif" then
          pcall(function() lv_gif_set_src(self.ui.emotion_gif, nil) end)
        end
        self.gif_loaded_src = ""
        self.current_emotion_name = name
        self.current_media_kind = "img"
        self.current_media_src = img_path
        self.last_emotion_ms = ts
        set_hidden(self.ui.emotion_gif, true)
        set_hidden(self.ui.emotion_img, false)
        set_hidden(self.ui.emotion, true)
        return
      end
    end

    if self.ui.emotion_gif and lv_gif_set_src and self.current_media_kind == "gif" then
      pcall(function() lv_gif_set_src(self.ui.emotion_gif, nil) end)
    end
    self.gif_loaded_src = ""
    self.current_emotion_name = name
    self.current_media_kind = "text"
    self.current_media_src = emotion_text[self.last_emotion] or emotion_text[name] or self.last_emotion
    self.last_emotion_ms = ts
    set_hidden(self.ui.emotion_gif, true)
    set_hidden(self.ui.emotion_img, true)
    set_hidden(self.ui.emotion, false)
    set_label(self.ui.emotion, self.current_media_src)
  end

  -- 默认模式显示底部字幕；微信模式保存最近 20 条并重绘气泡。
  function self:set_chat_message(role, content)
    self.last_role = text_or(role, "system")
    self.last_message = text_or(content, "")
    append_message(self.last_role, self.last_message)
    set_label(self.ui.chat, self.last_message)
    set_hidden(self.ui.bottom_bar, self.view_mode ~= "default" or self.last_message == "")
    if self.view_mode == "wechat" then
      refresh_chat_area()
    end
  end

  function self:clear_chat_messages()
    self.last_role = "system"
    self.last_message = ""
    self.messages = {}
    set_label(self.ui.chat, "")
    set_hidden(self.ui.bottom_bar, true)
    if self.ui.chat_area and lv_obj_clean then
      pcall(function()
        lv_obj_clean(self.ui.chat_area)
      end)
    end
  end

  function self:update_status_bar(force)
    local metrics = self.metrics or {}
    set_label(self.ui.net, metrics.network or "")
    set_label(self.ui.audio, "")
    set_label(self.ui.wake, "")
    if self.last_state == "idle" then
      local ts = now_ms()
      if ts > 0 and self.last_status_ms > 0 and (ts - self.last_status_ms) > 10000 then
        local clock = now_clock()
        if clock ~= "" then
          set_label(self.ui.status, clock)
        end
      end
    end
    if force then
      self:set_status(self.last_status)
    end
  end

  function self:set_metrics(metrics)
    self.metrics = metrics or {}
    self:update_status_bar(false)
  end

  function self:on_state(state)
    self.last_state = text_or(state, "")
    local status = {
      starting = "启动中",
      wifi_configuring = "配网中",
      activating = "激活中",
      idle = "待命",
      connecting = "连接中",
      listening = "聆听中",
      speaking = "回答中",
      upgrading = "升级中",
      audio_testing = "音频测试",
      fatal_error = "错误",
    }
    local emotion = {
      starting = "microchip_ai",
      wifi_configuring = "thinking",
      activating = "thinking",
      idle = "neutral",
      connecting = "thinking",
      listening = "thinking",
      speaking = "happy",
      upgrading = "download",
      audio_testing = "microchip_ai",
      fatal_error = "circle_xmark",
    }
    self:set_status(status[state] or tostring(state or ""))
    self:set_emotion(emotion[state] or "neutral")
  end

  function self:alert(status, message, emotion)
    self:set_status(status or "错误")
    self:set_emotion(emotion or "circle_xmark")
    self:set_chat_message("system", message or "")
  end

  -- 搭建官方默认 LCD 布局，并预创建微信气泡层供长按切换。
  function self:setup()
    self.root = lv_scr_act and lv_scr_act() or nil
    if not self.root or not lv_obj_create or not lv_label_create then
      print("[xiaozhi] lvgl api missing")
      return false
    end
    if lv_obj_clean then
      pcall(function() lv_obj_clean(self.root) end)
    end

    active_text_font = load_text_font(self.cfg)
    self.text_font = active_text_font
    style_rect(self.root, C.bg, 255, false)

    self.ui.container = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.container, 0, 0)
    lv_obj_set_size(self.ui.container, 320, 240)
    style_rect(self.ui.container, C.bg, 255, false)

    self.ui.chat_area = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.chat_area, 0, 28)
    lv_obj_set_size(self.ui.chat_area, 320, 212)
    style_rect(self.ui.chat_area, C.bg, 255, true)
    set_hidden(self.ui.chat_area, true)

    self.ui.emoji_box = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.emoji_box, 110, 70)
    lv_obj_set_size(self.ui.emoji_box, 100, 100)
    style_transparent(self.ui.emoji_box)

    if lv_gif_create then
      self.ui.emotion_gif = lv_gif_create(self.ui.emoji_box)
      lv_obj_set_pos(self.ui.emotion_gif, 18, 18)
      lv_obj_set_size(self.ui.emotion_gif, 64, 64)
      set_hidden(self.ui.emotion_gif, true)
    end

    if lv_img_create then
      self.ui.emotion_img = lv_img_create(self.ui.emoji_box)
      lv_obj_set_pos(self.ui.emotion_img, 18, 18)
      lv_obj_set_size(self.ui.emotion_img, 64, 64)
      set_hidden(self.ui.emotion_img, true)
    end

    self.ui.emotion = label(self.ui.emoji_box, 0, 34, 100, 32, "AI", C.text)

    self.ui.bottom_bar = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.bottom_bar, 0, 204)
    lv_obj_set_size(self.ui.bottom_bar, 320, 36)
    style_rect(self.ui.bottom_bar, C.bg, 128, false)
    self.ui.chat = label(self.ui.bottom_bar, 16, 8, 288, 20, "", C.text,
      LV_TEXT_ALIGN_CENTER, LV_LABEL_LONG_SCROLL_CIRCULAR)
    set_hidden(self.ui.bottom_bar, true)

    self.ui.top_bar = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.top_bar, 0, 0)
    lv_obj_set_size(self.ui.top_bar, 320, 28)
    style_rect(self.ui.top_bar, C.bg, 128, false)

    self.ui.net = label(self.ui.top_bar, 12, 6, 52, 16, "", C.text)
    self.ui.audio = label(self.ui.top_bar, 232, 6, 34, 16, "", C.text)
    self.ui.wake = label(self.ui.top_bar, 270, 6, 38, 16, "", C.text)

    self.ui.status_bar = lv_obj_create(self.root)
    lv_obj_set_pos(self.ui.status_bar, 0, 0)
    lv_obj_set_size(self.ui.status_bar, 320, 28)
    style_transparent(self.ui.status_bar)
    self.ui.notify = label(self.ui.status_bar, 32, 5, 256, 18, "", C.text)
    self.ui.status = label(self.ui.status_bar, 32, 5, 256, 18, self.last_status,
      C.text, LV_TEXT_ALIGN_CENTER, LV_LABEL_LONG_SCROLL_CIRCULAR)
    set_hidden(self.ui.notify, true)

    self:set_emotion("neutral")
    self:set_view_mode("default", true)
    self:update_status_bar(true)
    return true
  end

  function self:stop()
    if self.notification_timer then
      pcall(function() self.notification_timer:stop() end)
      pcall(function() self.notification_timer:unregister() end)
      self.notification_timer = nil
    end
    if self.ui.emotion_gif and lv_gif_set_src then
      pcall(function() lv_gif_set_src(self.ui.emotion_gif, nil) end)
    end
    self.gif_loaded_src = ""
    if self.root and lv_obj_clean then
      pcall(function() lv_obj_clean(self.root) end)
    end
    if self.text_font and lv_font_free then
      pcall(function() lv_font_free(self.text_font) end)
      if active_text_font == self.text_font then
        active_text_font = nil
      end
      self.text_font = nil
    end
  end

  return self
end

return M
