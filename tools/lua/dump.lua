-- Dump Taito L machine state + MAME's own frame, for the reference renderer and the RTL benches.
--
--   TL_OUT     output prefix (directory must exist), e.g. work/dumps/plotting
--   TL_FRAMES  comma list of frame numbers to dump, e.g. "100,300,800"
--   TL_INPUT   input script, ';'-separated "frame:port:field:value", value 1 = pressed,
--              e.g. "600:IN0:Coin 1:1;605:IN0:Coin 1:0"
--   TL_REGIONS 1 = also write the static ROM regions once (maincpu.bin, gfx.bin)
--   TL_FORCEFLIP=N  from frame N on set bit 4 (the chip's flip bit) of the byte at TL_FLIPADDR (hex, default 8211: Plotting's
--                   RAM shadow of video register 4, which the game copies into the chip every frame) -- tests the flip paths;
--                   the dumps then carry the flipped register
--
-- Per dumped frame N it writes <TL_OUT>.fNNNNN.{vram,pal,vregs,spr_prev,spr_cur,ctl}.bin and <TL_OUT>.fNNNNN.png.
-- spr_prev is VRAM[B000..B3FF] as it was at the end of frame N-1 (MAME copies the sprite RAM at vblank, after the
-- frame has been drawn, so frame N is drawn from the copy made at the end of frame N-1); spr_cur is frame N's own.
local m      = manager.machine
local out    = os.getenv("TL_OUT") or "dump"
local scr    = m.screens[":screen"]
local cpu    = m.devices[":maincpu"]
local prog   = cpu.spaces["program"]
local vramsh = m.memory.shares[":maincpu:vram"]
local palsh  = m.memory.shares[":maincpu:palette"]
local bmpsh  = m.memory.shares[":maincpu:bitmap_ram"]

local want = {}
for f in string.gmatch(os.getenv("TL_FRAMES") or "60", "%d+") do want[tonumber(f)] = true end

local events = {}   -- frame -> list of {port, field, value}
for ev in string.gmatch(os.getenv("TL_INPUT") or "", "[^;]+") do
  local fr, port, field, val = string.match(ev, "^(%d+):([^:]+):([^:]+):(%d+)$")
  if fr then
    fr = tonumber(fr)
    events[fr] = events[fr] or {}
    table.insert(events[fr], { port = ":" .. port, field = field, value = tonumber(val) })
  end
end

local function wr(path, str)
  local f = assert(io.open(path, "wb"))
  f:write(str)
  f:close()
end

local function bytes(share, base, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(share:read_u8(base + i)) end
  return table.concat(t)
end

local function pbytes(base, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(prog:read_u8(base + i)) end
  return table.concat(t)
end

if os.getenv("TL_REGIONS") == "1" then
  for _, r in ipairs({ { ":maincpu", "maincpu" }, { ":maincpu:gfx", "gfx" } }) do
    local reg = m.memory.regions[r[1]]
    local t = {}
    for i = 0, reg.size - 1 do t[#t + 1] = string.char(reg:read_u8(i)) end
    wr(out .. "." .. r[2] .. ".bin", table.concat(t))
  end
end

local prev_spr = string.rep("\0", 0x400)

local forceflip = tonumber(os.getenv("TL_FORCEFLIP") or "")
local flipaddr = tonumber(os.getenv("TL_FLIPADDR") or "8211", 16)
emu.register_frame_done(function()
  local n = scr:frame_number()
  if forceflip and n >= forceflip then prog:write_u8(flipaddr, prog:read_u8(flipaddr) | 0x10) end

  local ev = events[n]
  if ev then
    for _, e in ipairs(ev) do
      local p = m.ioport.ports[e.port]
      if p and p.fields[e.field] then p.fields[e.field]:set_value(e.value)
      else print("input event: no such field " .. e.port .. " / " .. e.field) end
    end
  end

  local cur_spr = bytes(vramsh, 0xb000, 0x400)
  if want[n] then
    local p = string.format("%s.f%05d", out, n)
    wr(p .. ".vram.bin", bytes(vramsh, 0, 0x10000))
    wr(p .. ".pal.bin", bytes(palsh, 0, 0x200))
    wr(p .. ".vregs.bin", pbytes(0xfe00, 0x100))
    wr(p .. ".spr_prev.bin", prev_spr)
    wr(p .. ".spr_cur.bin", cur_spr)
    -- ff00-ff08: irq vectors, irq enable, ram banks, rom bank (readable through the chip's own handlers)
    wr(p .. ".ctl.bin", pbytes(0xff00, 9))
    if os.getenv("TL_BITMAP") == "1" then wr(p .. ".bitmap.bin", bytes(bmpsh, 0, 0x20000)) end
    scr:snapshot(string.format("%s.f%05d.png", out:match("([^/\\]+)$"), n))
    print(string.format("dumped frame %d", n))
  end
  prev_spr = cur_spr
end)
