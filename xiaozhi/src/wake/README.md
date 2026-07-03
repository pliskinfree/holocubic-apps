# wake.so dynmod

`wake.so` 是 `WakeNet9s + 你好小智` 动态模块，目标模型固定为：

```text
wn9s_nihaoxiaozhi
```

本模块按 SD 卡模型资源设计，不使用 flash `model` 分区。运行时只找：

```text
/sd/apps/xiaozhi/wake/wn9s_nihaoxiaozhi/_MODEL_INFO_
```

## Lua API

```lua
local wake = require("/sd/apps/xiaozhi/wake.so")

print(wake.ENGINE)      -- WakeNet9s
print(wake.MODEL)       -- wn9s_nihaoxiaozhi
print(wake.WORD)        -- 你好小智
print(wake.MODEL_PATH)  -- /sd/apps/xiaozhi/wake

local ok, err = wake.start()
if not ok then print(err) return end

local ret = wake.selftest()
print(ret.ok, ret.detected, ret.frames)

wake.stop()
```

字段：

```text
VERSION
ENGINE
MODEL
WORD
MODEL_PATH
REAL_BACKEND
SAMPLE_RATE
```

函数：

```text
info()             -> table
start()/init()     -> true | nil, err
reset()            -> true | nil, err
selftest([chunks]) -> table
feed(pcm_string)   -> table | nil, err
stop()             -> true
```

`feed()` 接收 16 kHz、mono、signed 16-bit little-endian PCM 的 Lua 二进制字符串。为了避免固件暴露专用 wake API，连续监听可以由 Lua 用现有 `i2s.read()` 读取 PCM，再调用：

```lua
local ret, err = wake.feed(pcm)
if ret and ret.detected then
  print("wake")
end
```

## SD 模型资源

先让 ESP-IDF Component Manager 下载 `espressif/esp-sr`，然后复制 WakeNet9s 模型目录：

```powershell
cd xiaozhi/src/wake
pwsh ./build_sd_models.ps1
```

输出目录：

```text
xiaozhi/src/wake/build_sd/srmodels/wn9s_nihaoxiaozhi
```

把模型目录内文件打包到 xiaozhi app 目录后，设备上应存在：

```text
/sd/apps/xiaozhi/wake/wn9s_nihaoxiaozhi/_MODEL_INFO_
/sd/apps/xiaozhi/wake/wn9s_nihaoxiaozhi/wn9_index
/sd/apps/xiaozhi/wake/wn9s_nihaoxiaozhi/wn9_data
```

## 构建要点

`sdkconfig.defaults` 固定启用：

```text
CONFIG_MODEL_IN_SDCARD=y
CONFIG_SR_WN_WN9S_NIHAOXIAOZHI=y
```

`wake.so` 构建时通过 `espressif/esp-sr` 引入 WakeNet9s，并把 `model_path.c`、`libwakenet.a`、`libc_speech_features.a`、`libdl_lib.a`、`libhufzip.a` 以及 `esp-dsp/dl_fft` 链入 `.so`。

### 编译 wake.so

只编译动态模块，不需要全量编译主固件：

```powershell
$pio = Join-Path $env:USERPROFILE ".platformio"
$env:IDF_PATH = Join-Path $pio "packages\framework-espidf"
$env:IDF_TOOLS_PATH = $pio
$env:NINJA = Join-Path $pio "packages\tool-ninja\ninja.exe"
$env:CMAKE_MAKE_PROGRAM = $env:NINJA
$env:PATH = (Join-Path $pio "packages\tool-cmake\bin") + ";" +
            (Join-Path $pio "packages\tool-ninja") + ";" +
            (Join-Path $pio "packages\toolchain-xtensa-esp-elf\bin") + ";" +
            (Join-Path $pio "python_env\idf5.5_py3.11_env\Scripts") + ";" +
            (Join-Path $pio "penv\Scripts") + ";" + $env:PATH

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$build = "E:\cubicsrc\APPS\xiaozhi_wake_build"

cmake -S . -B $build -G Ninja -DIDF_TARGET=esp32s3
cmake --build $build --target so --config Release
```

Windows 下建议把 build 目录放到纯 ASCII 路径，避免 Xtensa 工具链处理中文路径时输出乱码或链接失败。

如果只改了 `wake_so.ld`，Ninja 可能不会自动感知 linker script 依赖；先删旧产物再构建：

```powershell
Remove-Item -LiteralPath (Join-Path $build "wake.so") -Force -ErrorAction SilentlyContinue
cmake --build $build --target so --config Release
```

构建完成后产物在：

```text
E:\cubicsrc\APPS\xiaozhi_wake_build\wake.so
```

检查段布局时应看到没有独立 `.mod_iram`，`.iram1*` 已合并进 `.text`：

```powershell
& (Join-Path $pio "packages\toolchain-xtensa-esp-elf\bin\xtensa-esp32s3-elf-readelf.exe") -S --wide (Join-Path $build "wake.so")
```

### 上传和验证

通过设备 DevTools 上传到 SD 卡模块目录：

```powershell
$base = "http://192.168.31.200"
$path = "E:\cubicsrc\APPS\xiaozhi_wake_build\wake.so"
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path))
$total = $bytes.Length
$uri = "$base/devtools/api/upload?path=/sd/apps/xiaozhi/wake.so&offset=0&total=$total"
$req = [System.Net.HttpWebRequest]::Create($uri)
$req.Method = "PUT"
$req.ContentType = "application/octet-stream"
$req.ContentLength = $total
$stream = $req.GetRequestStream()
$stream.Write($bytes, 0, $bytes.Length)
$stream.Close()
$resp = $req.GetResponse()
$reader = [IO.StreamReader]::new($resp.GetResponseStream())
$reader.ReadToEnd()
$reader.Close()
$resp.Close()
```

可用 `wake_probe.lua` 临时替换 `/sd/apps/dynmod_probe/main.lua` 后启动 `dynmod_probe` 验证。验证成功时结果里应看到：

```text
[wake-probe] start true nil
[wake-probe] selftest pcall true
[wake-probe][selftest] ok=true
[wake-probe][selftest] frames=4
[wake-probe] stop true nil
```

测试后记得恢复原 `/sd/apps/dynmod_probe/main.lua`，避免把 dynmod 测试 app 长期指向 wake probe。

### `.mod_iram` IllegalInstruction 问题

关键改动在 `wake_so.ld` 的 `.text` 输出段：把原来单独输出的 `.mod_iram` 合并进连续 `.text`，也就是把 `.iram1.literal*` 和 `.iram1*` 放在 `.text` 最前面。

原因是 ESP-SR 内部有 `.text -> .mod_iram` 的 Xtensa 直接 `call8`。这类调用在链接 `.so` 时已经被固化为相对跳转，运行时 ELF loader 不会重写这些指令；loader 只会处理 relocation 表里的符号和数据表函数指针。如果 `.iram1*` 被输出成独立 `.mod_iram` 并由 loader 复制到 IRAM，`.text` 内部的直接 `call8` 仍会跳向 `text_base + .mod_iram_vaddr`，那个位置不是实际 IRAM 函数正文，最终会触发 `IllegalInstruction`。

当前处理方式是模块侧规避：不要生成独立 `.mod_iram`，让 ESP-SR 热点代码和普通代码一起进入同一个连续 `.text`，保持直接 `call8` 的链接结果和运行时布局一致。这会牺牲一点 IRAM 热点优化，但可以保证 `wake.selftest()` 和真实 `detect()` 调用链稳定运行。

如果以后要重新把热点代码放回 IRAM，需要从 loader 侧处理：支持 `.text` 到 `.mod_iram` 的直接调用重定位，或在 `.text` 中生成可被固定相对调用命中的 trampoline，再跳转到实际 IRAM 地址。否则不要恢复独立 `.mod_iram` 输出段。

## Arduino 使用是否相同

Lua 侧保持低学习成本，接近 Arduino/NodeMCU 的风格：

```lua
wake.start()
wake.feed(pcm)
wake.stop()
```

但底层不是 Arduino 官方类。原因是 `.so` 跨 ABI 不能安全传递 `String`、`File`、I2S 对象这类 C++ 实例，所以模块只拿普通 C ABI、Lua 二进制字符串和 SD 路径。

## selftest 说明

`wake.selftest()` 会在 `.so` 内部生成一段 16 kHz s16 PCM 并喂给 WakeNet9s。它用于验证模型加载和 `detect()` 调用链，不是“你好小智”真实录音，真后端下正常情况下不会唤醒。
