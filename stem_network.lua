-- stem_network.lua
-- Wireless networking, registry handling, and boot-time file serving.

local CONFIG = require("stem_config")

local M = {}

local modemSide = nil
local nodeId    = os.getComputerID()
local registry  = {}   -- nodeId -> { id, role, pos, fuel, lastSeen, kind, isController }
local lastHeartbeat = 0

-- Message handlers keyed by msg.type (for STEM protocol).
local handlers = {}

-- PUBLIC: Register a handler for a given message type.
-- @msgType: string
-- @fn(senderId, message) -> ()
function M.on(msgType, fn)
  handlers[msgType] = fn
end

-- INTERNAL: Find a modem (prefer wireless) and open rednet.
local function initModem()
  if not rednet then return end
  if rednet.isOpen() then return end

  local bestSide, bestWireless = nil, false
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      local isWireless = false
      pcall(function()
        isWireless = peripheral.call(side, "isWireless")
      end)
      if isWireless and not bestWireless then
        bestSide, bestWireless = side, true
      elseif not bestSide then
        bestSide = side
      end
    end
  end
  if bestSide then
    rednet.open(bestSide)
    modemSide = bestSide
    print("S.T.E.M: Modem opened on side " .. bestSide)
  else
    print("S.T.E.M: No modem found; hive networking disabled.")
  end
end

-- PUBLIC: Expose registry (read-only copy).
function M.getRegistry()
  local copy = {}
  for k, v in pairs(registry) do
    copy[k] = v
  end
  return copy
end

-- PUBLIC: Get hive size (number of known nodes).
function M.getHiveSize()
  local c = 0
  for _ in pairs(registry) do c = c + 1 end
  return c
end

-- PUBLIC: Get list of controller IDs.
function M.getControllers()
  local list = {}
  for id, info in pairs(registry) do
    if info.isController then
      table.insert(list, id)
    end
  end
  return list
end

-- PUBLIC: Get info for a node.
function M.getNodeInfo(id)
  return registry[id]
end

-- INTERNAL: Update registry with heartbeat information.
local function updateRegistryFromHeartbeat(msg)
  if not msg or type(msg) ~= "table" then return end
  local id = msg.fromId
  if not id then return end

  local info = registry[id] or {}
  info.id           = id
  info.role         = msg.payload.role
  info.kind         = msg.payload.kind
  info.isController = msg.payload.isController
  info.fuel         = msg.payload.fuel
  info.pos          = msg.payload.pos
  info.home         = msg.payload.home
  info.lastSeen     = os.clock()

  registry[id] = info
end

-- PUBLIC: Broadcast a message on the STEM protocol.
function M.broadcast(msgType, payload)
  if not modemSide or not rednet.isOpen(modemSide) then return false end
  local msg = {
    fromId = nodeId,
    toId   = nil,
    type   = msgType,
    payload = payload,
  }
  rednet.broadcast(msg, CONFIG.protocol)
  return true
end

-- PUBLIC: Send a unicast message.
function M.send(toId, msgType, payload)
  if not modemSide or not rednet.isOpen(modemSide) then return false end
  local msg = {
    fromId = nodeId,
    toId   = toId,
    type   = msgType,
    payload = payload,
  }
  rednet.send(toId, msg, CONFIG.protocol)
  return true
end

-- INTERNAL: Send heartbeat about this node.
local function sendHeartbeat(state)
  if not modemSide or not rednet.isOpen(modemSide) then return end
  local payload = {
    role         = state.role,
    kind         = state.kind,
    isController = (state.kind == "computer" and state.role == "controller"),
    fuel         = state.fuelLevel or 0,
    pos          = state.pos,
    home         = state.home,
  }
  local msg = {
    fromId = nodeId,
    toId   = nil,
    type   = "heartbeat",
    payload = payload,
  }
  rednet.broadcast(msg, CONFIG.protocol)
  lastHeartbeat = os.clock()
end

-- INTERNAL: Cull nodes that have not been seen recently.
local function cullStaleNodes()
  local now = os.clock()
  for id, info in pairs(registry) do
    if (now - (info.lastSeen or 0)) > CONFIG.nodeTimeout then
      print("S.T.E.M: Node " .. id .. " timed out.")
      registry[id] = nil
    end
  end
end

-- INTERNAL: Serve bootstrapping requests from new nodes.
local function handleBootMessage(senderId, msg)
  if type(msg) ~= "table" or not msg.type then return end
  if msg.type == "boot_discover" then
    -- Offer ourselves as a file source.
    local reply = {
      fromId = nodeId,
      type   = "boot_offer",
      payload = { version = CONFIG.version },
    }
    rednet.send(senderId, reply, CONFIG.bootProtocol)

  elseif msg.type == "file_list_request" then
    local reply = {
      fromId = nodeId,
      type   = "file_list",
      payload = { files = CONFIG.files, version = CONFIG.version },
    }
    rednet.send(senderId, reply, CONFIG.bootProtocol)

  elseif msg.type == "file_request" then
    local fileName = msg.payload and msg.payload.file
    if not fileName or not fs.exists(fileName) then
      local errReply = {
        fromId = nodeId,
        type   = "file_error",
        payload = { file = fileName, error = "missing" },
      }
      rednet.send(senderId, errReply, CONFIG.bootProtocol)
      return
    end

    local h = fs.open(fileName, "r")
    if not h then
      local errReply = {
        fromId = nodeId,
        type   = "file_error",
        payload = { file = fileName, error = "open_failed" },
      }
      rednet.send(senderId, errReply, CONFIG.bootProtocol)
      return
    end

    while true do
      local chunk = h.read(4096)
      local final = (chunk == nil)
      local reply = {
        fromId = nodeId,
        type   = "file_chunk",
        payload = {
          file  = fileName,
          data  = chunk or "",
          final = final,
        },
      }
      rednet.send(senderId, reply, CONFIG.bootProtocol)
      if final then break end
    end
    h.close()
  end
end

-- INTERNAL: Handle a STEM protocol message.
local function handleStemMessage(senderId, msg)
  if type(msg) ~= "table" or not msg.type then return end

  -- Always update registry on heartbeat.
  if msg.type == "heartbeat" then
    updateRegistryFromHeartbeat(msg)
  end

  -- Ignore messages not addressed to us (except heartbeats/broadcast).
  if msg.toId and msg.toId ~= nodeId then return end

  local handler = handlers[msg.type]
  if handler then
    handler(senderId, msg)
  end
end

-- PUBLIC: Tick networking.
--  * Sends heartbeat when necessary.
--  * Receives all queued messages on both protocols.
--  * Culls stale nodes.
function M.tick(state)
  initModem()
  if not modemSide or not rednet.isOpen(modemSide) then return end

  local now = os.clock()
  local interval = CONFIG.heartbeatInterval
  if state.role == "stronghold" then
    interval = CONFIG.strongholdHeartbeatSlow
  end

  if now - lastHeartbeat >= interval then
    sendHeartbeat(state)
  end

  -- Non-blocking receive for all protocols.
  while true do
    local senderId, message, protocol = rednet.receive(nil, 0)
    if not senderId then break end

    if protocol == CONFIG.protocol then
      handleStemMessage(senderId, message)
    elseif protocol == CONFIG.bootProtocol then
      handleBootMessage(senderId, message)
    end
  end

  cullStaleNodes()
end

return M
