-- ui.lua - Music Player UI
-- LVGL rendering, layout, touch handling, and UI-owned fonts.

return function(APP)

-- Shared references from main.
local C                   = APP.C
local MAIN_STYLE          = APP.MAIN_STYLE
local FONT_10             = APP.FONT_10
local FONT_12             = APP.FONT_12
local FONT_14             = APP.FONT_14
local ALIGN_CENTER        = APP.ALIGN_CENTER
local LABEL_LONG_CLIP     = APP.LABEL_LONG_CLIP
local CANVAS_FMT          = APP.CANVAS_FMT
local EVENT_CLICKED       = APP.EVENT_CLICKED
local FLAG_CLICKABLE      = APP.FLAG_CLICKABLE
local LV_LAYOUT_NONE_VALUE = APP.LV_LAYOUT_NONE_VALUE

local LYRIC_OFFSETS       = APP.LYRIC_OFFSETS
local LYRIC_CENTER_Y      = APP.LYRIC_CENTER_Y
local LYRIC_LINE_SPACE    = APP.LYRIC_LINE_SPACE or 4
local LYRIC_SMALL_LINE_H  = APP.LYRIC_SMALL_LINE_H or 17
local LYRIC_ACTIVE_LINE_H = APP.LYRIC_ACTIVE_LINE_H or 21

local call                = APP._call
local text_or             = APP._text_or
local clamp               = APP._clamp
local elapsed_ms          = APP._elapsed_ms
local current_track       = APP._current_track
local next_track          = APP._next_track
local toggle_play         = APP._toggle_play
local asset               = APP._asset
local lyric_text_at       = APP._lyric_text_at
local lyric_scroll_px     = APP._lyric_scroll_px
local profile_now_us      = APP._profile_now_us
local profile_elapsed_us  = APP._profile_elapsed_us
local prof_add            = APP._prof_add
local maybe_log_profile   = APP._maybe_log_profile

local UI = APP.ui
local S  = APP.state

C.bg = 0x000000
C.text = 0xFFFFFF
C.sub = 0x9CA3AF
C.faint = 0x6B7280
C.line = 0x2A2A2A
C.accent = 0xFFFFFF

local BLUE = 0x2F80FF
local BLUE_DARK = 0x155EEF
local CONTROL_CENTER_Y = 219
local CONTROL_SIDE_SIZE = 30
local CONTROL_PLAY_SIZE = 35
local LYRIC_X = 24
local LYRIC_Y = 58
local LYRIC_W = 272
local LYRIC_H = 128
local PROGRESS_X = 42
local PROGRESS_Y = 192
local PROGRESS_W = 236
local PROGRESS_H = 4

-- ==================================================================
--  LVGL low-level helpers
-- ==================================================================

local function reset_obj(id)
  if not id then return end
  call(rawget(_G, "lv_obj_remove_style_all"), id)
  call(lv_obj_set_style_bg_opa, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_border_width, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_pad_all, id, 0, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, id, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function style_label(id, font, color, align, opa)
  if not id then return end
  call(lv_obj_set_style_text_font, id, font or FONT_12, MAIN_STYLE)
  call(lv_obj_set_style_text_color, id, color or C.text, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_opa"), id, opa or 255, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_align"), id, align or ALIGN_CENTER, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_letter_space"), id, 0, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_text_line_space"), id, LYRIC_LINE_SPACE, MAIN_STYLE)
end

local function track_event(obj, dsc)
  if dsc then
    APP.events[#APP.events + 1] = { obj = obj, dsc = dsc }
  end
end

local function set_label(id, text)
  if id and lv_label_set_text then
    pcall(function()
      lv_label_set_text(id, text_or(text, ""))
    end)
  end
end

local function label(parent, x, y, w, h, text, font, color, align)
  local id = lv_label_create(parent)
  reset_obj(id)
  call(lv_obj_set_pos, id, x, y)
  call(lv_obj_set_width, id, w)
  if h and lv_obj_set_height then call(lv_obj_set_height, id, h) end
  if lv_label_set_long_mode and LABEL_LONG_CLIP then
    call(lv_label_set_long_mode, id, LABEL_LONG_CLIP)
  end
  style_label(id, font, color, align)
  set_label(id, text)
  return id
end

local function style_box(id, bg, border, radius, opa)
  if not id then return end
  call(lv_obj_set_style_bg_color, id, bg or 0xFFFFFF, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, id, opa or 255, MAIN_STYLE)
  call(lv_obj_set_style_border_width, id, border and 1 or 0, MAIN_STYLE)
  if border then
    call(lv_obj_set_style_border_color, id, border, MAIN_STYLE)
  end
  call(lv_obj_set_style_radius, id, radius or 0, MAIN_STYLE)
end

local function make_control(parent, x, y, w, h, text, primary)
  local id = (lv_btn_create and lv_btn_create(parent)) or (lv_obj_create and lv_obj_create(parent))
  if not id then return nil end
  reset_obj(id)
  call(lv_obj_set_pos, id, x, y)
  call(lv_obj_set_size, id, w, h)
  style_box(id, primary and BLUE or 0x111827, primary and BLUE_DARK or 0x374151, math.floor(h / 2), 245)
  call(rawget(_G, "lv_obj_set_style_shadow_width"), id, primary and 10 or 4, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_shadow_opa"), id, primary and 90 or 55, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_shadow_color"), id, primary and BLUE_DARK or 0x000000, MAIN_STYLE)

  local text_color = primary and 0xFFFFFF or 0xE5E7EB
  local child = label(id, 0, math.floor((h - 18) / 2), w, 18, text, FONT_14, text_color, ALIGN_CENTER)
  UI.control_labels = UI.control_labels or {}
  UI.control_labels[id] = child
  return id, child
end

local function make_icon_control(parent, center_x, center_y, icon_src, icon_size)
  local id = (lv_btn_create and lv_btn_create(parent)) or (lv_obj_create and lv_obj_create(parent))
  if not id then return nil end
  icon_size = icon_size or CONTROL_SIDE_SIZE
  reset_obj(id)
  local x = math.floor(center_x - icon_size / 2)
  local y = math.floor(center_y - icon_size / 2)
  call(lv_obj_set_pos, id, x, y)
  call(lv_obj_set_size, id, icon_size, icon_size)
  call(lv_obj_set_style_bg_opa, id, 0, MAIN_STYLE)
  call(lv_obj_set_style_border_width, id, 0, MAIN_STYLE)
  call(rawget(_G, "lv_obj_set_style_shadow_width"), id, 0, MAIN_STYLE)

  local icon = lv_img_create and lv_img_create(id)
  if icon then
    reset_obj(icon)
    call(lv_obj_set_pos, icon, 0, 0)
    call(lv_obj_set_size, icon, icon_size, icon_size)
    call(lv_img_set_src, icon, icon_src)
    if lv_img_set_antialias then call(lv_img_set_antialias, icon, true) end
  end
  return id, icon
end

local function show_loading(status)
  if not lv_scr_act or not lv_obj_clean or not lv_label_create then return end
  local root = lv_scr_act()
  call(lv_obj_clean, root)
  UI.root = root
  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)
  if lv_obj_clear_flag and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    call(lv_obj_clear_flag, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end

  UI.loading_title = label(root, 0, 86, APP.SCREEN_W, 28, "Music", FONT_14, C.text, ALIGN_CENTER)
  UI.loading_status = label(root, 0, 118, APP.SCREEN_W, 20, status or "Loading", FONT_12, C.sub, ALIGN_CENTER)
  if lv_obj_create then
    UI.loading_line = lv_obj_create(root)
    reset_obj(UI.loading_line)
    call(lv_obj_set_pos, UI.loading_line, 122, 150)
    call(lv_obj_set_size, UI.loading_line, 76, 1)
    style_box(UI.loading_line, C.line, nil, 0, 255)
  end
end

local function set_loading_status(status)
  if UI.loading_status then
    set_label(UI.loading_status, status or "Loading")
  end
end

-- ==================================================================
--  Font management
-- ==================================================================

local function load_font(path, fallback)
  if not lv_font_load then return fallback end
  local ok, handle = pcall(function()
    return lv_font_load(path)
  end)
  if ok and type(handle) == "number" and handle > 0 then
    APP.font_handles[#APP.font_handles + 1] = handle
    return handle
  end
  return fallback
end

local function release_fonts()
  if lv_font_free then
    for _, handle in ipairs(APP.font_handles) do
      pcall(function() lv_font_free(handle) end)
    end
  end
  APP.font_handles = {}
end

-- ==================================================================
--  Lyric rendering
-- ==================================================================

local function lyric_line_count(text)
  local wrapped = text_or(text, "")
  if wrapped == "" then return 0, wrapped end
  local count = 1
  local pos = 1
  while true do
    local found = wrapped:find("\n", pos, true)
    if not found then break end
    count = count + 1
    pos = found + 1
  end
  return count, wrapped
end

local function lyric_slot_height(text, active)
  local lines, wrapped = lyric_line_count(text)
  if lines <= 0 then return 0, wrapped end
  local line_h = active and LYRIC_ACTIVE_LINE_H or LYRIC_SMALL_LINE_H
  return lines * line_h + (lines - 1) * LYRIC_LINE_SPACE, wrapped
end

local function lyric_slot_step(slot)
  local h = slot and slot.h or 0
  if h <= 0 then return 0 end
  return h + LYRIC_LINE_SPACE
end

local function lyric_active_y(slot, scroll)
  local h = slot and slot.h or LYRIC_ACTIVE_LINE_H
  if h <= 0 then h = LYRIC_ACTIVE_LINE_H end
  return LYRIC_CENTER_Y - math.floor((h - LYRIC_ACTIVE_LINE_H) / 2) - (scroll or 0)
end

local function lyric_initial_y(rel)
  if rel == 0 then return LYRIC_CENTER_Y end
  if rel < 0 then
    return LYRIC_CENTER_Y + rel * (LYRIC_SMALL_LINE_H + LYRIC_LINE_SPACE)
  end
  return LYRIC_CENTER_Y + LYRIC_ACTIVE_LINE_H + LYRIC_LINE_SPACE + (rel - 1) * (LYRIC_SMALL_LINE_H + LYRIC_LINE_SPACE)
end

local function set_lyric_slot(slot, text, y, active, opa)
  if not slot then return end
  local h, wrapped = lyric_slot_height(text, active)
  call(lv_obj_set_pos, slot, UI.lyric_slot_x or 0, (UI.lyric_slot_y or 0) + y)
  if lv_obj_set_height then
    call(lv_obj_set_height, slot, math.max(1, h))
  end
  style_label(slot, active and (APP.font_big or APP.font_cn) or APP.font_cn, active and C.text or C.sub, ALIGN_CENTER, opa)
  set_label(slot, wrapped)
end

local function render_message_lyrics(text)
  if not UI.lyric_labels then return end
  for i, slot in ipairs(UI.lyric_labels) do
    if i == 3 then
      local h = lyric_slot_height(text, true)
      set_lyric_slot(slot, text, lyric_active_y({ h = h }, 0), true, 255)
    else
      set_lyric_slot(slot, "", lyric_initial_y(i - 3), false, 0)
    end
  end
end

local function render_lyric_window(track, ms)
  if not UI.lyric_labels then return end

  if S.error ~= "" then
    render_message_lyrics(S.error)
    return
  end

  local lines = S.lyrics
  if not lines or #lines == 0 then
    render_message_lyrics("No lyrics")
    return
  end

  lyric_text_at(ms)
  local slots = {}
  local active_i = 1
  for i, rel in ipairs(LYRIC_OFFSETS) do
    local line = lines[S.lyric_idx + rel]
    local active = rel == 0
    local text = line and line.text or ""
    local h = lyric_slot_height(text, active)
    local opa = active and 255 or (math.abs(rel) >= 2 and 135 or 190)
    slots[i] = { text = text, active = active, opa = opa, h = h }
    if active then active_i = i end
  end

  local active_slot = slots[active_i]
  local scroll = lyric_scroll_px(ms, lyric_slot_step(active_slot))
  active_slot.y = lyric_active_y(active_slot, scroll)
  for i = active_i - 1, 1, -1 do
    slots[i].y = slots[i + 1].y - lyric_slot_step(slots[i])
  end
  for i = active_i + 1, #slots do
    slots[i].y = slots[i - 1].y + lyric_slot_step(slots[i - 1])
  end

  for i, info in ipairs(slots) do
    set_lyric_slot(UI.lyric_labels[i], info.text, info.y, info.active, info.opa)
  end
end

-- ==================================================================
--  Canvas helpers (optional progress bar)
-- ==================================================================

local function canvas_begin(id)
  local begin_fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
  if begin_fn then
    local ok = pcall(function() begin_fn(id) end)
    return ok
  end
  return false
end

local function canvas_end(id, explicit)
  local end_fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
  if explicit and end_fn then
    pcall(function() end_fn(id) end)
  elseif lv_obj_invalidate then
    pcall(function() lv_obj_invalidate(id) end)
  end
end

local function draw_visual()
  if not APP.USE_CANVAS_PROGRESS then return end
  if not UI.canvas or not lv_canvas_fill_bg then return end
  local explicit = canvas_begin(UI.canvas)
  lv_canvas_fill_bg(UI.canvas, C.bg, 255)

  local dur = tonumber(S.duration_ms) or 0
  lv_canvas_draw_line(UI.canvas, 14, 8, 306, 8, C.line, 255, 3)
  if dur > 0 then
    local p = clamp(elapsed_ms() / dur, 0, 1)
    lv_canvas_draw_line(UI.canvas, 14, 8, 14 + math.floor(292 * p), 8, C.accent, 255, 3)
  end
  canvas_end(UI.canvas, explicit)
end

-- ==================================================================
--  Play / pause icon
-- ==================================================================

local function refresh_play_icon()
  if UI.play_label then
    set_label(UI.play_label, S.playing and "PAUSE" or "PLAY")
  elseif UI.play_icon_small and lv_img_set_src then
    call(lv_img_set_src, UI.play_icon_small, asset(S.playing and "pause_small.png" or "play_small.png"))
  end
end

local function refresh_progress()
  if not UI.progress_fill then return end
  local dur = tonumber(S.duration_ms) or 0
  local ratio = 0
  if dur > 0 then
    ratio = clamp(elapsed_ms() / dur, 0, 1)
  end
  local w = math.max(1, math.floor(PROGRESS_W * ratio))
  if lv_obj_set_size then
    call(lv_obj_set_size, UI.progress_fill, w, PROGRESS_H)
  else
    call(lv_obj_set_width, UI.progress_fill, w)
  end
end

-- ==================================================================
--  Main render tick
-- ==================================================================

local function render_ui()
  if not APP.running then return end
  local ui_start = APP.PROFILE_AUDIO and profile_now_us and profile_now_us() or 0
  local function finish_ui_profile()
    if APP.PROFILE_AUDIO and profile_elapsed_us and prof_add then
      prof_add("ui", profile_elapsed_us(ui_start), 0)
      if maybe_log_profile then
        maybe_log_profile()
      end
    end
  end

  local track = current_track()
  if not track then
    set_label(UI.title, "NO MUSIC")
    render_message_lyrics("Put music in /sd/mp3")
    refresh_play_icon()
    draw_visual()
    finish_ui_profile()
    return
  end

  set_label(UI.title, track.title)
  refresh_play_icon()
  refresh_progress()

  render_lyric_window(track, elapsed_ms())
  draw_visual()
  finish_ui_profile()
end

-- ==================================================================
--  Build the screen
-- ==================================================================

local function build_ui()
  local root = lv_scr_act()
  if lv_obj_clean then
    call(lv_obj_clean, root)
  end
  UI.root = root
  if lv_obj_set_layout then call(lv_obj_set_layout, root, LV_LAYOUT_NONE_VALUE) end
  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)

  if lv_img_create then
    UI.bg_img = lv_img_create(root)
    reset_obj(UI.bg_img)
    call(lv_obj_set_pos, UI.bg_img, 0, 0)
    call(lv_img_set_src, UI.bg_img, asset("bg_anime.png"))
  end

  UI.title = label(root, LYRIC_X, 20, LYRIC_W, 30, "Music", APP.font_big or APP.font_cn, C.text, ALIGN_CENTER)

  local lyric_parent = root
  UI.lyric_slot_x = LYRIC_X
  UI.lyric_slot_y = LYRIC_Y
  UI.lyric_slot_w = LYRIC_W
  if lv_obj_create then
    UI.lyric_panel = lv_obj_create(root)
    reset_obj(UI.lyric_panel)
    call(lv_obj_set_pos, UI.lyric_panel, LYRIC_X, LYRIC_Y)
    call(lv_obj_set_size, UI.lyric_panel, LYRIC_W, LYRIC_H)
    lyric_parent = UI.lyric_panel
    UI.lyric_slot_x = 0
    UI.lyric_slot_y = 0
  end
  UI.lyric_labels = {}
  for i, rel in ipairs(LYRIC_OFFSETS) do
    UI.lyric_labels[i] = label(lyric_parent, UI.lyric_slot_x, UI.lyric_slot_y + lyric_initial_y(rel), UI.lyric_slot_w or LYRIC_W, LYRIC_SMALL_LINE_H, "", APP.font_cn, C.sub, ALIGN_CENTER)
  end

  UI.prev_icon = nil
  UI.play_icon = nil
  UI.next_icon = nil
  if lv_obj_create then
    UI.progress_track = lv_obj_create(root)
    reset_obj(UI.progress_track)
    call(lv_obj_set_pos, UI.progress_track, PROGRESS_X, PROGRESS_Y)
    call(lv_obj_set_size, UI.progress_track, PROGRESS_W, PROGRESS_H)
    style_box(UI.progress_track, 0x1F2937, nil, 2, 255)

    UI.progress_fill = lv_obj_create(root)
    reset_obj(UI.progress_fill)
    call(lv_obj_set_pos, UI.progress_fill, PROGRESS_X, PROGRESS_Y)
    call(lv_obj_set_size, UI.progress_fill, 1, PROGRESS_H)
    style_box(UI.progress_fill, BLUE, nil, 2, 255)
  end

  UI.prev_btn, UI.prev_icon_small = make_icon_control(root, 105, CONTROL_CENTER_Y, asset("prev_small.png"), CONTROL_SIDE_SIZE)
  UI.play_label = nil
  UI.play_btn, UI.play_icon_small = make_icon_control(root, 160, CONTROL_CENTER_Y, asset(S.playing and "pause_small.png" or "play_small.png"), CONTROL_PLAY_SIZE)
  UI.next_btn, UI.next_icon_small = make_icon_control(root, 215, CONTROL_CENTER_Y, asset("next_small.png"), CONTROL_SIDE_SIZE)
  refresh_progress()

  if APP.USE_CANVAS_PROGRESS then
    UI.canvas = lv_canvas_create(root, APP.SCREEN_W, 16, CANVAS_FMT)
    call(lv_obj_set_pos, UI.canvas, 0, 224)
    draw_visual()
  end
end

-- ==================================================================
--  Touch / click binding
-- ==================================================================

local function bind_touch()
  if not lv_obj_add_event_cb or not EVENT_CLICKED then return end

  local function make_clickable(id, fn)
    if not id then return end
    if lv_obj_add_flag and FLAG_CLICKABLE then
      call(lv_obj_add_flag, id, FLAG_CLICKABLE)
    end
    track_event(id, lv_obj_add_event_cb(id, function(_)
      fn()
      render_ui()
    end, EVENT_CLICKED, "music-control"))
  end

  make_clickable(UI.prev_btn or UI.prev_icon, function() next_track(-1) end)
  make_clickable(UI.play_btn or UI.play_icon, toggle_play)
  make_clickable(UI.next_btn or UI.next_icon, function() next_track(1) end)
end

-- ==================================================================
--  Wire exports back to APP so main can call them
-- ==================================================================

APP._ui_load_font    = load_font
APP._ui_release_fonts = release_fonts
APP._ui_build        = build_ui
APP._ui_render       = render_ui
APP._ui_bind_touch   = bind_touch
APP._ui_show_loading = show_loading
APP._ui_set_loading_status = set_loading_status

end  -- return function(APP)
