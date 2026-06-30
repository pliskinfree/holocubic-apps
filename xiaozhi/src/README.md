# xiaozhi.so dynmod

`xiaozhi.so` 是给小智第一版移植使用的语音核心动态模块。它只负责 Opus 编解码和播放输出，不负责 WiFi、WebSocket、LVGL UI、唤醒词检测。

Lua 侧建议分工：

- `wake.so`：离线唤醒。
- `websocket`/`sjson`：小智协议和联网。
- `xiaozhi.so`：PCM/Opus 转换和 TTS 播放。
- Lua LVGL app：状态、字幕、错误提示和配置页。

## Lua API

```lua
local mod = require("/sd/apps/xiaozhi/xiaozhi.so")

local xz = mod.xz      -- 也会注册到全局 xz
local voice = mod.voice -- 也会注册到全局 voice

local ok, err = voice.start({
  rate = 16000,
  channels = 1,
  frame_ms = 60,
  bitrate = 24000,
  complexity = 5,
  tx = true,
  rx = true,
  hold_audio = true, -- 默认 true；启动时占用 speaker I2S
})
if not ok then print(err) return end

local opus, enc_err = voice.encode(pcm16)  -- PCM -> Opus
local pcm, dec_err = voice.decode(opus)    -- Opus -> PCM
voice.play(opus, "opus")                   -- 解码后写 host audio
voice.play(pcm, "pcm")                     -- 直接播放 PCM
voice.stop()
```

小智会话薄封装：

```lua
xz.open({
  rate = 16000,
  channels = 1,
  frame_ms = 60,
  tx = true,
  rx = true,
})

local opus = xz.send_pcm(pcm16)
xz.on_binary(server_opus)
xz.close()
```

`voice.encode()` 第一版要求输入刚好是一帧 PCM：`rate * frame_ms / 1000 * channels * 2` 字节。默认 `16 kHz / mono / 60 ms` 时是一帧 `1920` 字节。

`voice.start()` 默认会打开 host audio，占用 speaker I2S TX；如果当前 I2S 已被别的 app/模块占用，会返回 `nil, "voice.start: audio output busy or unavailable"`，Lua UI 可以直接弹出启动失败。调试纯编解码时可传 `hold_audio = false` 或 `audio = false`，此时 `voice.play()` 会在首次播放时再尝试打开输出。

当前主固件 I2S 层全局互斥，Lua app 应在进入小智前释放其它 I2S 使用者；`voice.stop()` / `xz.close()` 会释放 speaker 输出。

## 构建

本模块放在 `xiaozhi/src`，使用 ESP-IDF managed component：

```text
78/esp-opus
espressif/elf_loader
```

只构建动态模块，不需要全量编译主固件：

```powershell
$pio = Join-Path $env:USERPROFILE ".platformio"
$env:IDF_PATH = Join-Path $pio "packages\framework-espidf"
$env:IDF_TOOLS_PATH = $pio
$env:NINJA = Join-Path $pio "packages\tool-ninja\ninja.exe"
$env:CMAKE_MAKE_PROGRAM = $env:NINJA
$env:PATH = (Join-Path $pio "packages\tool-cmake\bin") + ";" +
            (Join-Path $pio "packages\tool-ninja") + ";" +
            (Join-Path $pio "packages\toolchain-xtensa-esp-elf\bin") + ";" +
            (Join-Path $pio "penv\Scripts") + ";" + $env:PATH

$env:CUBICLUA_ROOT="E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop"
cmake -S . -B build -G Ninja -DIDF_TARGET=esp32s3
cmake --build build --target so --config Release
```

产物：

```text
xiaozhi/src/build/xiaozhi.so
```

## 上传

当前 Lua app 从 app 本地目录加载动态模块：

```text
/sd/apps/xiaozhi/xiaozhi.so
```

更新模块时可替换 `package/xiaozhi.so` 后重新部署 `package/`，或直接用 DevTools
`/devtools/api/upload` 以二进制 PUT 上传到上述路径。`wake.so` 同样保留在
`/sd/apps/xiaozhi/wake.so`。
