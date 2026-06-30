# xiaozhi Lua App

这是裁剪移植官方 `xiaozhi-esp32` 的 Lua 版应用层。底层动态模块只负责唤醒、Opus 编解码和音频播放；联网协议、状态机和 LVGL UI 放在 Lua。

## API 配置

设备端不直接填写 OpenAI / DeepSeek API Key。小智协议要求设备连接“小智服务端”，由服务端配置 ASR、LLM、TTS 的 API Key。

在 SD 卡创建：

```json
{
  "ota": {
    "url": "https://your-xiaozhi-server/xiaozhi/ota/",
    "enabled": true,
    "force": false
  },
  "websocket": {
    "url": "",
    "token": "",
    "version": 3
  },
  "wake_word": "你好小智"
}
```

路径：`/sd/apps/xiaozhi/config.json`

官方控制台 `https://xiaozhi.me/console/agents` 是网页管理页，不是设备 OTA 接口。使用官方控制台时，`ota.url` 通常填官方固件默认的 `https://api.tenclass.net/xiaozhi/ota/`；使用自建 xinnan 服务端时，填自建服务端暴露的 `/xiaozhi/ota/` 地址。

启动后如果 `websocket.url` 为空，Lua 会请求 `ota.url` 获取 6 位验证码，并在屏幕上显示。后台“添加设备”输入该验证码后，Lua 会轮询 `ota.url + activate`，绑定成功后再次请求 OTA，并把服务端下发的 `websocket.url/token/version` 写回 `config.json`。

如果你不使用后台添加设备，也可以手动填写 `websocket.url` 和 `token`，此时会跳过 OTA 激活。

## 回复流程

1. `wake.so` 检测到 `你好小智`。
2. Lua 进入 `connecting`，按官方 WebSocket 协议发送 hello。
3. 服务端返回 `session_id` 后，Lua 发送 `listen.detect/start`。
4. 麦克风 PCM 经 `xiaozhi.so` 编成 Opus，通过 WebSocket 发给服务端。
5. 服务端返回 STT/LLM/TTS 文本事件和二进制 Opus。
6. Lua 解码 Opus，写入独占 I2S 扬声器输出。

## 官方资源

资源来自官方 `78/xiaozhi-fonts`：

- `assets/emojis/gif/*.gif`：`gif/noto-emoji_64`
- `assets/emojis/png/*.png`：`png/twemoji_64`
- `assets/fonts/font_puhui_common_20_4.bin`：官方普惠字体，当前仅预留，不默认加载

Lua UI 会优先查找 GIF，再查找 PNG，最后退回文字表情。表情文件名与官方 emotion 名保持一致，例如 `neutral.gif`、`happy.gif`、`thinking.gif`。
