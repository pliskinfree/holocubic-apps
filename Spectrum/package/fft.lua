local APP_STATE = ...
local M = {}

local math_floor = math.floor
local math_ceil = math.ceil
local math_log = math.log
local math_pow = math.pow or function(a, b) return a ^ b end
local pcall_fn = pcall
local string_sub = string.sub

local i2s_mod = rawget(_G, "i2s")
local i2s_start_fn = i2s_mod and i2s_mod.start or nil
local i2s_stop_fn = i2s_mod and i2s_mod.stop or nil
local i2s_read_fn = i2s_mod and i2s_mod.read or nil
local np_mod = rawget(_G, "np")
local np_frombuffer_fn = np_mod and np_mod.frombuffer or nil
local np_hanning_fn = np_mod and np_mod.hanning or nil
local np_multiply_fn = np_mod and np_mod.multiply or nil
local np_divide_fn = np_mod and np_mod.divide or nil
local np_fft_mod = np_mod and np_mod.fft or nil
local np_rfft_fn = np_fft_mod and np_fft_mod.rfft or nil

local MAX_V = 100

local FFT = {
  id = 0,
  sample_rate = 28000,
  n = 1024,
  read_bytes = 4096,
  bins_used = 512,
  read_wait_ms = 0,
  pcm_scale = 65536,
  freq_low_hz = 70.0,
  freq_linear_start_hz = 150.0,
  freq_mid_hz = 1400.0,
  freq_high_hz = 9000.0,
  bars = 64,
  bars_low_band = 32,
  bars_high_band = 32,
  log_mid = math_log(1400.0),
  log_high = math_log(9000.0),
  noise_floor = 0.001,
  gamma_low = 0.68,
  gamma_mid = 0.55,
  gamma_high = 0.48,
  gamma_top = 0.35,
  gamma_mid_start = 33,
  gamma_high_start = 38,
  gamma_top_start = 54,
  high_gain_start = 48,
  high_gain_max = 2.0,
  max_energy_min = 500000000.0,
  max_energy_max = 1600000000.0,
}

local fft = {
  bins = {},
  energy = {},
  count = {},
  top1 = {},
  top2 = {},
  top3 = {},
  valid_bins = {},
  valid_buckets = {},
  bucket_gamma = {},
  valid_count = 0,
  pending = "",
  window = nil,
  on_bins = nil,
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function iround(v)
  if v >= 0 then
    return math_floor(v + 0.5)
  end
  return math_ceil(v - 0.5)
end

local function has_audio_runtime()
  return i2s_mod and
    i2s_start_fn and i2s_stop_fn and i2s_read_fn and
    i2s_mod.MODE_MASTER and i2s_mod.MODE_RX and
    i2s_mod.CHANNEL_ONLY_LEFT and i2s_mod.FORMAT_I2S and
    np_frombuffer_fn and np_hanning_fn and np_multiply_fn and
    np_divide_fn and np_rfft_fn
end

local function fft_bucket_for_freq(freq)
  if freq >= FFT.freq_low_hz and freq < FFT.freq_linear_start_hz then
    return 1
  end

  if freq >= FFT.freq_linear_start_hz and freq < FFT.freq_mid_hz then
    local t = (freq - FFT.freq_linear_start_hz) / (FFT.freq_mid_hz - FFT.freq_linear_start_hz)
    return math_floor(t * (FFT.bars_low_band - 1) + 0.5) + 1
  end

  if freq >= FFT.freq_mid_hz and freq <= FFT.freq_high_hz then
    local t = (math_log(freq) - FFT.log_mid) / (FFT.log_high - FFT.log_mid)
    return FFT.bars_low_band + math_floor(t * (FFT.bars_high_band - 1) + 0.5) + 1
  end

  return nil
end

local function fft_gamma_for_bucket(bucket)
  local z = bucket - 1
  if z >= FFT.gamma_top_start then
    return FFT.gamma_top
  end
  if z >= FFT.gamma_high_start then
    return FFT.gamma_high
  end
  if z >= FFT.gamma_mid_start then
    return FFT.gamma_mid
  end
  return FFT.gamma_low
end

local function build_fft_lut()
  fft.valid_count = 0

  for i = 1, FFT.bars do
    fft.bucket_gamma[i] = fft_gamma_for_bucket(i)
  end

  for k = 1, FFT.bins_used - 1 do
    local bucket = fft_bucket_for_freq(k * FFT.sample_rate / FFT.n)
    if bucket then
      fft.valid_count = fft.valid_count + 1
      fft.valid_bins[fft.valid_count] = k
      fft.valid_buckets[fft.valid_count] = bucket
    end
  end
end

local function reset_fft_accumulators()
  for i = 1, FFT.bars do
    fft.energy[i] = 0
    fft.count[i] = 0
    fft.top1[i] = 0
    fft.top2[i] = 0
    fft.top3[i] = 0
  end
end

local function process_audio_pcm(pcm)
  if #pcm < FFT.read_bytes then
    return false
  end

  local samples = np_frombuffer_fn(pcm, "<i4", FFT.n, 0)
  np_divide_fn(samples, FFT.pcm_scale, samples)
  np_multiply_fn(samples, fft.window, samples)

  local re, im = np_rfft_fn(samples, FFT.n)
  reset_fft_accumulators()

  local valid_bins = fft.valid_bins
  local valid_buckets = fft.valid_buckets
  local valid_count = fft.valid_count
  local count_tab = fft.count
  local top1_tab = fft.top1
  local top2_tab = fft.top2
  local top3_tab = fft.top3

  for n = 1, valid_count do
    local k = valid_bins[n]
    local idx = k + 1
    local real = re[idx] or 0
    local imag = im[idx] or 0
    local power = real * real + imag * imag
    local bucket = valid_buckets[n]

    count_tab[bucket] = count_tab[bucket] + 1

    local top1 = top1_tab[bucket]
    local top2 = top2_tab[bucket]
    local top3 = top3_tab[bucket]

    if power > top1 then
      top3_tab[bucket] = top2
      top2_tab[bucket] = top1
      top1_tab[bucket] = power
    elseif power > top2 then
      top3_tab[bucket] = top2
      top2_tab[bucket] = power
    elseif power > top3 then
      top3_tab[bucket] = power
    end
  end

  local max_energy = 0
  local energy_tab = fft.energy
  for i = 1, FFT.bars do
    local count = count_tab[i]
    local energy = 0

    if count == 1 then
      energy = top1_tab[i]
    elseif count == 2 then
      energy = (top1_tab[i] + top2_tab[i]) * 0.5
    elseif count >= 3 then
      energy = (top1_tab[i] + top2_tab[i] + top3_tab[i]) / 3
    end

    energy_tab[i] = energy
    if energy > max_energy then
      max_energy = energy
    end
  end

  if max_energy < FFT.max_energy_min then
    max_energy = FFT.max_energy_min
  elseif max_energy > FFT.max_energy_max then
    max_energy = FFT.max_energy_max
  end

  local gamma_tab = fft.bucket_gamma
  local bins_tab = fft.bins
  local high_gain_span = FFT.bars - FFT.high_gain_start
  for i = 1, FFT.bars do
    local norm = (energy_tab[i] or 0) / max_energy
    norm = clamp(norm, 0, 1)

    if i >= FFT.high_gain_start then
      local t = high_gain_span > 0 and (i - FFT.high_gain_start) / high_gain_span or 1
      local gain = 1 + t * (FFT.high_gain_max - 1)
      norm = clamp(norm * gain, 0, 1)
    end

    local out = 0
    if norm > FFT.noise_floor then
      local x = (norm - FFT.noise_floor) / (1 - FFT.noise_floor)
      out = iround(math_pow(clamp(x, 0, 1), gamma_tab[i]) * MAX_V)
    end

    bins_tab[i] = clamp(out, 0, MAX_V)
  end

  if fft.on_bins then
    fft.on_bins(fft.bins, FFT.bars)
  end

  if APP_STATE then
    APP_STATE.audio_frame_id = (APP_STATE.audio_frame_id or 0) + 1
    if APP_STATE.audio_frame_id % 8 == 0 and collectgarbage then
      collectgarbage("step")
    end
  end

  return true
end

function M.stop()
  fft.pending = ""
  if APP_STATE and APP_STATE.audio_started and i2s_stop_fn then
    pcall_fn(i2s_stop_fn, FFT.id)
  end
  if APP_STATE then
    APP_STATE.audio_started = false
  end
end

function M.start(on_bins)
  fft.on_bins = on_bins

  if APP_STATE then
    APP_STATE.audio_started = false
    APP_STATE.audio_frame_id = 0
  end

  if not has_audio_runtime() then
    if print and APP_STATE and not APP_STATE.audio_runtime_warned then
      APP_STATE.audio_runtime_warned = true
      print("[Spectrum circle] missing i2s or np.fft")
    end
    return false
  end

  if not fft.window then
    local ok, win = pcall_fn(np_hanning_fn, FFT.n)
    if not ok then
      if print then
        print("[Spectrum circle] np.hanning failed", win)
      end
      return false
    end
    fft.window = win
  end

  pcall_fn(i2s_stop_fn, FFT.id)
  local ok, err = pcall_fn(i2s_start_fn, FFT.id, {
    mode = i2s_mod.MODE_MASTER | i2s_mod.MODE_RX,
    rate = FFT.sample_rate,
    bits = 32,
    channel = i2s_mod.CHANNEL_ONLY_LEFT,
    format = i2s_mod.FORMAT_I2S,
    buffer_count = 4,
    buffer_len = 256,
  })

  if not ok then
    if print then
      print("[Spectrum circle] i2s.start failed", err)
    end
    if APP_STATE then
      APP_STATE.audio_started = false
    end
    return false
  end

  fft.pending = ""
  if APP_STATE then
    APP_STATE.audio_started = true
  end
  return true
end

function M.poll()
  if not APP_STATE or not APP_STATE.audio_started or not i2s_read_fn then
    return false
  end

  local need = FFT.read_bytes - #fft.pending
  if need > 0 then
    local ok, chunk = pcall_fn(i2s_read_fn, FFT.id, need, FFT.read_wait_ms)
    if not ok then
      if print and not APP_STATE.audio_read_warned then
        APP_STATE.audio_read_warned = true
        print("[Spectrum circle] i2s.read failed", chunk)
      end
      M.stop()
      return false
    end

    if chunk and #chunk > 0 then
      fft.pending = fft.pending .. chunk
    end
  end

  if #fft.pending < FFT.read_bytes then
    return false
  end

  local pcm = fft.pending
  if #fft.pending > FFT.read_bytes then
    pcm = string_sub(fft.pending, 1, FFT.read_bytes)
    fft.pending = string_sub(fft.pending, FFT.read_bytes + 1)
  else
    fft.pending = ""
  end

  local ok, err = pcall_fn(process_audio_pcm, pcm)
  if not ok then
    if print and not APP_STATE.audio_fft_warned then
      APP_STATE.audio_fft_warned = true
      print("[Spectrum circle] np.fft failed", err)
    end
    return false
  end

  return true
end

build_fft_lut()
APP_STATE.start_audio = M.start
APP_STATE.stop_audio = M.stop
APP_STATE.poll_audio = M.poll

return M
