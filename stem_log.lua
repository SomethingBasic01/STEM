-- stem_log.lua
-- Simple logging utility for S.T.E.M.

local CONFIG = require("stem_config")

local M = {}

local function ensureDir()
  local dir = CONFIG.dataDir or "/stem_data"
  if not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function writeLine(level, msg)
  ensureDir()
  local path = CONFIG.logFile or (CONFIG.dataDir .. "/stem.log")
  local h, err = fs.open(path, "a")
  if not h then
    print("LOG OPEN FAIL: " .. tostring(err))
    return
  end

  local ts
  local okTime, t = pcall(os.time)
  if okTime and t then
    local okFmt, pretty = pcall(textutils.formatTime, t, true)
    ts = okFmt and pretty or tostring(t)
  else
    ts = tostring(os.clock())
  end

  local line = string.format("[%s][%s][%d] %s", ts, level, os.getComputerID(), msg)
  h.writeLine(line)
  h.close()

  if CONFIG.logToConsole then
    if level == "ERROR" or level == "WARN" or CONFIG.logVerbose or CONFIG.logDebug then
      print(line)
    end
  end
end

function M.debug(msg)
  if CONFIG.logDebug then writeLine("DEBUG", msg) end
end

function M.info(msg)
  writeLine("INFO", msg)
end

function M.warn(msg)
  writeLine("WARN", msg)
end

function M.error(msg)
  writeLine("ERROR", msg)
end

return M
