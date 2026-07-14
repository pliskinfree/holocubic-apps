local SCREEN_W = 320
local SCREEN_H = 240

local SETUP_SSID = "clocteck-cubic"
local SETUP_PORTAL = "192.168.18.1"
local DEVICE_HOST = "clocteck-cubic.local"
local FONT_DIR = "/sd/apps/wifi_guide/font"
local ICON_PATH = "/sd/apps/wifi_guide/assets/wifi-guide-ios.png"
local SUCCESS_TITLE_PATH = "/sd/apps/wifi_guide/assets/success-title.png"

local root = lv_scr_act()
lv_obj_clean(root)

local UI = {
  setup = {},
  success = {},
}

local STATE = {
  poll_timer = nil,
  font_handles = {},
  connected = false,
  last_ip = "",
  screen = "setup",
}

local FONT_TITLE = LV_FONT_SIMSUN_20 or LV_FONT_MISANS_20 or LV_FONT_MONTSERRAT_20
local FONT_BODY = LV_FONT_SIMSUN_16 or LV_FONT_MISANS_16 or LV_FONT_MONTSERRAT_16
local FONT_SMALL = LV_FONT_SIMSUN_14 or LV_FONT_MISANS_14 or LV_FONT_MONTSERRAT_14

local show_setup

local function text_or(value, fallback)
  if value == nil or value == "" then
    return fallback or ""
  end
  return tostring(value)
end

local function safe_set_text(id, text)
  if not id then
    return
  end
  pcall(function()
    lv_label_set_text(id, text_or(text, ""))
  end)
end

local function safe_set_hidden(id, hidden)
  if not id then
    return
  end
  pcall(function()
    if hidden then
      lv_obj_add_flag(id, LV_OBJ_FLAG_HIDDEN)
    else
      lv_obj_clear_flag(id, LV_OBJ_FLAG_HIDDEN)
    end
  end)
end

local function style_panel(id, bg, opa, radius, border_w, border_color, border_opa)
  lv_obj_set_style_bg_color(id, bg, LV_PART_MAIN)
  lv_obj_set_style_bg_opa(id, opa, LV_PART_MAIN)
  lv_obj_set_style_radius(id, radius, LV_PART_MAIN)
  lv_obj_set_style_border_width(id, border_w, LV_PART_MAIN)
  lv_obj_set_style_border_color(id, border_color, LV_PART_MAIN)
  lv_obj_set_style_border_opa(id, border_opa, LV_PART_MAIN)
  lv_obj_set_style_pad_all(id, 0, LV_PART_MAIN)
end

local function style_text(id, color, font, align)
  lv_obj_set_style_text_color(id, color, LV_PART_MAIN)
  lv_obj_set_style_text_opa(id, 255, LV_PART_MAIN)
  if font then
    lv_obj_set_style_text_font(id, font, LV_PART_MAIN)
  end
  lv_obj_set_style_text_align(id, align or LV_TEXT_ALIGN_LEFT, LV_PART_MAIN)
end

local function make_panel(parent, x, y, w, h, bg, opa, radius, border_w, border_color, border_opa)
  local obj = lv_obj_create(parent)
  lv_obj_set_pos(obj, x, y)
  lv_obj_set_size(obj, w, h)
  style_panel(obj, bg, opa or 255, radius or 0, border_w or 0, border_color or 0x000000, border_opa or 0)
  return obj
end

local function make_label(parent, x, y, w, h, text, color, font, align)
  local label = lv_label_create(parent)
  lv_obj_set_pos(label, x, y)
  lv_obj_set_size(label, w, h)
  pcall(function()
    lv_label_set_long_mode(label, LV_LABEL_LONG_WRAP)
  end)
  style_text(label, color, font, align)
  safe_set_text(label, text)
  return label
end

local function stop_timer(name)
  local timer = STATE[name]
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
    timer:unregister()
  end)
  STATE[name] = nil
end

local function looks_like_ip(ip)
  ip = text_or(ip, "")
  if ip == "" or ip == "0.0.0.0" then
    return false
  end
  return ip:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

local function call_value(fn)
  local ok, value = pcall(fn)
  if ok then
    return value
  end
  return nil
end

local function load_font(path, fallback)
  if not lv_font_load then
    return fallback
  end
  local ok, handle = pcall(function()
    return lv_font_load(path)
  end)
  if ok and type(handle) == "number" and handle > 0 then
    STATE.font_handles[#STATE.font_handles + 1] = handle
    return handle
  end
  return fallback
end

local function init_fonts()
  FONT_SMALL = load_font(FONT_DIR .. "/msyh_cn_13.bin", FONT_SMALL)
  FONT_BODY = load_font(FONT_DIR .. "/msyh_cn_13.bin", FONT_BODY)
  FONT_TITLE = load_font(FONT_DIR .. "/18chinese.bin", FONT_TITLE)
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(STATE.font_handles) do
      pcall(function()
        lv_font_free(handle)
      end)
    end
  end
  STATE.font_handles = {}
end

local function wifi_ip()
  local ip = nil

  if wifi and wifi.sta and wifi.sta.getip then
    ip = call_value(function()
      return wifi.sta.getip()
    end)
  end

  if not looks_like_ip(ip) and wifi and wifi.sta and wifi.sta.ip then
    ip = call_value(function()
      return wifi.sta.ip()
    end)
  end

  if not looks_like_ip(ip) and net and net.getifaddr then
    ip = call_value(function()
      return net.getifaddr()
    end)
  end

  return looks_like_ip(ip) and tostring(ip) or ""
end

local function wifi_connected()
  local ip = wifi_ip()
  if ip ~= "" then
    return true, ip
  end

  if wifi and wifi.sta and wifi.sta.status then
    local status = call_value(function()
      return wifi.sta.status()
    end)
    if status == "got_ip" or status == "connected" or status == 5 then
      return true, ""
    end
  end

  return false, ""
end

local function set_group_visible(group, visible)
  for _, obj in pairs(group) do
    safe_set_hidden(obj, not visible)
  end
end

show_setup = function()
  STATE.connected = false
  STATE.screen = "setup"
  lv_obj_set_style_bg_color(UI.bg, 0x000000, LV_PART_MAIN)
  set_group_visible(UI.success, false)
  set_group_visible(UI.setup, true)
end

local function show_success(ip)
  STATE.connected = true
  STATE.screen = "success"
  STATE.last_ip = text_or(ip, STATE.last_ip)
  safe_set_text(UI.success.ip, text_or(STATE.last_ip, "获取 IP"))
  lv_obj_set_style_bg_color(UI.bg, 0x000000, LV_PART_MAIN)
  set_group_visible(UI.setup, false)
  set_group_visible(UI.success, true)
end

local function check_network()
  local ok, ip = wifi_connected()
  if ok then
    if not STATE.connected or STATE.screen ~= "success" then
      show_success(ip)
    elseif looks_like_ip(ip) and ip ~= STATE.last_ip then
      STATE.last_ip = ip
      safe_set_text(UI.success.ip, ip)
    end
  elseif STATE.connected or STATE.screen ~= "setup" then
    show_setup()
  end
end

local function leave_app()
  stop_timer("poll_timer")
  release_fonts()

  if app and app.exit then
    pcall(function()
      return app.exit()
    end)
  end
end

local function add_wifi_mark()
  if lv_img_create and lv_img_set_src then
    UI.setup.icon_img = lv_img_create(root)
    lv_obj_set_pos(UI.setup.icon_img, 247, 15)
    local ok = pcall(function()
      lv_img_set_src(UI.setup.icon_img, ICON_PATH)
      if lv_img_set_zoom then
        lv_img_set_zoom(UI.setup.icon_img, 116)
      end
    end)
    if ok then
      return
    end
    safe_set_hidden(UI.setup.icon_img, true)
  end

  UI.setup.icon_bar1 = make_panel(root, 232, 22, 60, 6, 0x22D3EE, 255, 3, 0, 0x000000, 0)
  UI.setup.icon_bar2 = make_panel(root, 244, 36, 36, 6, 0x22D3EE, 255, 3, 0, 0x000000, 0)
  UI.setup.icon_dot = make_panel(root, 258, 51, 10, 10, 0x22D3EE, 255, 5, 0, 0x000000, 0)
end

local function build_setup_ui()
  UI.setup.glow = make_panel(root, 216, -42, 132, 132, 0x22D3EE, 42, 66, 0, 0x000000, 0)
  UI.setup.badge = make_panel(root, 16, 14, 78, 22, 0xFFFFFF, 16, 11, 1, 0xFFFFFF, 46)
  UI.setup.badge_text = make_label(UI.setup.badge, 0, 3, 78, 16, "等待配网", 0xBFF7FF, FONT_SMALL, LV_TEXT_ALIGN_CENTER)

  add_wifi_mark()

  UI.setup.title = make_label(root, 16, 48, 210, 28, "WiFi 配网", 0xFFFFFF, FONT_TITLE, LV_TEXT_ALIGN_LEFT)
  UI.setup.subtitle = make_label(root, 16, 76, 288, 54, "1. 手机或 PC 连接 " .. SETUP_SSID .. "\n2. 等待自动弹出控制网页\n   或输入 " .. SETUP_PORTAL, 0xD1D5DB, FONT_BODY, LV_TEXT_ALIGN_LEFT)

  UI.setup.card = make_panel(root, 16, 134, 288, 46, 0xFFFFFF, 16, 8, 1, 0xFFFFFF, 36)
  UI.setup.card_label = make_label(UI.setup.card, 12, 7, 80, 14, "热点 / 地址", 0x8A8F98, FONT_SMALL, LV_TEXT_ALIGN_LEFT)
  UI.setup.ssid = make_label(UI.setup.card, 12, 23, 140, 18, SETUP_SSID, 0xFFFFFF, FONT_SMALL, LV_TEXT_ALIGN_LEFT)
  UI.setup.portal = make_label(UI.setup.card, 154, 23, 120, 18, SETUP_PORTAL, 0x67E8F9, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)

  UI.setup.note = make_label(root, 16, 184, 288, 28, "天气、股票等功能需要联网使用。", 0x9298A2, FONT_SMALL, LV_TEXT_ALIGN_LEFT)

  UI.setup.skip_btn = lv_btn_create(root)
  lv_obj_set_pos(UI.setup.skip_btn, 96, 218)
  lv_obj_set_size(UI.setup.skip_btn, 128, 18)
  style_panel(UI.setup.skip_btn, 0xFFFFFF, 255, 9, 0, 0x000000, 0)
  UI.setup.skip_text = make_label(UI.setup.skip_btn, 0, 2, 128, 14, "按 HOME 键返回", 0x000000, FONT_SMALL, LV_TEXT_ALIGN_CENTER)

  pcall(function()
    lv_obj_add_event_cb(UI.setup.skip_btn, function()
      leave_app()
    end, LV_EVENT_CLICKED, nil)
  end)
end

local function build_success_ui()
  UI.success.green_glow = make_panel(root, 92, -58, 170, 170, 0x22C55E, 42, 85, 0, 0x000000, 0)
  UI.success.cyan_glow = make_panel(root, 224, 124, 116, 116, 0x22D3EE, 30, 58, 0, 0x000000, 0)
  UI.success.badge = make_panel(root, 16, 14, 82, 22, 0x22C55E, 36, 11, 1, 0x22C55E, 118)
  UI.success.badge_text = make_label(UI.success.badge, 0, 3, 82, 16, "设备已联网", 0xBBF7D0, FONT_SMALL, LV_TEXT_ALIGN_CENTER)

  UI.success.ring = make_panel(root, 132, 27, 56, 56, 0x16A34A, 255, 28, 2, 0x86EFAC, 184)
  UI.success.ok = make_label(root, 132, 41, 56, 24, "OK", 0xFFFFFF, FONT_TITLE, LV_TEXT_ALIGN_CENTER)

  if lv_img_create and lv_img_set_src then
    UI.success.title = lv_img_create(root)
    lv_obj_set_pos(UI.success.title, 30, 84)
    local ok = pcall(function()
      lv_img_set_src(UI.success.title, SUCCESS_TITLE_PATH)
    end)
    if not ok then
      safe_set_hidden(UI.success.title, true)
      UI.success.title = make_label(root, 0, 91, 320, 30, "设备已联网", 0xFFFFFF, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
    end
  else
    UI.success.title = make_label(root, 0, 91, 320, 30, "设备已联网", 0xFFFFFF, FONT_SMALL, LV_TEXT_ALIGN_CENTER)
  end
  UI.success.subtitle = make_label(root, 16, 119, 288, 30, "现在可以使用以下域名\n进入设备控制页面", 0xB8BEC8, FONT_SMALL, LV_TEXT_ALIGN_CENTER)

  UI.success.card = make_panel(root, 16, 153, 288, 48, 0xFFFFFF, 16, 8, 1, 0xFFFFFF, 36)
  UI.success.card_label = make_label(UI.success.card, 12, 7, 90, 14, "域名 / IP", 0x8A8F98, FONT_SMALL, LV_TEXT_ALIGN_LEFT)
  UI.success.host = make_label(UI.success.card, 12, 23, 158, 18, DEVICE_HOST, 0xFFFFFF, FONT_SMALL, LV_TEXT_ALIGN_LEFT)
  UI.success.ip = make_label(UI.success.card, 174, 23, 100, 18, "获取 IP", 0x67E8F9, FONT_SMALL, LV_TEXT_ALIGN_RIGHT)

  UI.success.done_btn = lv_btn_create(root)
  lv_obj_set_pos(UI.success.done_btn, 96, 218)
  lv_obj_set_size(UI.success.done_btn, 128, 18)
  style_panel(UI.success.done_btn, 0xFFFFFF, 255, 9, 0, 0x000000, 0)
  UI.success.done_text = make_label(UI.success.done_btn, 0, 2, 128, 14, "按 HOME 键返回", 0x000000, FONT_SMALL, LV_TEXT_ALIGN_CENTER)

  pcall(function()
    lv_obj_add_event_cb(UI.success.done_btn, function()
      leave_app()
    end, LV_EVENT_CLICKED, nil)
  end)
end

local function build_ui()
  UI.bg = make_panel(root, 0, 0, SCREEN_W, SCREEN_H, 0x000000, 255, 0, 0, 0x000000, 0)
  build_setup_ui()
  build_success_ui()
end

init_fonts()
build_ui()
show_setup()
check_network()

STATE.poll_timer = tmr.create()
STATE.poll_timer:alarm(1200, tmr.ALARM_AUTO, function()
  check_network()
end)

key.on(key.HOME, function(evt_type, ts_ms)
  if evt_type == key.SHORT or evt_type == key.START then
    leave_app()
  end
end)
