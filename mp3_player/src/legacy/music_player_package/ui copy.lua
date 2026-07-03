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
local LYRIC_GAP           = APP.LYRIC_GAP
local LYRIC_CENTER_Y      = APP.LYRIC_CENTER_Y

local call                = APP._call
local text_or             = APP._text_or
local clamp               = APP._clamp
local elapsed_ms          = APP._elapsed_ms
local current_track       = APP._current_track
local next_track          = APP._next_track
local toggle_play         = APP._toggle_play
local asset               = APP._asset
local demo_icon_src       = APP._demo_icon_src
local lyric_text_at       = APP._lyric_text_at
local lyric_scroll_px     = APP._lyric_scroll_px
local profile_now_us      = APP._profile_now_us
local profile_elapsed_us  = APP._profile_elapsed_us
local prof_add            = APP._prof_add
local maybe_log_profile   = APP._maybe_log_profile

local UI = APP.ui
local S  = APP.state

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
  call(rawget(_G, "lv_obj_set_style_text_line_space"), id, 1, MAIN_STYLE)
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

local function set_lyric_slot(slot, text, y, active, opa)
  if not slot then return end
  call(lv_obj_set_pos, slot, UI.lyric_slot_x or 0, (UI.lyric_slot_y or 0) + y)
  style_label(slot, active and (APP.font_big or APP.font_cn) or APP.font_cn, active and C.text or C.sub, ALIGN_CENTER, opa)
  set_label(slot, text)
end

local function render_message_lyrics(text)
  if not UI.lyric_labels then return end
  for i, slot in ipairs(UI.lyric_labels) do
    if i == 3 then
      set_lyric_slot(slot, text, LYRIC_CENTER_Y, true, 255)
    else
      set_lyric_slot(slot, "", LYRIC_CENTER_Y + (i - 3) * LYRIC_GAP, false, 0)
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
  local scroll = lyric_scroll_px(ms)
  for i, rel in ipairs(LYRIC_OFFSETS) do
    local line = lines[S.lyric_idx + rel]
    local y = LYRIC_CENTER_Y + rel * LYRIC_GAP - scroll
    local active = rel == 0
    local opa = active and 255 or (math.abs(rel) >= 2 and 135 or 190)
    set_lyric_slot(UI.lyric_labels[i], line and line.text or "", y, active, opa)
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
  if not UI.play_icon or not lv_img_set_src then return end
  local name = S.playing and "pause.png" or "play.png"
  call(lv_img_set_src, UI.play_icon, asset(name))
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

  if S.playing then
    S.angle = (S.angle + 34) % 3600
    if UI.disc and lv_img_set_angle then
      call(lv_img_set_angle, UI.disc, S.angle)
    end
  end

  set_label(UI.title, track.title)
  refresh_play_icon()

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
  elseif lv_clear then
    call(lv_clear)
  end
  UI.root = root
  if lv_obj_set_layout then call(lv_obj_set_layout, root, LV_LAYOUT_NONE_VALUE) end
  call(lv_obj_set_style_bg_color, root, C.bg, MAIN_STYLE)
  call(lv_obj_set_style_bg_opa, root, 255, MAIN_STYLE)

  UI.disc = lv_img_create(root)
  reset_obj(UI.disc)
  call(lv_obj_set_pos, UI.disc, 25, 38)
  call(lv_obj_set_size, UI.disc, 100, 100)
  local icon_src, using_demo_icon = demo_icon_src()
  call(lv_img_set_src, UI.disc, icon_src)
  if lv_img_set_zoom then call(lv_img_set_zoom, UI.disc, using_demo_icon and 256 or 200) end
  if lv_img_set_pivot then call(lv_img_set_pivot, UI.disc, 50, 50) end
  if lv_img_set_antialias then call(lv_img_set_antialias, UI.disc, true) end

  UI.title = label(root, 150, 10, 164, 34, "SCAN", APP.font_big or APP.font_cn, C.text, ALIGN_CENTER)

  local lyric_parent = root
  UI.lyric_slot_x = 150
  UI.lyric_slot_y = 52
  if lv_obj_create then
    UI.lyric_panel = lv_obj_create(root)
    reset_obj(UI.lyric_panel)
    call(lv_obj_set_pos, UI.lyric_panel, 150, 52)
    call(lv_obj_set_size, UI.lyric_panel, 164, 146)
    lyric_parent = UI.lyric_panel
    UI.lyric_slot_x = 0
    UI.lyric_slot_y = 0
  end
  UI.lyric_labels = {}
  for i, rel in ipairs(LYRIC_OFFSETS) do
    UI.lyric_labels[i] = label(lyric_parent, UI.lyric_slot_x, UI.lyric_slot_y + LYRIC_CENTER_Y + rel * LYRIC_GAP, 164, 24, "", APP.font_cn, C.sub, ALIGN_CENTER)
  end

  UI.prev_icon = lv_img_create(root)
  reset_obj(UI.prev_icon)
  call(lv_obj_set_pos, UI.prev_icon, 0, 163)
  call(lv_img_set_src, UI.prev_icon, asset("prev.png"))

  UI.play_icon = lv_img_create(root)
  reset_obj(UI.play_icon)
  call(lv_obj_set_pos, UI.play_icon, 46, 156)
  call(lv_img_set_src, UI.play_icon, asset("play.png"))

  UI.next_icon = lv_img_create(root)
  reset_obj(UI.next_icon)
  call(lv_obj_set_pos, UI.next_icon, 106, 163)
  call(lv_img_set_src, UI.next_icon, asset("next.png"))

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

  make_clickable(UI.prev_icon, function() next_track(-1) end)
  make_clickable(UI.play_icon, toggle_play)
  make_clickable(UI.next_icon, function() next_track(1) end)
end

-- ==================================================================
--  Wire exports back to APP so main can call them
-- ==================================================================

APP._ui_load_font    = load_font
APP._ui_release_fonts = release_fonts
APP._ui_build        = build_ui
APP._ui_render       = render_ui
APP._ui_bind_touch   = bind_touch

end  -- return function(APP)
