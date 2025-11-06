-- stem_mining.lua
-- Simple but robust branch mining behaviour for S.T.E.M. miners.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")

local M = {}

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

-- Attempt to refuel using items in inventory.
local function tryRefuel(state)
  if not turtle then return end
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and CONFIG.fuelItems[detail.name] then
      turtle.select(slot)
      turtle.refuel(1)
      stateMod.updateFuel(state)
      if state.fuelLevel >= CONFIG.minFuelToMine then
        return
      end
    end
  end
end

-- Return home and dump items into chest (below or in front), else drop.
local function offloadAtHome(state)
  if not turtle then return end
  print("S.T.E.M: Returning home to offload.")
  stateMod.returnHome(state, function() net.tick(state) end)

  -- Prefer chest below, then in front.
  local function dumpAll(fnPlaceDetect, fnDrop)
    for slot = 1, 16 do
      turtle.select(slot)
      if turtle.getItemCount(slot) > 0 then
        fnDrop()
      end
    end
  end

  if turtle.detectDown() then
    local ok, block = turtle.inspectDown()
    if ok and block.name and block.name:find("chest") then
      dumpAll(turtle.detectDown, turtle.dropDown)
      return
    end
  end
  if turtle.detect() then
    local ok, block = turtle.inspect()
    if ok and block.name and block.name:find("chest") then
      dumpAll(turtle.detect, turtle.drop)
      return
    end
  end

  -- No chest found; drop in front.
  dumpAll(turtle.detect, turtle.drop)
end

-- Ensure sufficient fuel, optionally going home if low.
local function ensureFuel(state)
  if not turtle then return true end
  stateMod.updateFuel(state)
  if state.fuelLevel >= CONFIG.minFuelToMine then return true end

  tryRefuel(state)
  stateMod.updateFuel(state)
  if state.fuelLevel >= CONFIG.minFuelToMine then return true end

  if state.fuelLevel < CONFIG.refuelAt then
    print("S.T.E.M: Fuel low; returning home for refuel.")
    stateMod.returnHome(state, function() net.tick(state) end)
    tryRefuel(state)
    stateMod.updateFuel(state)
  end
  return state.fuelLevel >= CONFIG.minFuelToMine
end

-- Check if inventory is nearly full.
local function inventoryNearlyFull()
  if not turtle then return false end
  local free = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      free = free + 1
    end
  end
  return free <= 2
end

-- Ensure we are within configured mining radius from home.
local function withinMiningBounds(state)
  if not CONFIG.homeRegionBounds then return true end
  if not state.pos or not state.home then return true end
  local dx = state.pos.x - state.home.x
  local dz = state.pos.z - state.home.z
  local bounds = CONFIG.homeRegionBounds
  return dx >= bounds.xMin and dx <= bounds.xMax and
         dz >= bounds.zMin and dz <= bounds.zMax
end

-- Initialise mining state.
local function initMiningState(state)
  if state.mining then return end
  state.mining = {
    branchIndex = 0,
    stepInBranch = 0,
    goingForward = true,
  }
  stateMod.markDirty(state)
end

-----------------------------------------------------------------------
-- Branch-mining pattern
-----------------------------------------------------------------------

-- Perform one mining “step” within our branch pattern.
local function miningStep(state)
  if not turtle then
    print("S.T.E.M: Miner role requires a turtle.")
    os.sleep(5)
    return
  end

  initMiningState(state)
  local ms = state.mining

  if not withinMiningBounds(state) then
    print("S.T.E.M: Out of mining bounds; returning home.")
    stateMod.returnHome(state, function() net.tick(state) end)
    ms.branchIndex = 0
    ms.stepInBranch = 0
    ms.goingForward = true
    stateMod.markDirty(state)
    return
  end

  if inventoryNearlyFull() then
    offloadAtHome(state)
    ms.stepInBranch = 0
    ms.goingForward = true
    stateMod.markDirty(state)
    return
  end

  if not ensureFuel(state) then
    print("S.T.E.M: Cannot mine; insufficient fuel.")
    os.sleep(10)
    return
  end

  -- Simple pattern:
  --  * From home, dig a main corridor along +X.
  --  * Every 4 blocks, dig a branch along +/-Z.

  -- Ensure we start facing +X (dir=1 in our relative system).
  if state.pos.dir ~= 1 then
    stateMod.faceDir(state, 1, function() net.tick(state) end)
  end

  -- Move one step forward along the main corridor.
  local ok, err = stateMod.forward(state, function() net.tick(state) end)
  if not ok then
    print("S.T.E.M: Mining forward blocked: " .. tostring(err))
    os.sleep(1)
    return
  end

  ms.stepInBranch = ms.stepInBranch + 1

  -- Periodically cut a side branch.
  if ms.stepInBranch % 4 == 0 then
    -- Alternate branches left and right along Z.
    local left = (ms.branchIndex % 2 == 0)
    ms.branchIndex = ms.branchIndex + 1

    -- Turn into branch.
    if left then
      stateMod.turnLeft(state)
    else
      stateMod.turnRight(state)
    end

    -- Dig branch up to some depth or depth limit.
    for i = 1, 6 do
      if not withinMiningBounds(state) then break end
      if not ensureFuel(state) then break end
      local ok2 = stateMod.forward(state, function() net.tick(state) end)
      if not ok2 then break end
      -- Optional: mine up/down too for a 1x2x2 tunnel.
      turtle.digUp()
      turtle.digDown()
    end

    -- Return to main corridor.
    -- Turn around.
    stateMod.turnLeft(state)
    stateMod.turnLeft(state)
    for i = 1, 6 do
      if not stateMod.forward(state, function() net.tick(state) end) then break end
    end

    -- Face +X again.
    if left then
      stateMod.turnRight(state)
    else
      stateMod.turnLeft(state)
    end
  end
end

-----------------------------------------------------------------------
-- PUBLIC: Run mining loop until role changes.
-----------------------------------------------------------------------

function M.run(state)
  print("S.T.E.M: Miner loop started.")
  while state.role == "miner" or state.role == "hauler" or state.role == "crafter" do
    net.tick(state)
    stateMod.updateFuel(state)
    stateMod.periodicSave(state)

    -- Respect any role reassignment.
    if _G.__STEM_ASSIGN_ROLE and _G.__STEM_ASSIGN_ROLE ~= state.role then
      return
    end

    miningStep(state)
    os.sleep(0.1)
  end
  print("S.T.E.M: Miner loop exiting; role changed.")
end

return M
