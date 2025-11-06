-- stem_combat.lua
-- Soldier turtles: patrol and hunt nearby hostile entities if equipped.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")

local M = {}

-----------------------------------------------------------------------
-- Plethora sensor discovery
-----------------------------------------------------------------------

local function findEntitySensor()
  if not peripheral or not peripheral.getNames then return nil end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t == "plethora:sensor" or t == "sensor" then
      local ok, p = pcall(peripheral.wrap, name)
      if ok and p and p.sense then
        return p, name
      end
    end
  end
  return nil
end

local function isPlayer(ent)
  if not ent or type(ent) ~= "table" then return false end
  if ent.name == "player" or ent.name == "minecraft:player" then return true end
  if ent.type == "PLAYER" then return true end
  return false
end

local function isHostileMob(ent)
  if not ent or not ent.name then return false end
  local n = ent.name
  -- Crude but serviceable list.
  if n:find("zombie") or n:find("skeleton") or n:find("creeper")
     or n:find("spider") or n:find("witch") or n:find("slime")
     or n:find("enderman") then
    return true
  end
  return false
end

-- Choose best target given entities list.
local function pickTarget(entities)
  local best, bestDist = nil, nil
  for _, ent in ipairs(entities) do
    local dx, dy, dz = ent.x or ent.dx or 0, ent.y or ent.dy or 0, ent.z or ent.dz or 0
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if isHostileMob(ent) or (CONFIG.allowPlayerAttacks and isPlayer(ent)) then
      if not best or dist < bestDist then
        best, bestDist = ent, dist
      end
    end
  end
  return best, bestDist
end

-----------------------------------------------------------------------
-- Movement / chasing
-----------------------------------------------------------------------

local function moveRandom(state)
  if not turtle then return end
  local r = math.random(1, 4)
  if r == 1 then
    stateMod.turnLeft(state)
  elseif r == 2 then
    stateMod.turnRight(state)
  end
  stateMod.forward(state, function() net.tick(state) end)
end

local function moveTowardsRelative(state, target)
  if not turtle then return end
  local dx = target.x or target.dx or 0
  local dz = target.z or target.dz or 0
  local adx, adz = math.abs(dx), math.abs(dz)

  if adx > adz then
    -- Move along X.
    if dx > 0 then
      stateMod.faceDir(state, 1, function() net.tick(state) end)
    else
      stateMod.faceDir(state, 3, function() net.tick(state) end)
    end
  else
    -- Move along Z.
    if dz > 0 then
      stateMod.faceDir(state, 2, function() net.tick(state) end)
    else
      stateMod.faceDir(state, 0, function() net.tick(state) end)
    end
  end
  stateMod.forward(state, function() net.tick(state) end)
end

-----------------------------------------------------------------------
-- PUBLIC: Run soldier loop until role changes.
-----------------------------------------------------------------------

function M.run(state)
  if not turtle then
    print("S.T.E.M: Soldier role requires a turtle.")
    os.sleep(5)
    return
  end

  print("S.T.E.M: Soldier loop started.")
  local sensor = findEntitySensor()
  if sensor then
    print("S.T.E.M: Plethora sensor found for soldier.")
  else
    print("S.T.E.M: No Plethora sensor; soldier will fight only nearby foes.")
  end

  while state.role == "soldier" do
    net.tick(state)
    stateMod.updateFuel(state)
    stateMod.periodicSave(state)

    if _G.__STEM_ASSIGN_ROLE and _G.__STEM_ASSIGN_ROLE ~= state.role then
      break
    end

    -- If fuel is critically low, retreat home.
    if state.fuelLevel and state.fuelLevel < CONFIG.soldierLowFuel then
      print("S.T.E.M: Soldier fuel low; retreating to home.")
      stateMod.returnHome(state, function() net.tick(state) end)
      os.sleep(2)
      -- Try to refuel like miners do; here we just hope someone helps us.
    end

    -- Attack anything adjacent.
    turtle.attack()
    turtle.attackUp()
    turtle.attackDown()

    if sensor then
      local ok, entities = pcall(sensor.sense)
      if ok and type(entities) == "table" then
        local target, dist = pickTarget(entities)
        if target and dist and dist <= CONFIG.soldierChaseRadius then
          if dist > 1 then
            moveTowardsRelative(state, target)
          else
            turtle.attack()
            turtle.attackUp()
            turtle.attackDown()
          end
        else
          -- Patrol randomly around home within radius.
          if state.pos and state.home then
            local dx = state.pos.x - state.home.x
            local dz = state.pos.z - state.home.z
            local distHome = math.sqrt(dx*dx + dz*dz)
            if distHome > CONFIG.soldierPatrolRadius then
              stateMod.returnHome(state, function() net.tick(state) end)
            else
              moveRandom(state)
            end
          else
            moveRandom(state)
          end
        end
      else
        moveRandom(state)
      end
    else
      -- No sensor: mild patrol.
      moveRandom(state)
    end

    os.sleep(0.2)
  end

  print("S.T.E.M: Soldier loop exiting; role changed.")
end

return M
