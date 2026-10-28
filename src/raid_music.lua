-- The raids' own music (data/raid_music.lua): one track at a time, streamed from its .ogg (a Decoder
-- fed into a QueueableSource a chunk at a time) and looped at the file's own loop points to the
-- sample; a change fades the old one out and the new one in. While one plays the game's music is
-- faded out; the raid brings the field's back when it closes. Its volume follows the game's: the
-- music volume (Audio._bgmVolume), its ducking under a cry (Audio._duck), the game suspended (paused).
--   RM = raid_music(mod, { data, Audio })
--   RM.play(name) ; RM.stop() ; RM.update(dt) (every frame, the raid's or not) ; RM.playing() -> name
return function(mod, deps)
  local D = deps.data or { TRACKS = {}, MIX = 0.55, FADE_S = 0.8 }
  local Audio = deps.Audio
  local RM = {}
  local min, max = math.min, math.max

  local CHUNK = 4096        -- samples a chunk
  local BUFFERS = 8         -- chunks queued ahead
  -- the voices: the one playing (cur) and the one fading out (old)
  local cur, old = nil, nil
  local bytesOf = {}        -- a file's bytes, read once

  local function fileData(t)
    local fd = bytesOf[t.file]
    if fd then return fd end
    local bytes = mod.read and mod:read(t.file)
    if not bytes then return nil end
    fd = love.filesystem.newFileData(bytes, t.file:match("[^/]+$"))
    bytesOf[t.file] = fd
    return fd
  end

  local function open(name)
    local t = D.TRACKS[name]
    if not (t and love and love.sound and love.audio and love.audio.newQueueableSource) then return nil end
    local ok, v = pcall(function()
      local fd = fileData(t)
      if not fd then return nil end
      local dec = love.sound.newDecoder(fd, CHUNK)
      local rate, bits, ch = dec:getSampleRate(), dec:getBitDepth(), dec:getChannelCount()
      local src = love.audio.newQueueableSource(rate, bits, ch, BUFFERS)
      return { name = name, t = t, dec = dec, src = src, rate = rate, bits = bits, ch = ch, pos = 0,
        loopEnd = t.loopStart + t.loopLength, fade = 0, to = 1, speed = 1 / max(0.05, D.FADE_S) }
    end)
    if not ok then
      if mod.log then mod.log:warn("raid music %s did not open (%s)", name, tostring(v)) end
      return nil
    end
    return v
  end

  -- the next chunk: from the decoder, cut at the loop's end (the decoder then sent back to its start)
  local function nextChunk(v)
    local sd = v.dec:decode()
    if not sd then
      -- (the file ended before its loop's end: back to the loop's start)
      v.dec:seek(v.t.loopStart / v.rate)
      v.pos = v.t.loopStart
      sd = v.dec:decode()
      if not sd then return nil end
    end
    local n = sd:getSampleCount()
    if v.pos + n >= v.loopEnd then
      local keep = v.loopEnd - v.pos
      v.dec:seek(v.t.loopStart / v.rate)
      v.pos = v.t.loopStart
      if keep <= 0 then return nextChunk(v) end
      local cut = love.sound.newSoundData(keep, v.rate, v.bits, v.ch)
      for i = 0, keep - 1 do
        for c = 1, v.ch do cut:setSample(i, c, sd:getSample(i, c)) end
      end
      return cut
    end
    v.pos = v.pos + n
    return sd
  end

  local function feed(v)
    for _ = 1, BUFFERS do
      if v.src:getFreeBufferCount() <= 0 then break end
      local sd = nextChunk(v)
      if not sd then break end
      v.src:queue(sd)
    end
    if not v.src:isPlaying() and not v.paused then v.src:play() end
  end

  local function gameGain()
    if not Audio then return 1 end
    local g = tonumber(Audio._bgmVolume) or 1
    g = g * (tonumber(Audio._duck) or 1)
    return g * (D.MIX or 1)
  end

  local function release(v)
    if v and v.src then pcall(v.src.stop, v.src); pcall(v.src.release, v.src) end
    if v and v.dec then pcall(v.dec.release, v.dec) end
  end

  -- the game's music faded away under ours (once, when ours starts)
  local function quietGame()
    if Audio and Audio.fadeOutBgm then pcall(Audio.fadeOutBgm, 4) end
  end

  function RM.play(name)
    if cur and cur.name == name then cur.to = 1; return true end
    local v = open(name)
    if not v then return false end
    if not cur and not old then quietGame() end
    if old then release(old) end
    if cur then cur.to = 0; old = cur end
    cur = v
    feed(cur)
    return true
  end

  -- faded out (not cut)
  function RM.stop()
    if cur then
      if old then release(old) end
      cur.to, old, cur = 0, cur, nil
    end
  end
  function RM.playing() return cur and cur.name or nil end

  local function step(v, dt, gain, suspended)
    if v.fade < v.to then v.fade = min(v.to, v.fade + dt * v.speed)
    elseif v.fade > v.to then v.fade = max(v.to, v.fade - dt * v.speed) end
    if suspended then
      if not v.paused then v.paused = true; pcall(v.src.pause, v.src) end
      return
    elseif v.paused then
      v.paused = false
    end
    pcall(v.src.setVolume, v.src, max(0, min(1, gain * (v.t.gain or 1) * v.fade)))
    pcall(feed, v)
  end

  function RM.update(dt)
    if not (cur or old) then return end
    dt = min(0.1, dt or 1 / 60)
    local gain = gameGain()
    local suspended = Audio and Audio._suspended == true
    if cur then step(cur, dt, gain, suspended) end
    if old then
      step(old, dt, gain, suspended)
      if old.fade <= 0 then release(old); old = nil end
    end
  end

  -- (drivers) the voice playing, the data, a file's loudness over its first `seconds` (RMS, dB)
  function RM._cur() return cur end
  RM._data = D
  function RM._loudness(name, seconds)
    local t = D.TRACKS[name]
    local fd = t and fileData(t)
    if not fd then return nil end
    local dec = love.sound.newDecoder(fd, 16384)
    local limit = (seconds or 20) * dec:getSampleRate()
    local sum, n = 0, 0
    while n < limit do
      local sd = dec:decode()
      if not sd then break end
      for i = 0, sd:getSampleCount() - 1, 4 do
        local x = sd:getSample(i, 1)
        sum, n = sum + x * x, n + 4
      end
    end
    dec:release()
    if n == 0 then return nil end
    return 10 * math.log10(sum / (n / 4))
  end

  return RM
end
