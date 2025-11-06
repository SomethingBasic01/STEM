-- stem_roles.lua
-- Role assignment, basic scheduler, and role orchestration.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")

local mining      = require("stem_mining")
local combat      = require("stem_combat")
local stronghold  = require("stem_stronghold")

local M = {}

-----------------------------------------------------------------------
-- Message handlers
-----------------------------------------------------------------------

-- Handle assign_role message from a controller.
net.on("assign_role", function(senderId, msg)
  local payload = msg.payload or {}
  local newRole = payload.role
  if not newRole then return end
  print(("S.T.E.M: Controller %d assigned role '%s'"):format(senderId, newRole))
  -- We don't change state here; the core loop passes state into us.
  _G.__STEM_ASSIGN_ROLE = newRole  -- crude but effective cross-module signalling
end)

-----------------------------------------------------------------------
-- Initial role selection
-----------------------------------------------------------------------

-- PUBLIC: Decide an initial role if none is set yet.
function M.decideInitialRole(state)
  if state.role then return end

  if state.kind == "computer" then
    state.role = "controller"
  else
    -- Turtle. Founder becomes miner-leader; others default to miner.
    if state.isFounder then
      state.role = "miner"
    else
      state.role = "miner"
    end
  end
  print("S.T.E.M: Initial role: " .. state.role)
  stateMod.markDirty(state)
end

-----------------------------------------------------------------------
-- Scheduler (runs on controllers)
-----------------------------------------------------------------------

-- Helper: count roles in registry.
local function countRoles(registry)
  local counts = {}
  local total  = 0
  for _, info in pairs(registry) do
    local r = info.role or "unknown"
    counts[r] = (counts[r] or 0) + 1
    total = total + 1
  end
  return counts, total
end

-- Helper: find candidate node to reassign.
local function findReassignCandidates(registry, fromRole)
  local out = {}
  for id, info in pairs(registry) do
    if info.role == fromRole and info.kind == "turtle" then
      table.insert(out, id)
    end
  end
  return out
end

-- PUBLIC: Scheduler tick – called only when state.role == "controller".
-- Decides which nodes should be re-assigned to approach target role ratios.
function M.schedulerTick(state)
  local registry = net.getRegistry()
  local counts, total = countRoles(registry)
  if total == 0 then return end

  -- Compute desired counts per role.
  local desired = {}
  for role, ratio in pairs(CONFIG.roleRatios) do
    desired[role] = math.floor(total * ratio + 0.5)
  end

  -- No soldiers until hive is large enough.
  if total < CONFIG.soldierUnlockHiveSize then
    desired["soldier"] = 0
  end

  -- Ensure we aim for a fixed number of strongholds.
  desired["stronghold"] = math.max(CONFIG.strongholdCount, desired["stronghold"] or 0)

  -- For each role deficit, try to steal nodes from over-represented roles.
  local roles = { "miner", "hauler", "crafter", "soldier", "stronghold" }

  for _, role in ipairs(roles) do
    local have = counts[role] or 0
    local want = desired[role] or 0
    local deficit = want - have
    if deficit > 0 then
      -- We need more of this role.
      for _, fromRole in ipairs(roles) do
        if fromRole ~= role then
          local fromHave = counts[fromRole] or 0
          local fromWant = desired[fromRole] or 0
          local surplus = fromHave - fromWant
          if surplus > 0 then
            local candidates = findReassignCandidates(registry, fromRole)
            for _, id in ipairs(candidates) do
              if deficit <= 0 then break end
              print(("S.T.E.M: Reassigning node %d from %s to %s"):format(id, fromRole, role))
              net.send(id, "assign_role", { role = role, reason = "scheduler" })
              counts[fromRole] = counts[fromRole] - 1
              counts[role]      = counts[role] + 1
              deficit = deficit - 1
            end
          end
        end
        if deficit <= 0 then break end
      end
    end
  end
end

-----------------------------------------------------------------------
-- Role runners
-----------------------------------------------------------------------

-- PUBLIC: Apply any pending assign_role from controller.
function M.applyAssignedRole(state)
  if _G.__STEM_ASSIGN_ROLE then
    local newRole = _G.__STEM_ASSIGN_ROLE
    _G.__STEM_ASSIGN_ROLE = nil
    if newRole ~= state.role then
      print(("S.T.E.M: Changing role from %s to %s"):format(tostring(state.role), newRole))
      state.role = newRole
      stateMod.markDirty(state)
    end
  end
end

-- PUBLIC: Run role loop (blocks until role changes).
function M.runRoleLoop(state)
  if state.role == "controller" then
    -- Controller: mostly thinking, not moving.
    while state.role == "controller" do
      net.tick(state)
      stateMod.updateFuel(state)
      stateMod.periodicSave(state)
      M.applyAssignedRole(state)
      M.schedulerTick(state)
      os.sleep(0.5)
    end

  elseif state.role == "miner" then
    mining.run(state)

  elseif state.role == "soldier" then
    combat.run(state)

  elseif state.role == "stronghold" then
    stronghold.run(state)

  elseif state.role == "hauler" or state.role == "crafter" then
    -- For now, hauler/crafter behave like miners but tend to stay nearer home.
    mining.run(state)

  else
    -- Idle / unknown: just sit in a modestly dignified fashion.
    print("S.T.E.M: No role assigned; idling.")
    while state.role == nil or state.role == "idle" do
      net.tick(state)
      stateMod.updateFuel(state)
      stateMod.periodicSave(state)
      M.applyAssignedRole(state)
      os.sleep(1)
    end
  end
end

return M
