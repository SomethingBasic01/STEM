-- stem_install.lua
-- S.T.E.M. installer which fetches all modules from your GitHub repository.

local BASE_URL = "https://raw.githubusercontent.com/SomethingBasic01/STEM/main/"

local FILES = {
  "stem.lua",
  "stem_boot.lua",
  "stem_combat.lua",
  "stem_config.lua",
  "stem_core.lua",
  "stem_mining.lua",
  "stem_network.lua",
  "stem_roles.lua",
  "stem_state.lua",
  "stem_stronghold.lua",
  "stem_log.lua",
}

local function ensureHttp()
  if not http then
    print("S.T.E.M INSTALL: http API is disabled.")
    print("Enable http in the CC:Tweaked / ComputerCraft config first.")
    return false
  end
  return true
end

local function downloadFile(name)
  local url = BASE_URL .. name
  print("S.T.E.M INSTALL: Downloading " .. name)
  print("  from " .. url)

  local res = http.get(url)
  if not res then
    print("  FAILED: http.get() returned nil.")
    return false
  end

  local data = res.readAll()
  res.close()

  if not data or data == "" then
    print("  FAILED: empty response.")
    return false
  end

  local h, err = fs.open(name, "w")
  if not h then
    print("  FAILED: cannot open " .. name .. " for writing: " .. tostring(err))
    return false
  end
  h.write(data)
  h.close()
  print("  OK.")
  return true
end

local function main()
  term.clear()
  term.setCursorPos(1, 1)
  print("S.T.E.M Installer (GitHub)")
  print("-------------------------")

  if not ensureHttp() then return end

  for _, name in ipairs(FILES) do
    if not downloadFile(name) then
      print("S.T.E.M INSTALL: Aborting due to failure.")
      return
    end
  end

  print("")
  print("All S.T.E.M. files downloaded.")
  print("You may now run:")
  print("  stem_boot")
end

main()
    return false
  end

  local data = res.readAll()
  res.close()

  if not data or data == "" then
    print("  FAILED: empty response.")
    return false
  end

  local h, err = fs.open(name, "w")
  if not h then
    print("  FAILED: cannot open " .. name .. " for writing: " .. tostring(err))
    return false
  end
  h.write(data)
  h.close()
  print("  OK.")
  return true
end

local function main()
  term.clear()
  term.setCursorPos(1, 1)
  print("S.T.E.M Installer (GitHub)")
  print("-------------------------")

  if not ensureHttp() then return end

  for _, name in ipairs(FILES) do
    if not downloadFile(name) then
      print("S.T.E.M INSTALL: Aborting due to failure.")
      return
    end
  end

  print("")
  print("All S.T.E.M. files downloaded.")
  print("You may now run:")
  print("  stem_boot")
end

main()
