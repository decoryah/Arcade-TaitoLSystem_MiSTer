-- Log the CPU's writes (and a few reads) with the frame number, for comparing the RTL's boot with MAME's.
--   TL_OUT = output file; TL_RANGES = comma list of lo-hi hex ranges to tap (default 8000-ffff: board + chip + window)
--   TL_FRAMES_MAX = stop logging after this frame (default 60)
local m   = manager.machine
local cpu = m.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr = m.screens[":screen"]
local out = assert(io.open(os.getenv("TL_OUT") or "wtrace.txt", "w"))
local maxf = tonumber(os.getenv("TL_FRAMES_MAX") or "60")
local n = 0
local taps = {}
for lo, hi in string.gmatch(os.getenv("TL_RANGES") or "8000-ffff", "(%x+)-(%x+)") do
  table.insert(taps, prog:install_write_tap(tonumber(lo, 16), tonumber(hi, 16), "w" .. lo, function(offset, data, mask)
    local f = scr:frame_number()
    if f <= maxf and n < 400000 then
      out:write(string.format("W %04x %02x  (frame %d)\n", offset, data & 0xff, f))
      n = n + 1
    end
  end))
end
emu.register_frame_done(function() out:flush(); local f = scr:frame_number(); if f % 10 == 0 then print("frame " .. f .. " events " .. n) end end)
