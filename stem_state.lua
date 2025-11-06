-- stem_state.lua
-- Persistent node state handling and basic movement helpers for turtles.

local CONFIG = require("stem_config")

local M = {}

-- Ensure the data directory exists.
local function ensureDataDir()
  if not fs.exists(CONFIG.dataDir) then
    fs.makeDir(CONFIG.dataDir)
  end
end

-- Save a Lua table as JSON.
local function saveJson(path, tbl)
  ensureDataDir()
  local h, err = fs.open(path, "w")
  if not h then
    error("Failed to open " .. path .. " for writing: " .. tostring(err))
  end
  h.write(textutils.serializeJSON(tbl))
  h.close()
end

-- Load a JSON file into a Lua table, or return nil.
local function loadJson(path)
  if not fs.exists(path) then return nil end
  local h, err = fs.open(path, "r")
  if not h then
    error("Failed to open " .. path .. " for reading: " .. tostring(err))
  end
  local content = h.readAll()
  h.close()
  if not content or content == "" then return nil end
  return textutils.unserializeJSON(content)
end

-- Determine whether we are a turtle or a normal computer.
local function detectKind()
  local kind = "computer"
  if turtle then
    kind = "turtle"
  end
  return kind
end

-- Attempt to locate GPS coordinates (optional).
local function tryGPS()
  if not gps then return nil end
  local x, y, z = gps.locate(5)
  if x and y and z then
    return { x = x, y = y, z = z, dir = 0, absolute = true }
  end
  return nil
end

-- Initialise a default state table.
local function defaultState()
  local pos = tryGPS() or { x = 0, y = 0, z = 0, dir = 0, absolute = false }
  local s = {
    nodeId     = os.getComputerID(),
    kind       = detectKind(), -- "turtle" or "computer"
    role       = nil,          -- decided later
    isFounder  = false,
    home       = {
      x   = pos.x,
      y   = pos.y,
      z   = pos.z,
      dir = pos.dir,
    },
    pos = {
      x   = pos.x,
      y   = pos.y,
      z   = pos.z,
      dir = pos.dir,
    },
    mining   = nil,   -- mining-specific state
    combat   = nil,   -- soldier-specific state
    stronghold = nil, -- stronghold-specific state
    task     = nil,   -- generic task
    fuelLevel = 0,
    _lastSave = os.clock(),
    _dirty    = true,
  }
  return s
end

-- PUBLIC: Load or create state.
-- @param isFounder (boolean) whether this node is the hive founder.
function M.load(isFounder)
  ensureDataDir()
  local state = loadJson(CONFIG.stateFile) or defaultState()
  state.nodeId = os.getComputerID()
  state.kind   = detectKind()
  if isFounder then
    state.isFounder = true
  end
  state._lastSave = state._lastSave or os.clock()
  state._dirty    = state._dirty or true
  return state
end

-- PUBLIC: Save state immediately.
-- Side effects: writes to disk.
function M.save(state)
  saveJson(CONFIG.stateFile, state)
  state._dirty = false
  state._lastSave = os.clock()
end

-- PUBLIC: Mark state as dirty (must be saved later).
function M.markDirty(state)
  state._dirty = true
end

-- PUBLIC: Periodic autosave based on CONFIG.saveInterval.
function M.periodicSave(state)
  if not state._dirty then return end
  local now = os.clock()
  if now - (state._lastSave or 0) >= CONFIG.saveInterval then
    M.save(state)
  end
end

-- INTERNAL: Update position based on direction.
local function advancePosForward(pos)
  if not pos then return end
  if pos.dir == 0 then        -- "north"
    pos.z = pos.z - 1
  elseif pos.dir == 1 then    -- "east"
    pos.x = pos.x + 1
  elseif pos.dir == 2 then    -- "south"
    pos.z = pos.z + 1
  elseif pos.dir == 3 then    -- "west"
    pos.x = pos.x - 1
  end
end

-- PUBLIC: Turn left and update heading.
-- Note: turtle-only. Returns true/false.
function M.turnLeft(state)
  if not turtle then return false, "Not a turtle" end
  turtle.turnLeft()
  if state.pos then
    state.pos.dir = (state.pos.dir + 3) % 4
  end
  M.markDirty(state)
  return true
end

-- PUBLIC: Turn right and update heading.
function M.turnRight(state)
  if not turtle then return false, "Not a turtle" end
  turtle.turnRight()
  if state.pos then
    state.pos.dir = (state.pos.dir + 1) % 4
  end
  M.markDirty(state)
  return true
end

-- Helper: attempt to move forward, digging if necessary.
local function tryForward(state, networkTick)
  if not turtle then return false, "Not a turtle" end
  local attempts = 0
  while not turtle.forward() do
    attempts = attempts + 1
    if turtle.detect() then
      turtle.dig()
    else
      -- Something living, perhaps. Attempt to attack.
      turtle.attack()
    end
    if networkTick then networkTick() end
    if attempts > 10 then
      return false, "Blocked"
    end
  end
  if state.pos then advancePosForward(state.pos) end
  M.markDirty(state)
  return true
end

-- PUBLIC: Move forward with automatic digging.
function M.forward(state, networkTick)
  return tryForward(state, networkTick)
end

-- PUBLIC: Move up, digging if necessary.
function M.up(state, networkTick)
  if not turtle then return false, "Not a turtle" end
  local attempts = 0
  while not turtle.up() do
    attempts = attempts + 1
    if turtle.detectUp() then
      turtle.digUp()
    else
      turtle.attackUp()
    end
    if networkTick then networkTick() end
    if attempts > 10 then
      return false, "Blocked"
    end
  end
  if state.pos then
    state.pos.y = state.pos.y + 1
  end
  M.markDirty(state)
  return true
end

-- PUBLIC: Move down, digging if necessary.
function M.down(state, networkTick)
  if not turtle then return false, "Not a turtle" end
  local attempts = 0
  while not turtle.down() do
    attempts = attempts + 1
    if turtle.detectDown() then
      turtle.digDown()
    else
      turtle.attackDown()
    end
    if networkTick then networkTick() end
    if attempts > 10 then
      return false, "Blocked"
    end
  end
  if state.pos then
    state.pos.y = state.pos.y - 1
  end
  M.markDirty(state)
  return true
end

-- PUBLIC: Face a given direction (0..3) by turning.
function M.faceDir(state, dir, networkTick)
  if not turtle then return false, "Not a turtle" end
  while state.pos and state.pos.dir ~= dir do
    M.turnRight(state)
    if networkTick then networkTick() end
  end
  return true
end

-- PUBLIC: Go (relatively) to given coordinates (Manhattan path).
-- @target: table {x, y, z}
function M.goTo(state, target, networkTick)
  if not turtle then return false, "Not a turtle" end
  local pos = state.pos
  if not pos then return false, "No position" end

  -- Move vertically first
  while pos.y < target.y do
    local ok = M.up(state, networkTick)
    if not ok then return false, "Failed going up" end
    pos = state.pos
  end
  while pos.y > target.y do
    local ok = M.down(state, networkTick)
    if not ok then return false, "Failed going down" end
    pos = state.pos
  end

  -- X axis
  if target.x > pos.x then
    M.faceDir(state, 1, networkTick) -- east
  elseif target.x < pos.x then
    M.faceDir(state, 3, networkTick) -- west
  end
  while pos.x ~= target.x do
    local ok = M.forward(state, networkTick)
    if not ok then return false, "Failed moving X" end
    pos = state.pos
  end

  -- Z axis
  if target.z > pos.z then
    M.faceDir(state, 2, networkTick) -- south
  elseif target.z < pos.z then
    M.faceDir(state, 0, networkTick) -- north
  end
  while pos.z ~= target.z do
    local ok = M.forward(state, networkTick)
    if not ok then return false, "Failed moving Z" end
    pos = state.pos
  end
  return true
end

-- PUBLIC: Return to home position.
function M.returnHome(state, networkTick)
  if not state.home then return false, "No home set" end
  return M.goTo(state, state.home, networkTick)
end

-- PUBLIC: Update cached fuel level for turtles.
function M.updateFuel(state)
  if turtle then
    state.fuelLevel = turtle.getFuelLevel()
    M.markDirty(state)
  end
end

return M
