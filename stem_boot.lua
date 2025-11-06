-- stem_boot.lua
-- Minimal bootstrap for S.T.E.M. nodes.
-- New turtles/computers only need THIS file copied manually.

local BOOT_PROTOCOL = "STEM_BOOT"

-- Detect a modem and open rednet.
local function initModem()
  if not rednet then
    print("S.T.E.M BOOT: rednet API not available.")
    return nil
  end
  if rednet.isOpen() then
    return true
  end
  local bestSide, bestWireless = nil, false
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      local isWireless = false
      pcall(function()
        isWireless = peripheral.call(side, "isWireless")
      end)
      if isWireless and not bestWireless then
        bestSide, bestWireless = side, true
      elseif not bestSide then
        bestSide = side
      end
    end
  end
  if bestSide then
    rednet.open(bestSide)
    print("S.T.E.M BOOT: Modem opened on side " .. bestSide)
    return true
  else
    print("S.T.E.M BOOT: No modem found; hive discovery impossible.")
    return nil
  end
end

-- Contact the hive, returning providerId or nil.
local function findProvider()
  if not rednet or not rednet.isOpen() then return nil end
  local id = os.getComputerID()
  print("S.T.E.M BOOT: Discovering hive...")
  local msg = { fromId = id, type = "boot_discover" }
  rednet.broadcast(msg, BOOT_PROTOCOL)

  local timeout = os.clock() + 3
  while os.clock() < timeout do
    local senderId, message, protocol = rednet.receive(BOOT_PROTOCOL, 0.5)
    if senderId and protocol == BOOT_PROTOCOL and type(message) == "table" then
      if message.type == "boot_offer" then
        print("S.T.E.M BOOT: Found hive node " .. senderId)
        return senderId
      end
    end
  end
  print("S.T.E.M BOOT: No hive responded.")
  return nil
end

-- Request list of files from provider.
local function requestFileList(providerId)
  local req = { fromId = os.getComputerID(), type = "file_list_request" }
  rednet.send(providerId, req, BOOT_PROTOCOL)
  while true do
    local senderId, message, protocol = rednet.receive(BOOT_PROTOCOL, 5)
    if not senderId then
      print("S.T.E.M BOOT: Timed out waiting for file list.")
      return nil
    end
    if senderId == providerId and protocol == BOOT_PROTOCOL and type(message) == "table" then
      if message.type == "file_list" then
        local files = message.payload and message.payload.files
        if type(files) == "table" then
          print("S.T.E.M BOOT: Received file list (" .. #files .. " files).")
          return files
        end
      end
    end
  end
end

-- Download a single file from provider.
local function downloadFile(providerId, fileName)
  print("S.T.E.M BOOT: Downloading " .. fileName .. " ...")
  local req = {
    fromId = os.getComputerID(),
    type   = "file_request",
    payload = { file = fileName },
  }
  rednet.send(providerId, req, BOOT_PROTOCOL)

  local h, err = fs.open(fileName, "w")
  if not h then
    print("S.T.E.M BOOT: Failed to open " .. fileName .. " for writing: " .. tostring(err))
    return false
  end

  while true do
    local senderId, message, protocol = rednet.receive(BOOT_PROTOCOL, 5)
    if not senderId then
      print("S.T.E.M BOOT: Timed out while receiving " .. fileName)
      h.close()
      return false
    end
    if senderId == providerId and protocol == BOOT_PROTOCOL and type(message) == "table" then
      if message.type == "file_error" then
        print("S.T.E.M BOOT: Provider reported error for " .. (message.payload and message.payload.file or "?"))
        h.close()
        return false
      elseif message.type == "file_chunk" then
        local p = message.payload or {}
        if p.file == fileName then
          if p.data and p.data ~= "" then
            h.write(p.data)
          end
          if p.final then
            h.close()
            print("S.T.E.M BOOT: Finished " .. fileName)
            return true
          end
        end
      end
    end
  end
end

-- Try to start as founder if local files already exist.
local function localFounderAvailable()
  return fs.exists("stem.lua") and fs.exists("stem_core.lua")
end

-- MAIN BOOTSTRAP ------------------------------------------------------

local function main()
  term.clear()
  term.setCursorPos(1,1)
  print("S.T.E.M BOOT: Initialising...")

  initModem()

  local providerId = findProvider()
  if providerId then
    -- Download files from hive.
    local files = requestFileList(providerId)
    if not files then
      print("S.T.E.M BOOT: Failed to obtain file list from hive.")
    else
      for _, fname in ipairs(files) do
        if fname ~= "stem_boot.lua" then
          -- We already are stem_boot; no need to overwrite unless you wish.
          downloadFile(providerId, fname)
        end
      end
    end
    print("S.T.E.M BOOT: Launching S.T.E.M as normal node.")
    if fs.exists("stem.lua") then
      shell.run("stem")
    else
      print("S.T.E.M BOOT: stem.lua missing after download.")
    end
    return
  end

  -- No provider found – perhaps we are the founder.
  if localFounderAvailable() then
    print("S.T.E.M BOOT: No hive found; starting NEW hive as founder.")
    shell.run("stem", "founder")
  else
    print("S.T.E.M BOOT: No hive and no local S.T.E.M files.")
    print("Copy the full S.T.E.M program (stem.lua + modules) to this turtle")
    print("and run stem_boot again to initialise the hive.")
  end
end

main()
