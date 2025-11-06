-- stem_core.lua
-- Glue logic: load state, drive network & roles, and keep the hive coherent.

local CONFIG   = require("stem_config")
local stateMod = require("stem_state")
local net      = require("stem_network")
local roles    = require("stem_roles")
local log      = require("stem_log")

local M = {}

-- Main entry for S.T.E.M.
function M.main(isFounder)
  log.info(
    "S.T.E.M v" .. CONFIG.version ..
    " starting (founder=" .. tostring(isFounder) ..
    ") on ID " .. os.getComputerID()
  )

  local state = stateMod.load(isFounder)
  stateMod.updateFuel(state)

  roles.decideInitialRole(state)
  stateMod.save(state)

  while true do
    roles.applyAssignedRole(state)
    stateMod.save(state)

    net.tick(state)
    stateMod.updateFuel(state)

    local ok, err = pcall(roles.runRoleLoop, state)
    if not ok then
      log.error("Role loop crashed: " .. tostring(err))
      os.sleep(2) -- pause a moment, then try again
    end
  end
end

return M
end

return M
