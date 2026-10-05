-- Exploration: what does MAME 0.289 expose for the Taito L driver?
-- run: mame plotting -video none -sound none -nothrottle -autoboot_script explore.lua -seconds_to_run 2
local m = manager.machine
print("== machine: " .. m.system.name .. " (" .. m.system.description .. ")")

print("== devices (top level)")
for tag, dev in pairs(m.devices) do
  if #tag < 24 then print("  " .. tag .. "  " .. dev.shortname) end
end

local cpu = m.devices[":maincpu"]
print("== maincpu spaces")
for name, sp in pairs(cpu.spaces) do
  print("  " .. name .. "  name=" .. tostring(sp.name) .. " address_mask=0x" .. string.format("%x", sp.address_mask) .. " shift=" .. tostring(sp.shift))
end

print("== memory regions")
for tag, r in pairs(m.memory.regions) do
  print("  " .. tag .. "  size=0x" .. string.format("%x", r.size))
end

print("== memory shares")
for tag, s in pairs(m.memory.shares) do
  print("  " .. tag .. "  size=0x" .. string.format("%x", s.size))
end

print("== ioports")
for ptag, port in pairs(m.ioport.ports) do
  for fname, f in pairs(port.fields) do
    print(string.format("  %s  '%s'  mask=%02x defvalue=%02x", ptag, fname, f.mask, f.defvalue))
  end
end

print("== screens")
for tag, s in pairs(m.screens) do
  print("  " .. tag .. "  w=" .. s.width .. " h=" .. s.height .. " refresh=" .. s.refresh)
end
