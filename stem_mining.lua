-- stem_mining.lua
-- Improved mining behaviour for S.T.E.M.:
--  * Digs a vertical shaft under home down to a target depth.
--  * Performs branch mining at that depth.
--  * After some branches, increases the target depth (within maxDepth).
--  * Logs fuel issues, ore finds, depth changes, etc.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")
local log      = require("stem_log")

local M = {}

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

-- Attempt to refuel using inventory items.
local function tryRefuel(state)
  if not turtle then return end
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and CONFIG.fuelItems[detail.name] then
      turtle.select(slot)
      if turtle.refuel(1) then
        stateMod.updateFuel(state)
        log.info("Refuelled using " .. detail.name)
        if state.fuelLevel >= CONFIG.minFuelToMine then
          return
        end
      end
    end
  end
end

-- Return home and offload items into chest (below or in front), else drop.
local function offloadAtHome(state)
  if not turtle then return end
  log.info("Returning home to offload.")
  stateMod.returnHome(state, function() net.tick(state) end)

  local function dumpAll(dropFn)
    for slot = 1, 16 do
      turtle.select(slot)
      if turtle.getItemCount(slot) > 0 then
        dropFn()
      end
    end
  end

  if turtle.detectDown() then
    local ok, block = turtle.inspectDown()
    if ok and block.name and block.name:find("chest") then
      dumpAll(turtle.dropDown)
      return
    end
  end

  if turtle.detect() then
    local ok, block = turtle.inspect()
    if ok and block.name and block.name:find("chest") then
      dumpAll(turtle.drop)
      return
    end
  end

  dumpAll(turtle.drop)
end

-- Ensure enough fuel to mine; possibly returning home to refuel.
local function ensureFuel(state)
  if not turtle then return true end
  stateMod.updateFuel(state)
  if state.fuelLevel >= CONFIG.minFuelToMine then return true end

  tryRefuel(state)
  stateMod.updateFuel(state)
  if state.fuelLevel >= CONFIG.minFuelToMine then return true end

  if state.fuelLevel < CONFIG.refuelAt then
    log.warn("Fuel low; returning home to refuel.")
    stateMod.returnHome(state, function() net.tick(state) end)
    tryRefuel(state)
    stateMod.updateFuel(state)
  end

  if state.fuelLevel < CONFIG.minFuelToMine then
    log.warn("Unable to obtain sufficient fuel for mining.")
    return false
  end
  return true
end

-- Check if inventory is almost full.
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

-- Respect optional home-region bounds.
local function withinMiningBounds(state)
  if not CONFIG.homeRegionBounds then return true end
  if not state.pos or not state.home then return true end
  local dx = state.pos.x - state.home.x
  local dz = state.pos.z - state.home.z
  local b = CONFIG.homeRegionBounds
  return dx >= b.xMin and dx <= b.xMax and dz >= b.zMin and dz <= b.zMax
end

-- Initialise or upgrade mining state.
local function initMiningState(state)
  local ms = state.mining
  if ms and ms.version == 2 then return end
  state.mining = {
    version          = 2,
    phase            = "descend",    -- "descend" or "branch"
    desiredDepth     = math.min(CONFIG.maxDepth, 24),
    mainStep         = 0,
    branchIndex      = 0,
    branchesDone     = 0,
    branchesPerDepth = 6,            -- how many side-branches before going deeper
  }
  log.info("Initialising mining state; target depth " .. state.mining.desiredDepth)
  stateMod.markDirty(state)
end

-----------------------------------------------------------------------
-- Descend shaft under home
-----------------------------------------------------------------------

local function descendStep(state)
  if not turtle then return end
  local ms   = state.mining
  local home = state.home
  local pos  = state.pos
  if not home or not pos then return end

  local targetY = home.y - ms.desiredDepth
  if pos.y <= targetY then
    ms.phase = "branch"
    log.info("Reached work depth " .. targetY .. ", switching to branch mining.")
    stateMod.markDirty(state)
    return
  end

  -- First ensure we're above home (same X/Z).
  if pos.x ~= home.x or pos.z ~= home.z then
    stateMod.goTo(state, { x = home.x, y = pos.y, z = home.z },
      function() net.tick(state) end)
    return
  end

  -- Now dig down one block.
  local ok, err = stateMod.down(state, function() net.tick(state) end)
  if not ok then
    log.warn("descendStep: down failed: " .. tostring(err))
    os.sleep(1)
  end
end

-----------------------------------------------------------------------
-- Ore logging
-----------------------------------------------------------------------

local function recordOresAtCurrentPos(state)
  if not turtle or not state.pos or not state.home then return end
  local depth = state.home.y - state.pos.y

  local function checkBlock(ok, block)
    if ok and block and block.name then
      if block.name:find("ore") or block.name:find("coal") then
        log.info("Found ore " .. block.name .. " at relative depth " .. depth)
      end
    end
  end

  checkBlock(turtle.inspect())
  checkBlock(turtle.inspectDown())
  checkBlock(turtle.inspectUp())
end

-----------------------------------------------------------------------
-- Branch mining at working depth
-----------------------------------------------------------------------

local function branchStep(state)
  if not turtle then
    log.error("Miner role requires a turtle.")
    os.sleep(5)
    return
  end

  initMiningState(state)
  local ms = state.mining

  if not withinMiningBounds(state) then
    log.warn("Out of mining bounds; returning home.")
    stateMod.returnHome(state, function() net.tick(state) end)
    ms.mainStep     = 0
    ms.branchIndex  = 0
    ms.branchesDone = 0
    stateMod.markDirty(state)
    return
  end

  if inventoryNearlyFull() then
    offloadAtHome(state)
    ms.mainStep     = 0
    ms.branchIndex  = 0
    ms.branchesDone = 0
    stateMod.markDirty(state)
    return
  end

  if not ensureFuel(state) then
    os.sleep(10)
    return
  end

  -- Keep the main corridor along +X.
  if state.pos.dir ~= 1 then
    stateMod.faceDir(state, 1, function() net.tick(state) end)
  end

  local ok, err = stateMod.forward(state, function() net.tick(state) end)
  if not ok then
    log.warn("branchStep: forward blocked: " .. tostring(err))
    os.sleep(0.5)
    return
  end

  ms.mainStep = ms.mainStep + 1
  recordOresAtCurrentPos(state)

  -- Every few steps, cut a side branch.
  if ms.mainStep % 4 == 0 then
    local left = (ms.branchIndex % 2 == 0)
    ms.branchIndex  = ms.branchIndex + 1
    ms.branchesDone = ms.branchesDone + 1

    if left then stateMod.turnLeft(state) else stateMod.turnRight(state) end

    for i = 1, 6 do
      if not withinMiningBounds(state) then break end
      if not ensureFuel(state) then break end

      local ok2, err2 = stateMod.forward(state, function() net.tick(state) end)
      if not ok2 then
        log.warn("branchStep: branch forward blocked: " .. tostring(err2))
        break
      end

      turtle.digUp()
      turtle.digDown()
      recordOresAtCurrentPos(state)
    end

    -- Return to main corridor.
    stateMod.turnLeft(state)
    stateMod.turnLeft(state)
    for i = 1, 6 do
      local ok2 = stateMod.forward(state, function() net.tick(state) end)
      if not ok2 then break end
    end

    if left then
      stateMod.turnRight(state)
    else
      stateMod.turnLeft(state)
    end

    -- After enough branches at this depth, choose to go deeper.
    if ms.branchesDone >= ms.branchesPerDepth and ms.desiredDepth < CONFIG.maxDepth then
      ms.desiredDepth = math.min(CONFIG.maxDepth, ms.desiredDepth + 4)
      ms.phase        = "descend"
      ms.branchesDone = 0
      log.info("Completed branches at this depth; increasing desiredDepth to " .. ms.desiredDepth)
      stateMod.markDirty(state)
    end
  end
end

-----------------------------------------------------------------------
-- PUBLIC: Run mining loop until role changes.
-----------------------------------------------------------------------

function M.run(state)
  log.info("Miner loop started.")
  while state.role == "miner" or state.role == "hauler" or state.role == "crafter" do
    net.tick(state)
    stateMod.updateFuel(state)
    stateMod.periodicSave(state)

    if _G.__STEM_ASSIGN_ROLE and _G.__STEM_ASSIGN_ROLE ~= state.role then
      log.info("Role change detected; leaving miner loop.")
      return
    end

    initMiningState(state)

    if state.mining.phase == "descend" then
      descendStep(state)
    else
      branchStep(state)
    end

    os.sleep(0.1)
  end
  log.info("Miner loop exiting; role changed.")
end

return M
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
