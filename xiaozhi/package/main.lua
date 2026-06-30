local previous = rawget(_G, "XIAOZHI_APP")
if previous and previous.stop then
  pcall(function()
    previous.stop("reload")
  end)
end

local APP_DIR = "/sd/apps/xiaozhi"

local function load_app_module(name)
  return dofile(APP_DIR .. "/" .. name .. ".lua")
end

local Config = load_app_module("config")
local Runtime = load_app_module("runtime")

local cfg = Config.load()
local app = Runtime.new(cfg, load_app_module)

XIAOZHI_APP = app
app:start()
