-- stem_stronghold.lua
-- Stronghold turtles: hide away as backup seeds and wake if hive collapses.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")

local M = {}

-- Determine whether hive looks "collapsed" enough to wake.
local function shouldWake()
  local registry = net.getRegistry()
  local total = 0
  local controllers = 0
  for _, info in pairs(registry) do
    total = total + 1
    if info.isController then controllers = controllers + 1 end
  end
  if total <= CONFIG.strongholdWakeHiveSize or controllers == 0 then
    return true
  end
  return false
end

-- Build a small 2x2x2 chamber around current position.
local function carveChamber(state)
  if not turtle then return end
  -- Carve current block and one ahead, up and down.
  turtle.dig()
  turtle.digUp()
  turtle.digDown()
  stateMod.forward(state, function() net.tick(state) end)
  turtle.digUp()
  turtle.digDown()
  -- Turn and carve sideways a little.
  stateMod.turnLeft(state)
  turtle.dig()
  stateMod.turnRight(state)
end

-- Place a chest below if possible and drop off items.
local function stashSupplies()
  if not turtle then return end
  -- Try to place chest below (assuming one is in inventory).
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name and detail.name:find("chest") then
      turtle.select(slot)
      if turtle.placeDown() then
        for s = 1, 16 do
          turtle.select(s)
          if turtle.getItemCount(s) > 0 then
            turtle.dropDown()
          end
        end
        return
      end
    end
  end
end

-- Dig down some distance, but respect max depth.
local function goDeep(state)
  if not turtle then return end
  local targetY = state.home.y - CONFIG.maxDepth
  while state.pos.y > targetY do
    stateMod.down(state, function() net.tick(state) end)
  end
end

-----------------------------------------------------------------------
-- PUBLIC: Stronghold behaviour.
-----------------------------------------------------------------------

function M.run(state)
  if not turtle then
    print("S.T.E.M: Stronghold role requires a turtle.")
    os.sleep(5)
    return
  end

  print("S.T.E.M: Stronghold loop started.")

  state.stronghold = state.stronghold or { initialised = false, dormant = false }
  local sh = state.stronghold

  if not sh.initialised then
    print("S.T.E.M: Travelling to deep level for stronghold.")
    goDeep(state)
    carveChamber(state)
    stashSupplies()
    sh.initialised = true
    sh.dormant = true
    stateMod.markDirty(state)
    stateMod.save(state)
  end

  -- Dormant loop: wake if hive collapses.
  while state.role == "stronghold" do
    net.tick(state)
    stateMod.updateFuel(state)
    stateMod.periodicSave(state)

    if _G.__STEM_ASSIGN_ROLE and _G.__STEM_ASSIGN_ROLE ~= state.role then
      break
    end

    if shouldWake() then
      print("S.T.E.M: Stronghold waking – hive appears collapsed.")
      -- Promote ourselves to miner and rejoin the world.
      state.role = "miner"
      stateMod.markDirty(state)
      stateMod.save(state)
      return
    end

    os.sleep(CONFIG.strongholdHeartbeatSlow)
  end

  print("S.T.E.M: Stronghold loop exiting; role changed.")
end

return M
