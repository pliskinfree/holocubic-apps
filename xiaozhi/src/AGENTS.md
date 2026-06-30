# AGENTS.md

This directory contains the development-side sources for the XiaoZhi dynamic
module. Do not deploy `src/` to the device.

- Deploy only the contents of `../package/` to `/sd/apps/xiaozhi/`.
- `../package/xiaozhi.so` and `../package/wake.so` are intentionally loaded
  from the app directory by `package/config.lua`.
- Keep device-specific runtime state in `/sd/apps/xiaozhi/config.json`;
  commit only `package/config.example.json`.
- To rebuild `xiaozhi.so`, set `CUBICLUA_ROOT` or `MODULE_ABI_DIR` so CMake can
  find the firmware `src/dynmod/module_abi.h`.
