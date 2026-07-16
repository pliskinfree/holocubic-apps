local config = {}

config.host = "192.168.0.80"
config.port = 80
config.path = "/sse"
config.layout = "classic"

config.timeout_ms = 7000
config.reconnect_ms = 2000
config.stale_ms = 5000
config.watchdog_ms = 1000
config.serial_log = true

config.history_points = 48

config.thresholds = {
  warm_temp = 70,
  hot_temp = 85,
  warm_load = 75,
  hot_load = 92
}

config.metrics = {
  {
    id = "cpu_usage",
    title = "CPU",
    unit = "%",
    kind = "percent",
    aliases = { "CPU Usage", "CPU Utilization", "CPU" }
  },
  {
    id = "gpu_usage",
    title = "GPU",
    unit = "%",
    kind = "percent",
    aliases = { "GPU Usage", "GPU1 Usage", "GPU Utilization", "GPU" }
  },
  {
    id = "memory_usage",
    title = "RAM",
    unit = "%",
    kind = "percent",
    aliases = { "Memory Usage", "Memory Utilization", "RAM Usage", "Memory" }
  },
  {
    id = "vram_usage",
    title = "VRAM",
    unit = "%",
    kind = "percent",
    aliases = { "GPU Memory Usage", "VRAM Usage", "Video Memory Usage", "VRAM" }
  },
  {
    id = "cpu_clock",
    title = "CPU Clock",
    unit = "MHz",
    kind = "clock",
    aliases = { "CPU Frequency", "CPU Clock", "CPU Core Clock" },
    min_valid = 1
  },
  {
    id = "gpu_clock",
    title = "GPU Clock",
    unit = "MHz",
    kind = "clock",
    aliases = { "GPU Frequency", "GPU Clock", "GPU Core Clock" },
    min_valid = 1
  },
  {
    id = "cpu_temp",
    title = "CPU Temp",
    unit = "C",
    kind = "temperature",
    aliases = { "CPU Diode", "CPU Temperature", "CPU Package" },
    min_valid = 1
  },
  {
    id = "gpu_temp",
    title = "GPU Temp",
    unit = "C",
    kind = "temperature",
    aliases = { "GPU Temperature", "GPU Diode", "GPU1 Temperature" },
    min_valid = 1
  },
  {
    id = "fan",
    title = "Fan",
    unit = "RPM",
    kind = "speed",
    aliases = { "CPU Fan", "GPU Fan", "Chassis Fan 1", "Chassis Fan 2", "Chassis Fan", "Fan" },
    min_valid = 1
  }
}

return config
