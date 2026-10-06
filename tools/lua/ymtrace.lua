-- Log the sound CPU's writes to its sound chip, as the RTL bench's +ymlog does: "frame address-bits data" a line.
--   TL_YMLOG   = output file
--   TL_YMRANGE = address range of the chip on the sound CPU's bus (hex, default e000-e003: Raimais' YM2610)
-- Loaded before dump.lua by tools/mamedump.py --ymlog.
local m    = manager.machine
local cpu  = m.devices[":audiocpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens[":screen"]
local out  = assert(io.open(os.getenv("TL_YMLOG") or "ymtrace.txt", "w"))
local lo, hi = string.match(os.getenv("TL_YMRANGE") or "e000-e003", "(%x+)-(%x+)")
lo = tonumber(lo, 16); hi = tonumber(hi, 16)
YMTAP = prog:install_write_tap(lo, hi, "ymtrace", function(offset, data, mask)
  out:write(string.format("%d %d %02x\n", scr:frame_number(), (offset - lo) & 3, data & 0xff))
end)
emu.register_frame_done(function() out:flush() end)
