-- stem_core.lua
-- Glue logic: load state, drive network & roles, and keep the hive coherent.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")
local roles    = require("stem_roles")

local M = {}

-- PUBLIC: Main entry for S.T.E.M.
-- @isFounder: boolean, true when launched as the very first node via stem_boot.
function M.main(isFounder)
  print("S.T.E.M v" .. CONFIG.version ..
        " starting on ID " .. os.getComputerID() ..
        (isFounder and " (founder)" or ""))

  local state = stateMod.load(isFounder)
  stateMod.updateFuel(state)

  roles.decideInitialRole(state)
  stateMod.save(state)

  -- Main orchestration loop. Each iteration runs the appropriate role loop,
  -- which blocks until the role is changed (e.g. by a controller).
  while true do
    roles.applyAssignedRole(state)
    stateMod.save(state) -- ensure we persist role changes immediately

    net.tick(state)      -- allow the hive to notice us quickly
    stateMod.updateFuel(state)

    roles.runRoleLoop(state)

    -- After each role loop returns, state.role may have changed; loop again.
  end
end

return M
