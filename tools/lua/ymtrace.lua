-- Log the sound CPU's writes to its sound chip, as the RTL bench's +ymlog does: "frame address-bits data" a line.
--   TL_YMLOG   = output file
--   TL_YMRANGE = address range of the chip on the sound CPU's bus (hex, default e000-e003: Raimais' YM2610)
--   TL_YMCPU   = the CPU whose bus it is (default :audiocpu; the one-CPU boards, Plotting among them, have the chip on :maincpu)
--   TL_YMMASK  = address bits kept in the log (default 3; the YM2203 only uses bit 0)
-- Loaded before dump.lua by tools/mamedump.py --ymlog.
local m    = manager.machine
local cpu  = m.devices[os.getenv("TL_YMCPU") or ":audiocpu"]
local prog = cpu.spaces["program"]
local scr  = m.screens[":screen"]
local out  = assert(io.open(os.getenv("TL_YMLOG") or "ymtrace.txt", "w"))
local lo, hi = string.match(os.getenv("TL_YMRANGE") or "e000-e003", "(%x+)-(%x+)")
lo = tonumber(lo, 16); hi = tonumber(hi, 16)
local amask = tonumber(os.getenv("TL_YMMASK") or "3")
YMTAP = prog:install_write_tap(lo, hi, "ymtrace", function(offset, data, mask)
  out:write(string.format("%d %d %02x\n", scr:frame_number(), (offset - lo) & amask, data & 0xff))
end)
emu.register_frame_done(function() out:flush() end)
