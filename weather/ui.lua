local M = {}
M.__index = M

local MAIN_STYLE = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local DEGREE = "\194\176"
local LABEL_LONG_CLIP = rawget(_G, "LV_LABEL_LONG_CLIP") or rawget(_G, "LABEL_LONG_CLIP")
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local FONT_TIME = rawget(_G, "LV_FONT_MONTSERRAT_20")
local FONT_DATE = rawget(_G, "LV_FONT_MONTSERRAT_14")
local FONT_CITY = rawget(_G, "LV_FONT_MONTSERRAT_24")
local FONT_TEMP = rawget(_G, "LV_FONT_MONTSERRAT_40")
local FONT_DETAIL = rawget(_G, "LV_FONT_MONTSERRAT_16")
local FONT_METRIC_TITLE = rawget(_G, "LV_FONT_MONTSERRAT_16")
local FONT_METRIC_VALUE = rawget(_G, "LV_FONT_MONTSERRAT_24")

local COLORS = {
  root_bg = 0x111717,
  card_left = 0x263133,
  card_right = 0x6C8E73,
  card_border = 0xBFD8A2,
  card_shadow = 0x050707,
  text_main = 0xFFF8F1,
  text_soft = 0xDDE9DA,
  text_line = 0xC7D7B7,
  glow_top = 0xD8D96D,
  glow_bottom = 0x5CC08C,
}

-- 把 /sd 路径转换成 LVGL 的 S:/ 盘符路径。
local function sd_to_lv(path)
  if type(path) == "string" and path:sub(1, 4) == "/sd/" then
    return "S:/" .. path:sub(5)
  end
  return path
end

-- 短文本裁剪，避免天气描述或城市名撑破布局。
local function short_text(value, limit)
  local text = tostring(value or ""):gsub("[\r\n]+", " ")
  limit = tonumber(limit) or 0
  if limit <= 0 then
    return text
  end

  local function next_index(index)
    local b = string.byte(text, index)
    if not b then
      return index + 1
    end
    if b < 0x80 then
      return index + 1
    elseif b < 0xE0 then
      return math.min(index + 2, #text + 1)
    elseif b < 0xF0 then
      return math.min(index + 3, #text + 1)
    end
    return math.min(index + 4, #text + 1)
  end

  local index = 1
  local count = 0
  while index <= #text do
    count = count + 1
    if count > limit then
      break
    end
    index = next_index(index)
  end
  if count <= limit then
    return text
  end

  local keep = math.max(1, limit - 3)
  index = 1
  count = 0
  local end_index = 0
  while index <= #text and count < keep do
    end_index = next_index(index) - 1
    index = end_index + 1
    count = count + 1
  end
  return text:sub(1, end_index) .. "..."
end

-- 安全设置标签文本，所有 nil 都在这里收口。
local function set_label_text(id, text)
  if id and lv_label_set_text then
    pcall(function()
      lv_label_set_text(id, tostring(text or ""))
    end)
  end
end

-- 安全设置图片路径，资源缺失时不让脚本中断。
local function set_image_src(id, src)
  if id and lv_img_set_src and src and src ~= "" then
    pcall(function()
      lv_img_set_src(id, src)
    end)
  end
end

-- 清理对象默认样式，并关闭滚动以稳定 320x240 布局。
local function reset_obj(id)
  if not id then
    return
  end
  if lv_obj_remove_style_all then
    pcall(function()
      lv_obj_remove_style_all(id)
    end)
  end
  if lv_obj_clear_flag and LV_OBJ_FLAG_SCROLLABLE then
    pcall(function()
      lv_obj_clear_flag(id, LV_OBJ_FLAG_SCROLLABLE)
    end)
  end
end

-- 设置基础矩形样式，面板、卡片和装饰圆都复用它。
local function style_box(id, bg_color, bg_opa, radius)
  reset_obj(id)
  lv_obj_set_style_bg_color(id, bg_color or 0x000000, MAIN_STYLE)
  lv_obj_set_style_bg_opa(id, bg_opa or 255, MAIN_STYLE)
  lv_obj_set_style_radius(id, radius or 0, MAIN_STYLE)
  lv_obj_set_style_border_width(id, 0, MAIN_STYLE)
  if lv_obj_set_style_pad_all then
    lv_obj_set_style_pad_all(id, 0, MAIN_STYLE)
  end
end

-- 创建标签并固定宽度与裁剪模式，防止文字和图标重叠。
local function create_label(parent, text, font_ref, color, x, y, width, align)
  local id = lv_label_create(parent)
  set_label_text(id, text)
  lv_obj_set_pos(id, x, y)
  if font_ref then
    lv_obj_set_style_text_font(id, font_ref, MAIN_STYLE)
  end
  lv_obj_set_style_text_color(id, color, MAIN_STYLE)
  lv_obj_set_style_text_opa(id, 255, MAIN_STYLE)
  if width and width > 0 then
    lv_obj_set_width(id, width)
    if LABEL_LONG_CLIP and lv_label_set_long_mode then
      pcall(function()
        lv_label_set_long_mode(id, LABEL_LONG_CLIP)
      end)
    end
    pcall(function()
      lv_obj_set_style_text_align(id, align or ALIGN_LEFT, MAIN_STYLE)
    end)
  end
  return id
end

-- 创建无边框小面板，用于分割线等轻量元素。
local function create_panel(parent, x, y, w, h, color)
  local id = lv_obj_create(parent)
  style_box(id, color, 255, 0)
  lv_obj_set_pos(id, x, y)
  lv_obj_set_size(id, w, h)
  return id
end

-- 创建柔和发光装饰，只作为背景层，不承载信息。
local function add_glow(parent, x, y, size, color, opa)
  local glow = lv_obj_create(parent)
  style_box(glow, color, opa or 32, math.floor(size / 2))
  lv_obj_set_pos(glow, x, y)
  lv_obj_set_size(glow, size, size)
  if lv_obj_set_style_shadow_width and lv_obj_set_style_shadow_color and lv_obj_set_style_shadow_opa then
    lv_obj_set_style_shadow_width(glow, math.floor(size / 2), MAIN_STYLE)
    lv_obj_set_style_shadow_color(glow, color, MAIN_STYLE)
    lv_obj_set_style_shadow_opa(glow, opa or 32, MAIN_STYLE)
  end
  if lv_obj_move_background then
    pcall(function()
      lv_obj_move_background(glow)
    end)
  end
  return glow
end

-- 温度文本优先显示整数，避免主视觉过长。
local function format_temp_text(temp)
  if temp == nil then
    return "--" .. DEGREE .. "C"
  end
  if math.abs(temp - math.floor(temp + 0.5)) < 0.05 then
    return string.format("%d%sC", math.floor(temp + 0.5), DEGREE)
  end
  return string.format("%.1f%sC", temp, DEGREE)
end

-- 天气描述压缩到一行，保持右上区域稳定。
local function format_condition_text(text)
  local value = tostring(text or "")
  if value == "" then
    return "--"
  end
  return short_text(value, 12)
end

-- 降雨、风速或观测时间三选一作为辅助信息。
local function format_detail_text(state)
  if state.precip_x10 ~= nil then
    return string.format("Rain %.1fmm", state.precip_x10 / 10.0)
  end
  if state.wind_speed ~= nil then
    return string.format("Wind %.0fkm/h", state.wind_speed)
  end
  local hh, mm = tostring(state.obs_time or ""):match("T(%d%d):(%d%d)")
  if hh and mm then
    return "Obs " .. hh .. ":" .. mm
  end
  return "--"
end

-- 湿度统一显示为百分比。
local function format_humidity_text(v)
  if v == nil then
    return "--%"
  end
  return string.format("%d%%", math.floor(v + 0.5))
end

-- 按 km/h 估算风力等级，显示为紧凑的 Lx。
local function format_wind_level(speed)
  if speed == nil then
    return "--"
  end
  local n = tonumber(speed) or 0
  local levels = { 1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118 }
  local idx = 0
  while idx < #levels and n >= levels[idx + 1] do
    idx = idx + 1
  end
  return "L" .. tostring(idx)
end

-- 创建 UI 实例，clock 服务负责提供本地时间文本。
function M.new(app, clock)
  return setmetatable({
    app = app,
    clock = clock,
  }, M)
end

-- 检查关键 LVGL API 是否存在，缺失时 main.lua 会直接退出。
function M:available()
  return lv_obj_create and lv_label_create and (lv_scr_act or lv_get_root) and lv_clear
end

-- 初始化整页天气卡片，一屏只保留时间、城市、温度和三项指标。
function M:init()
  local app = self.app
  local root = lv_scr_act and lv_scr_act() or lv_get_root()
  lv_clear()
  app.ui.root = root

  lv_obj_set_style_bg_color(root, COLORS.root_bg, MAIN_STYLE)
  lv_obj_set_style_bg_opa(root, 255, MAIN_STYLE)
  if lv_obj_clear_flag and LV_OBJ_FLAG_SCROLLABLE then
    pcall(function()
      lv_obj_clear_flag(root, LV_OBJ_FLAG_SCROLLABLE)
    end)
  end

  local card = lv_obj_create(root)
  style_box(card, COLORS.card_left, 255, 24)
  lv_obj_set_pos(card, 4, 4)
  lv_obj_set_size(card, app.SCREEN_W - 8, app.SCREEN_H - 8)
  if lv_obj_set_style_bg_grad_color and lv_obj_set_style_bg_grad_dir then
    lv_obj_set_style_bg_grad_color(card, COLORS.card_right, MAIN_STYLE)
    lv_obj_set_style_bg_grad_dir(card, LV_GRAD_DIR_HOR, MAIN_STYLE)
  end
  lv_obj_set_style_border_width(card, 1, MAIN_STYLE)
  lv_obj_set_style_border_color(card, COLORS.card_border, MAIN_STYLE)
  lv_obj_set_style_border_opa(card, 102, MAIN_STYLE)
  if lv_obj_set_style_clip_corner then
    pcall(function()
      lv_obj_set_style_clip_corner(card, true, MAIN_STYLE)
    end)
  end
  if lv_obj_set_style_shadow_width and lv_obj_set_style_shadow_color and lv_obj_set_style_shadow_opa then
    lv_obj_set_style_shadow_width(card, 18, MAIN_STYLE)
    lv_obj_set_style_shadow_color(card, COLORS.card_shadow, MAIN_STYLE)
    lv_obj_set_style_shadow_opa(card, 128, MAIN_STYLE)
  end

  add_glow(card, 236, -30, 84, COLORS.glow_top, 34)
  add_glow(card, 262, 138, 64, COLORS.glow_bottom, 24)

  app.ui.card = card
  app.ui.time_label = create_label(card, "--:--", FONT_TIME, COLORS.text_main, 20, 17, 0, ALIGN_LEFT)
  app.ui.date_label = create_label(card, "--/--/----", FONT_DATE, COLORS.text_soft, 212, 19, 76, ALIGN_RIGHT)
  app.ui.city_label = create_label(card, short_text(app.CITY_NAME, 12), FONT_CITY, COLORS.text_main, 20, 52, 120, ALIGN_LEFT)
  app.ui.temp_label = create_label(card, "--" .. DEGREE .. "C", FONT_TEMP, COLORS.text_main, 20, 82, 132, ALIGN_LEFT)
  app.ui.cond_label = create_label(card, "--", FONT_DETAIL, COLORS.text_soft, 164, 86, 72, ALIGN_RIGHT)
  app.ui.detail_label = create_label(card, "--", FONT_DETAIL, COLORS.text_soft, 160, 112, 76, ALIGN_RIGHT)

  app.ui.main_icon = lv_img_create(card)
  lv_obj_set_pos(app.ui.main_icon, 228, 56)
  if lv_img_set_size_mode and LV_IMG_SIZE_MODE_REAL then
    pcall(function()
      lv_img_set_size_mode(app.ui.main_icon, LV_IMG_SIZE_MODE_REAL)
    end)
  end
  if lv_img_set_antialias then
    pcall(function()
      lv_img_set_antialias(app.ui.main_icon, true)
    end)
  end
  if lv_img_set_zoom then
    pcall(function()
      lv_img_set_zoom(app.ui.main_icon, 144)
    end)
  end
  set_image_src(app.ui.main_icon, sd_to_lv(app.MAIN_ICON_DIR) .. "/103.png")

  app.ui.divider = create_panel(card, 28, 152, 256, 1, COLORS.text_line)
  lv_obj_set_style_bg_opa(app.ui.divider, 180, MAIN_STYLE)

  app.ui.aqi_title = create_label(card, "AQI", FONT_METRIC_TITLE, COLORS.text_main, 24, 176, 72, ALIGN_CENTER)
  app.ui.aqi_value = create_label(card, "--", FONT_METRIC_VALUE, COLORS.text_main, 24, 204, 72, ALIGN_CENTER)

  app.ui.humidity_icon = lv_img_create(card)
  lv_obj_set_pos(app.ui.humidity_icon, 138, 174)
  set_image_src(app.ui.humidity_icon, sd_to_lv(app.MINI_ICON_DIR) .. "/humidity.png")
  app.ui.humidity_value = create_label(card, "--%", FONT_METRIC_VALUE, COLORS.text_main, 114, 204, 84, ALIGN_CENTER)

  app.ui.wind_icon = lv_img_create(card)
  lv_obj_set_pos(app.ui.wind_icon, 232, 176)
  set_image_src(app.ui.wind_icon, sd_to_lv(app.MINI_ICON_DIR) .. "/wind.png")
  app.ui.wind_value = create_label(card, "--", FONT_METRIC_VALUE, COLORS.text_main, 210, 204, 74, ALIGN_CENTER)
end

-- 刷新时间和城市，时钟每秒走这里即可。
function M:render_clock()
  local app = self.app
  set_label_text(app.ui.time_label, self.clock:clock_text())
  set_label_text(app.ui.date_label, self.clock:date_text())
  set_label_text(app.ui.city_label, short_text(app.CITY_NAME, 12))
end

-- 刷新天气数据，失败态只改文本不改布局。
function M:render_weather()
  local app = self.app
  local state = app.state
  if not app.running then
    return
  end

  if not state.valid then
    set_label_text(app.ui.temp_label, "--" .. DEGREE .. "C")
    if state.last_error then
      set_label_text(app.ui.cond_label, "Update failed")
      set_label_text(app.ui.detail_label, short_text(state.last_error, 12))
    else
      set_label_text(app.ui.cond_label, "--")
      set_label_text(app.ui.detail_label, "--")
    end
    set_label_text(app.ui.aqi_value, "--")
    set_label_text(app.ui.humidity_value, "--%")
    set_label_text(app.ui.wind_value, "--")
    return
  end

  set_label_text(app.ui.temp_label, format_temp_text(state.temp))
  set_label_text(app.ui.cond_label, format_condition_text(state.text))
  set_label_text(app.ui.detail_label, format_detail_text(state))
  set_label_text(app.ui.aqi_value, "--")
  set_label_text(app.ui.humidity_value, format_humidity_text(state.humidity))
  set_label_text(app.ui.wind_value, format_wind_level(state.wind_speed))

  if state.code and state.code ~= "" then
    set_image_src(app.ui.main_icon, sd_to_lv(app.MAIN_ICON_DIR) .. "/" .. state.code .. ".png")
  end
end

-- 页面退出时清屏，避免旧控件残留到下一个 app。
function M:destroy()
  if lv_clear then
    pcall(function()
      lv_clear()
    end)
  end
end

return M
