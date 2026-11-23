-- Run from the mod root: lua tests/locale.lua [locale-file]
local path = arg[1] or "locale/en/locale.cfg"
local sections, keys, section = {}, {}, nil
local line_number = 0
for line in io.lines(path) do
  line_number = line_number + 1
  local heading = line:match("^%s*%[([^%]]+)%]%s*$")
  if heading then
    assert(not sections[heading], path .. ":" .. line_number .. ": duplicate section " .. heading)
    sections[heading], keys, section = true, {}, heading
  elseif not line:match("^%s*[;#]") and not line:match("^%s*$") then
    local key = line:match("^%s*([^=]-)%s*=")
    assert(section and key, path .. ":" .. line_number .. ": invalid locale entry")
    assert(not keys[key], path .. ":" .. line_number .. ": duplicate key " .. key)
    keys[key] = true
  end
end
assert(sections["mod-setting-name"] and sections["mod-setting-description"], "missing setting locale sections")
print("PASS: locale sections and keys are unique")
