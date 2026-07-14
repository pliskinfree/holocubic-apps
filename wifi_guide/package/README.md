# WiFi Setting Guide 页面说明

这是一个 320 x 240 的 WiFi 配网引导页面设计稿，文件为 `main.html`。

## 中文字体

设备端 Lua app 使用 LVGL `.bin` 字体：

```text
/sd/apps/wifi_guide/font/msyh_cn_13.bin
/sd/apps/wifi_guide/font/18chinese.bin
```

代码通过 `lv_font_load()` 加载字体，退出 app 时通过 `lv_font_free()` 释放字体。

LVGL 字体转换工具源码已下载到：

```text
tools/lv_font_conv
```

## 页面风格

- 主色为黑色，文字为白色。
- 使用少量青色表现 WiFi 状态。
- 所有主要 UI 元素使用 `position:absolute` 固定定位，适配 320 x 240 小屏。
- 页面默认显示“等待配网”状态。

## 等待配网文案

标题：

```text
连接 WiFi
```

正文：

```text
请连接 clocteck_cubic
并登录 192.168.18.1 完成配网
```

跳过说明：

```text
跳过后仍可使用本地 app；天气、股票等功能需要联网。
```

## 配网成功文案

标题：

```text
配网成功
```

正文：

```text
请使用 clocteck-cubic.local
打开设备控制网页
```

设备地址：

```text
clocteck-cubic.local
设备 IP 地址
```

说明：

```text
设备已联网，可以使用天气、股票和应用商店等功能。
```

成功页按钮：

```text
按 HOME 键返回
```

## 预览

默认配网页：

```text
main.html
```

内置成功状态：

```text
main.html?state=success&ip=192.168.0.180
```

独立成功页：

```text
success.html?ip=192.168.0.180
```
