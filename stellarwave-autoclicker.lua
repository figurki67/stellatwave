-- Zodiac Melody auto-clicker (v20)
-- Fixes over v19: memory-first size reads, 8px visibility floor,
-- widened Y guard (container rests below the viewport).
-- F6 = toggle, right-click = unload.
local CFG = {
  MOVE_SETTLE  = 0.03,
  JITTER       = 0.028,
  JITTER_STEPS = 4,
  JITTER_R     = 3,
  HOLD         = 0.05,
  GAP          = 0.04,
  GROW_FRAC    = 0.30,
  MIN_PX       = 18,
  CAST_BUDGET  = 8.5,
  MAX_REPRESS  = 4,
  STALL_LIMIT  = 1.6,
  VISIBLE_PX   = 8,
  Y_SLACK      = 120,
}

local S = { clicks=0, castClicks=0, status="Ready", enabled=true, running=true,
            rerolls=0, rounds=0, shortRounds=0, lastRoundClicks=0,
            reads=0, memOK=0, memBad=0 }
S.CFG = CFG
_G.ZW = S

local function press()   if not S.pressed then mouse1press();  S.pressed=true end end
local function release() if S.pressed then mouse1release(); S.pressed=false end end

local function getAddress(v)
  local ok, a = pcall(function() return v.Address end)
  if ok and type(a) == "number" then return a end
  return nil
end

local function sizeOf(v)
  local a = getAddress(v)
  if a then
    S.reads = S.reads + 1
    local okM, w, h = pcall(function()
      return memory_read("float", a+0x104), memory_read("float", a+0x108)
    end)
    if okM and type(w) == "number" and type(h) == "number"
       and w > 0 and h > 0 and w < 100000 then
      S.memOK = S.memOK + 1
      return w, h
    end
    S.memBad = S.memBad + 1
  end
  local ok, z = pcall(function() return v.AbsoluteSize end)
  if ok and type(z) == "table" and type(z.X) == "number"
     and type(z.Y) == "number" and z.X >= CFG.VISIBLE_PX then
    return z.X, z.Y
  end
  return 0, 0
end

local function posOf(v)
  local a = getAddress(v)
  if a then
    local okP, x, y = pcall(function()
      return memory_read("float", a+0xFC), memory_read("float", a+0x100)
    end)
    if okP and type(x) == "number" and type(y) == "number"
       and x > 0 and x < 10000 and y > 0 and y < 10000 then
      return x, y
    end
  end
  local ok, p = pcall(function() return v.AbsolutePosition end)
  if ok and type(p) == "table" and type(p.X) == "number" and type(p.Y) == "number" then
    return p.X, p.Y
  end
  return nil
end

local function isSign(v)
  local ok, n = pcall(function() return v.Name end)
  return ok and type(n) == "string" and n:match("^sign%d+$") ~= nil
end

-------------- GUI --------------
local PW, PH = 296, 338
local GUI = { x=20, y=170, dragging=false, dx=0, dy=0, items={} }
local MOUSE = game:GetService("Players").LocalPlayer:GetMouse()

local COL_BG  = Color3.fromRGB(18,18,24)
local COL_TXT = Color3.fromRGB(228,231,238)
local COL_DIM = Color3.fromRGB(134,140,154)
local COL_ACC = Color3.fromRGB(92,172,255)
local COL_TRK = Color3.fromRGB(52,54,64)
local COL_OK  = Color3.fromRGB(110,220,150)

local function mkSquare(x,y,w,h,c)
  local s = Drawing.new("Square")
  s.Position=Vector2.new(x,y); s.Size=Vector2.new(w,h)
  s.Color=c; s.Filled=true; s.Visible=true
  return s
end
local function mkText(x,y,sz,c,cen)
  local s = Drawing.new("Text")
  s.Position=Vector2.new(x,y); s.Size=sz; s.Color=c
  s.Center=cen or false; s.Outline=false; s.Visible=true
  return s
end

local gPanel = mkSquare(0,0,PW,PH,COL_BG)
local gTitle = mkText(0,0,14,COL_TXT)
local gHint  = mkText(0,0,11,COL_DIM)
local gStat  = mkText(0,0,12,COL_OK)
gTitle.Text = "Zodiac Melody  [F6]"
gHint.Text  = "drag title | right-click = close"

local SPEC = {
  {"Move settle",  "MOVE_SETTLE",  0.01, 0.15, 0.005, "%.3f"},
  {"Jitter dwell", "JITTER",       0.010,0.10, 0.002, "%.3f"},
  {"Jitter steps", "JITTER_STEPS", 1,    10,   1,     "%d"},
  {"Jitter radius","JITTER_R",     1,    12,   1,     "%d"},
  {"Hold",         "HOLD",         0.01, 0.20, 0.005, "%.3f"},
  {"Gap",          "GAP",          0.00, 0.30, 0.005, "%.3f"},
  {"Grow gate",    "GROW_FRAC",    0.05, 0.90, 0.05,  "%.0f%%"},
  {"Min size px",  "MIN_PX",       4,    60,   1,     "%d"},
  {"Cast budget",  "CAST_BUDGET",  3.0, 12.0, 0.5,   "%.3f"},
  {"Max repress",  "MAX_REPRESS",  1,    8,    1,     "%d"},
}

local TRKW, ROW_H, TOP = 236, 21, 68
for i, sp in ipairs(SPEC) do
  GUI.items[i] = {
    key=sp[2], min=sp[3], max=sp[4], step=sp[5], fmt=sp[6],
    lab = mkText(0,0,12,COL_TXT),
    val = mkText(0,0,12,COL_ACC,true),
    trk = mkSquare(0,0,TRKW,4,COL_TRK),
    knb = mkSquare(0,0,4,7,COL_ACC),
    dragging=false,
  }
  GUI.items[i].lab.Text = sp[1]
end

local function place()
  local x, y = GUI.x, GUI.y
  gPanel.Position = Vector2.new(x,y)
  gTitle.Position = Vector2.new(x+12, y+7)
  gHint.Position  = Vector2.new(x+12, y+27)
  gStat.Position  = Vector2.new(x+12, y+47)
  for i = 1, #GUI.items do
    local it = GUI.items[i]
    local cy = y + TOP + (i-1)*ROW_H
    it.lab.Position = Vector2.new(x+12, cy)
    it.val.Position = Vector2.new(x+284, cy)
    it.trk.Position = Vector2.new(x+12, cy+15)
    it.knb.Position = Vector2.new(x+12, cy+14)
    it.trkX = x+12
  end
end
place()

function S.Stop()
  S.running=false; S.enabled=false; release()
  if S.conn then pcall(function() S.conn:Disconnect() end) end
  if S.guiConn then pcall(function() S.guiConn:Disconnect() end) end
  if S.rmConn then pcall(function() S.rmConn:Disconnect() end) end
  local all = { gPanel, gTitle, gHint, gStat }
  for i = 1, #GUI.items do
    local it = GUI.items[i]
    all[#all+1]=it.lab; all[#all+1]=it.val; all[#all+1]=it.trk; all[#all+1]=it.knb
  end
  for i = 1, #all do pcall(function() all[i]:Remove() end) end
end

-------------- click engine --------------
local order, seenAddr = {}, {}
local fullW, castAt, allZeroAt = 0, nil, nil
local stallSince = nil

local function endRound()
  S.rounds = S.rounds + 1
  S.lastRoundClicks = S.castClicks
  if S.castClicks > 0 and S.castClicks < 12 then
    S.shortRounds = S.shortRounds + 1
    print(string.format("round end: %d clicks (SHORT)  total=%d", S.castClicks, S.clicks))
  end
end

local function resetCast(countRound)
  if countRound and S.castClicks > 0 then S.rerolls = S.rerolls + 1 end
  release(); S.pending = nil
  order, seenAddr = {}, {}
  fullW, castAt, allZeroAt = 0, nil, nil
  S.castClicks = 0
  S.nextIdx = 1
  S.nextClick = 0
  stallSince = nil
end

local function jitterStep(x, y)
  local r = CFG.JITTER_R
  mousemoveabs(math.floor(x + (math.random()*2-1)*r + 0.5),
               math.floor(y + (math.random()*2-1)*r + 0.5))
end

local function tickCast(now, cont, maxX, maxY)
  local anyVisible = false
  local kids = cont:GetChildren()
  for i = #kids, 1, -1 do
    local v = kids[i]
    if isSign(v) then
      local w, h = sizeOf(v)
      if w > fullW then fullW = w end
      if w >= CFG.VISIBLE_PX then
        anyVisible = true
        local a = getAddress(v)
        if a ~= nil and not seenAddr[a] then
          seenAddr[a] = true
          order[#order+1] = v
        end
      end
    end
  end

  if not anyVisible then
    if allZeroAt == nil then allZeroAt = now end
    if now - allZeroAt > 0.2 then
      if S.castClicks > 0 then endRound() end
      resetCast(false)
    end
    return
  end
  allZeroAt = nil
  if not castAt then castAt = now end
  if now - castAt > CFG.CAST_BUDGET then
    if S.castClicks > 0 then endRound() end
    resetCast(true)
    S.status = "window passed @ " .. S.castClicks
    return
  end
  if S.nextIdx == nil then S.nextIdx = 1 end
  if now < (S.nextClick or 0) then return end

  local v = order[S.nextIdx]
  if not v then
    S.status = "round: " .. S.castClicks .. " clicks"
    return
  end

  local w, h = sizeOf(v)
  local px, py = posOf(v)
  local viable = px ~= nil and w >= math.max(CFG.MIN_PX, fullW*CFG.GROW_FRAC) and h >= CFG.MIN_PX
  if not viable then
    if stallSince == nil then stallSince = now end
    if now - stallSince > CFG.STALL_LIMIT then
      if S.castClicks > 0 then endRound() end
      order, seenAddr = {}, {}
      for i = 1, #kids do
        local k = kids[i]
        if isSign(k) then
          local kw = sizeOf(k)
          local ka = getAddress(k)
          if kw >= CFG.VISIBLE_PX and ka ~= nil and not seenAddr[ka] then
            seenAddr[ka] = true
            order[#order+1] = k
          end
        end
      end
      S.nextIdx = 1
      S.pending = nil
      release()
      stallSince = now
      S.rerolls = S.rerolls + 1
      S.castClicks = 0
      S.status = "reroll -> restart"
    end
    return
  end
  stallSince = nil

  local x, y = px + w/2, py + h/2
  if x < 5 or y < 5 or x > maxX-5 or y > maxY + CFG.Y_SLACK then return end

  local p = S.pending
  if not p then
    mousemoveabs(math.floor(x+0.5), math.floor(y+0.5))
    S.pending = { at=now, phase="settle", step=0, addr=getAddress(v), x=x, y=y }
    S.status = "aim " .. S.nextIdx .. "/" .. #order
             .. " w=" .. string.format("%.0f", w)
             .. " @" .. string.format("%.0f,%.0f", x, y)
    return
  end
  if p.addr ~= getAddress(v) then S.pending = nil; return end
  p.x, p.y = x, y

  if p.phase == "settle" and now - p.at >= CFG.MOVE_SETTLE then
    p.phase = "jitter"; p.at = now; p.step = 0
  elseif p.phase == "jitter" and now - p.at >= CFG.JITTER then
    p.step = p.step + 1; p.at = now
    if p.step <= CFG.JITTER_STEPS then
      jitterStep(p.x, p.y)
    else
      mousemoveabs(math.floor(p.x+0.5), math.floor(p.y+0.5))
      p.phase = "prepress"; p.at = now
    end
  elseif p.phase == "prepress" and now - p.at >= CFG.JITTER then
    press()
    if not ismouse1pressed() then
      p.retries = (p.retries or 0) + 1
      if p.retries <= CFG.MAX_REPRESS then
        p.phase = "jitter"; p.step = 0; p.at = now
        return
      end
    end
    p.phase = "press"; p.at = now
  elseif p.phase == "press" and now - p.at >= CFG.HOLD then
    release()
    S.clicks = S.clicks + 1
    S.castClicks = S.castClicks + 1
    S.pending = nil
    S.nextClick = now + CFG.GAP
    S.nextIdx = S.nextIdx + 1
  end
end

-------------- loops --------------
local cam = workspace:FindFirstChildOfClass("Camera")
local lastPoll = 0

local function findContainer()
  local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
  if not pg then return nil end
  local reel = pg:FindFirstChild("reel")
  if reel then
    local bar = reel:FindFirstChild("bar")
    local cont = bar and bar:FindFirstChild("signContainer")
    if cont then return cont end
  end
  local kids = pg:GetChildren()
  for i = 1, #kids do
    local c = kids[i]
    local s = c:FindFirstChild("signContainer")
    if s then return s end
    local b = c:FindFirstChild("bar")
    local s2 = b and b:FindFirstChild("signContainer")
    if s2 then return s2 end
  end
  return nil
end

S.conn = game:GetService("RunService").RenderStepped:Connect(function()
  if not S.running then return end
  local now = tick()
  local f6 = iskeypressed(0x75)
  if f6 and not S.f6Was then
    S.enabled = not S.enabled
    release(); S.pending = nil
    S.status = S.enabled and "on" or "paused"
  end
  S.f6Was = f6
  if not S.enabled or not isrbxactive() then return end
  if now - lastPoll < 0.02 then return end
  lastPoll = now

  pcall(function()
    if not S.routed then pcall(function() setrobloxinput(true) end); S.routed = true end
    local cont = findContainer()
    if not cont then
      if castAt then
        if S.castClicks > 0 then endRound() end
        resetCast(false)
      end
      S.status = "armed"
      return
    end
    local ca = getAddress(cont)
    if ca ~= nil and S.contAddr ~= ca then
      resetCast(false)
      S.contAddr = ca
    end
    local vp = cam and cam.ViewportSize
    tickCast(now, cont, vp and vp.X or 1920, vp and vp.Y or 1080)
  end)
end)

local wasDown = false
S.guiConn = game:GetService("RunService").RenderStepped:Connect(function()
  if not S.running then return end
  local down = ismouse1pressed()
  local mx, my = MOUSE.X, MOUSE.Y
  local x, y = GUI.x, GUI.y

  if down and not wasDown then
    if mx >= x and mx <= x+PW and my >= y and my <= y+TOP-4 then
      GUI.dragging = true
      GUI.dx, GUI.dy = mx - x, my - y
    else
      local idx = math.floor((my - (y + TOP)) / ROW_H) + 1
      if idx >= 1 and idx <= #GUI.items
         and mx >= x+8 and mx <= x+8+TRKW
         and my >= y+TOP+(idx-1)*ROW_H and my <= y+TOP+(idx-1)*ROW_H+ROW_H then
        GUI.items[idx].dragging = true
      end
    end
  elseif wasDown and not down then
    GUI.dragging = false
    for i = 1, #GUI.items do GUI.items[i].dragging = false end
  end
  wasDown = down

  if GUI.dragging then
    GUI.x = mx - GUI.dx; GUI.y = my - GUI.dy; place()
  end

  for i = 1, #GUI.items do
    local it = GUI.items[i]
    if it.dragging then
      local t = math.max(0, math.min(1, (mx - it.trkX) / TRKW))
      local raw = it.min + t*(it.max - it.min)
      local snap = it.min + math.floor((raw - it.min)/it.step + 0.5)*it.step
      CFG[it.key] = math.max(it.min, math.min(it.max, snap))
    end
    local t = math.max(0, math.min(1, (CFG[it.key] - it.min) / (it.max - it.min)))
    it.knb.Size = Vector2.new(math.max(3, t*TRKW), 7)
    it.val.Text = string.format(it.fmt, CFG[it.key])
  end

  gStat.Text = S.status .. "  |  " .. S.clicks .. " clicks  rr" .. S.rerolls
             .. "  |  m" .. S.memOK .. "/" .. S.reads
             .. "  |  " .. (S.enabled and "ON" or "OFF")
  gStat.Color = S.enabled and COL_OK or COL_DIM
end)

S.rmConn = game:GetService("UserInputService").InputBegan:Connect(function(k)
  if k and k.KeyCode == 2 then S.Stop() end
end)

print("ZW v20 loaded (memory-first sizes, 8px floor, widened Y guard)")