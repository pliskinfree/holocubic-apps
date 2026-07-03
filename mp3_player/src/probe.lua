local audio = require("/sd/modules/audio.so")

print("[audio probe] " .. tostring(audio.version and audio.version() or audio.VERSION))

local ok, err = audio.open("/sd/MP3/22.mp3", { output_channels = 1 })
if not ok then
  error(tostring(err))
end

local info = audio.info()
print("[audio probe] type=" .. tostring(info.type)
  .. " rate=" .. tostring(info.sample_rate)
  .. " channels=" .. tostring(info.channels))

local total = 0
while total < 65536 do
  local pcm, read_err = audio.read(4096)
  if not pcm then
    error(tostring(read_err))
  end
  if #pcm == 0 then
    break
  end
  total = total + #pcm
end

audio.close()
print("[audio probe] decoded=" .. tostring(total))

