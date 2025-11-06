-- stem_config.lua
-- Global configuration for S.T.E.M.

local CONFIG = {
  version = "0.1.0",

  -- Networking
  protocol     = "STEM_HIVE",
  bootProtocol = "STEM_BOOT",

  -- File & directory layout
  dataDir      = "/stem_data",
  stateFile    = "/stem_data/state.json",
  registryFile = "/stem_data/registry.json",

  -- List of core program files for hive distribution to new turtles
  files = {
    "stem.lua",
    "stem_core.lua",
    "stem_config.lua",
    "stem_state.lua",
    "stem_network.lua",
    "stem_roles.lua",
    "stem_mining.lua",
    "stem_combat.lua",
    "stem_stronghold.lua",
    "stem_boot.lua",
    "stem_log.lua",
  },

  -- Heartbeat & registry
  heartbeatInterval = 5,
  nodeTimeout       = 45,
  saveInterval      = 30,

  -- Mining & navigation
  maxMiningRadius   = 64,     -- max Manhattan distance from home
  maxDepth          = 32,     -- max depth below home Y (relative) to dig
  refuelAt          = 200,
  minFuelToMine     = 400,
  fuelItems = {
    ["minecraft:coal"]        = true,
    ["minecraft:coal_block"]  = true,
    ["minecraft:charcoal"]    = true,
    ["minecraft:log"]         = true,
    ["minecraft:log2"]        = true,
  },

  -- Hive composition / roles
  roleRatios = {
    miner      = 0.50,
    hauler     = 0.15,
    crafter    = 0.10,
    soldier    = 0.10,
    stronghold = 0.15,
  },

  -- Combat / soldiers
  allowPlayerAttacks    = false,
  soldierUnlockHiveSize = 6,
  soldierPatrolRadius   = 16,
  soldierChaseRadius    = 24,
  soldierLowFuel        = 200,
  soldierLowHealthRatio = 0.3,

  -- Strongholds
  strongholdCount         = 2,
  strongholdHeartbeatSlow = 15,
  strongholdWakeHiveSize  = 3,

  -- Optional home area bounds (relative to home)
  homeRegionBounds = nil,

  -- Logging
  logFile      = "/stem_data/stem.log",
  logToConsole = true,   -- mirror important log lines to screen
  logVerbose   = true,   -- INFO messages as well
  logDebug     = false,  -- set true if you want very spammy debug output
}

return CONFIG
  maxDepth          = 32,     -- max depth below home Y (relative) to dig
  refuelAt          = 200,    -- if fuel falls below this, attempt refuel
  minFuelToMine     = 400,    -- refuse to go mining if fuel < this
  fuelItems = {
    ["minecraft:coal"]        = true,
    ["minecraft:coal_block"]  = true,
    ["minecraft:charcoal"]    = true,
    ["minecraft:log"]         = true,
    ["minecraft:log2"]        = true,
  },

  -- Hive composition / roles
  roleRatios = {
    miner      = 0.50,
    hauler     = 0.15,
    crafter    = 0.10,
    soldier    = 0.10,
    stronghold = 0.15,
  },

  -- Combat / soldiers
  allowPlayerAttacks   = false,
  soldierUnlockHiveSize = 6,
  soldierPatrolRadius   = 16,
  soldierChaseRadius    = 24,
  soldierLowFuel        = 200,
  soldierLowHealthRatio = 0.3, -- with Plethora's introspection, if available

  -- Strongholds
  strongholdCount         = 2,   -- how many stronghold turtles the hive wants
  strongholdHeartbeatSlow = 15,  -- seconds between stronghold heartbeats
  strongholdWakeHiveSize  = 3,   -- wake up if hive drops to at or below this

  -- Optional home area bounds (relative to home)
  -- Set to nil to disable.
  homeRegionBounds = nil,
  -- Example:
  -- homeRegionBounds = {
  --   xMin = -100, xMax = 100,
  --   zMin = -100, zMax = 100,
  -- }

}

return CONFIG
