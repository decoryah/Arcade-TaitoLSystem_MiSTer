-- Print every non-DIP input field of the running game: port tag, field name, mask, default value, type.
--   mame <set> -video none -sound none -nothrottle -autoboot_script inputs.lua -seconds_to_run 1
local m = manager.machine
for ptag, port in pairs(m.ioport.ports) do
  local t = ptag:gsub("^:", "")
  if not t:match("^DSW") then
    for fname, f in pairs(port.fields) do
      print(string.format("FIELD|%s|%s|%d|%d|%s", t, fname, f.mask, f.defvalue, tostring(f.type)))
    end
  end
end
-- the value each port reads with every input released (bits without a field keep whatever MAME gives them)
for ptag, port in pairs(m.ioport.ports) do
  local t = ptag:gsub("^:", "")
  if not t:match("^DSW") and not t:match("^AN") then
    print(string.format("IDLE|%s|%d", t, port:read()))
  end
end
