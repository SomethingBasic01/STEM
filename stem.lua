--[[
S.T.E.M. – Self-Teaching Emergent Machine
========================================

README (short)

Overview
--------
S.T.E.M. is a multi-file CC:Tweaked / Plethora “hive mind” system for turtles
and computers. After the first manual launch, nodes mine, coordinate, and
cooperate over a wireless network.

Files
-----
Place the following files in the computer/turtle's root directory:

  stem.lua              (this file, main entry)
  stem_boot.lua         (tiny bootstrap used on NEW turtles)
  stem_config.lua
  stem_state.lua
  stem_network.lua
  stem_roles.lua
  stem_mining.lua
  stem_combat.lua
  stem_stronghold.lua

Data directory (created automatically):
  /stem_data/state.json      - per-node persistent state
  /stem_data/registry.json   - last known hive registry

How to start
------------
On **the very first / founder turtle or computer**:
  1. Copy ALL the Lua files above.
  2. Ensure the machine has:
       - A wireless modem attached.
       - Some fuel (coal/charcoal/logs) for turtles.
       - A chest under or in front of the turtle at "home" is recommended.
  3. Run:
       stem_boot

On **subsequent turtles**:
  1. You only need to copy **stem_boot.lua**.
  2. Place the turtle near the hive, attach a wireless modem, add fuel.
  3. Run:
       stem_boot
     It will download the latest S.T.E.M. files over the hive wireless network.

Which program actually “is” S.T.E.M.?
-------------------------------------
  - `stem_boot.lua` is the minimal bootstrap you run manually.
  - `stem.lua` is the main program entry.
  - Most logic lives in:
       * stem_core.lua (internal, required from here)
       * stem_network.lua
       * stem_roles.lua
       * stem_mining.lua
       * stem_combat.lua
       * stem_stronghold.lua

Assumptions
-----------
  - Environment:
      * Minecraft 1.12.2
      * CC:Tweaked 1.89.x
      * Plethora 1.2.x (optional, for better sensing)
  - Turtles:
      * Have a wireless modem on some side.
      * Have at least a wooden pickaxe or better in their tool slot.
      * Have some initial fuel.
  - Computers:
      * Have a wireless modem.
      * Are stationary "controllers" once the hive is large enough.

Run-safety & ethics
-------------------
The configuration (`stem_config.lua`) contains:
  - radius/depth limits for mining
  - whether soldiers may attack players (off by default)
  - how many stronghold turtles to maintain, etc.

Please adjust those before turning the hive loose on your world.

--]]

local ok, core = pcall(require, "stem_core")
if not ok then
  print("S.T.E.M: Failed to load stem_core.lua: " .. tostring(core))
  print("Ensure all STEM files are present.")
  return
end

-- Main entry point. Accepts an optional argument "founder" from stem_boot.
local args = {...}
local isFounder = args[1] == "founder"

core.main(isFounder)
