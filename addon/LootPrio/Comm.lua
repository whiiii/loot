--[[
  LootPrio — messages inside the raid.

  Addons talk to each other on their own channel. One message is at most
  255 bytes, so long lists are split into parts.

  Receivers do not trust the sender blindly: only an officer may open a
  distribution, and only that distribution's master may act on it. Every
  check is made on the receiving machine from the game's own data, never
  from the message body.
]]

local ADDON, NS = ...

local PREFIX = "LOOTPRIO1"

NS.Comm = {}

local function channel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

function NS.Comm.Send(messageType, payload)
  local target = channel()
  if not target then return end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end

  C_ChatInfo.SendAddonMessage(PREFIX, messageType .. " " .. (payload or ""), target)
end

-- Receiving ----------------------------------------------------------------

function NS.Comm.Handle(messageType, body, sender)
  if messageType == "SESSION" then
    -- Only an officer opens a distribution. Otherwise anyone could pop a
    -- response window on the whole raid.
    if not NS.IsOfficer(sender) then return end

    local sessionId, visibility, list = body:match("^(%S+)%s+(%S+)%s+(.*)$")
    if not sessionId then return end

    local items = {}
    for index, itemId in list:gmatch("(%d+):(%d+)") do
      items[#items + 1] = {
        index = tonumber(index),
        itemId = tonumber(itemId),
      }
    end

    NS.IncomingSession(sessionId, visibility, items, sender)

  elseif messageType == "RESPONSE" then
    local sessionId, index, code = body:match("^(%S+)%s+(%d+)%s+(%S+)$")
    if not sessionId then return end

    -- A response is always recorded under the sender's name, never from
    -- the message body. That way nobody can answer for someone else.
    NS.RecordResponse(sessionId, tonumber(index), sender, code)

  elseif messageType == "ROLL" then
    -- The roll is made by whoever opened the distribution, so everyone
    -- sees the same number.
    if not NS.IsDistributor(sender) then return end

    local sessionId, index, player, roll =
      body:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%d+)$")
    if not sessionId then return end

    NS.RecordRoll(sessionId, tonumber(index), player, tonumber(roll))

  elseif messageType == "AWARDED" then
    -- Only this distribution's master. Officer rank is enough to open a
    -- distribution, not to give away items in someone else's.
    if not NS.IsDistributor(sender) then return end

    local sessionId, index, winner, code, roll =
      body:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+)$")
    if not sessionId then return end

    NS.RecordAward(sessionId, tonumber(index), winner, code, tonumber(roll))

  elseif messageType == "CLOSE" then
    if not NS.IsDistributor(sender) then return end
    NS.ResponsesClosed(body:match("^(%S+)"))

  elseif messageType == "UNDO" then
    if not NS.IsDistributor(sender) then return end

    local sessionId, index = body:match("^(%S+)%s+(%d+)$")
    if not sessionId then return end
    if NS.session and NS.session.id == sessionId then
      NS.UndoAward(tonumber(index), sender)
    end

  elseif messageType == "TAKEOVER" then
    -- Only the raid leader may take over a distribution. The check is
    -- made on every machine from the raid rank, not the message body.
    if not NS.IsLeader(sender) then return end
    NS.DistributorChanged(body:match("^(%S+)"), sender)

  elseif messageType == "END" then
    -- Ended by whoever is distributing. If the master has vanished, the
    -- leader takes over first and ends it after that.
    if not NS.IsDistributor(sender) then return end
    NS.SessionEnded(body:match("^(%S+)"))

  elseif messageType == "ASK" then
    -- Anyone may ask: the answer only tells a version, and hiding it
    -- would help nobody.
    --
    -- Spread out in time: 40 simultaneous replies would flood the channel
    -- and some would be dropped, making the list show addons as missing.
    C_Timer.After(math.random() * 3, NS.SendVersion)

  elseif messageType == "VERSION" then
    local version, profileCount, ownProfile =
      body:match("^(%S+)%s+(%d+)%s+(%d)$")
    if not version then return end

    NS.RecordVersion(sender, version, tonumber(profileCount), ownProfile == "1")
  end
end

--------------------------------------------------------------------------
-- Version handshake
--------------------------------------------------------------------------

--- Who in the raid has the addon and which version.
---
--- Per session rather than saved: the question is what the situation is
--- right now, and last week's answer would only mislead.
NS.addons = {}

--- Our own version and profile status, to the raid.
---
--- The profile count tells whether the export has been imported at all,
--- and the presence of one's own profile tells why the LootPrio button is
--- greyed out. Both are reasons a distribution looks broken while nothing
--- is actually broken.
function NS.SendVersion()
  -- A roster event can fire before the saved data has loaded.
  if not NS.db then return end

  local count = 0
  for _ in pairs(NS.db.profiles) do count = count + 1 end

  local own = NS.db.profiles[NS.MyName()] and "1" or "0"

  NS.Comm.Send("VERSION", ("%s %d %s"):format(NS.VERSION, count, own))
  NS.RecordVersion(NS.MyName(), NS.VERSION, count, own == "1")
end

function NS.RecordVersion(name, version, profileCount, ownProfile)
  NS.addons[name] = {
    version = version,
    profileCount = profileCount or 0,
    ownProfile = ownProfile and true or false,
    time = GetTime(),
  }

  if NS.RefreshView then NS.RefreshView("members") end
end

--- Asks everyone for their version.
function NS.AskVersions()
  wipe(NS.addons)
  NS.Comm.Send("ASK", "")
  NS.SendVersion()
end

--- Compares version numbers part by part.
---
--- A string comparison would hold only while the numbers are one
--- character long: "0.10" would otherwise sort below "0.9".
function NS.VersionOlder(a, b)
  local function parts(v)
    local list = {}
    for n in tostring(v or ""):gmatch("%d+") do list[#list + 1] = tonumber(n) end
    return list
  end

  local x, z = parts(a), parts(b)
  for i = 1, math.max(#x, #z) do
    local p, q = x[i] or 0, z[i] or 0
    if p ~= q then return p < q end
  end

  return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

-- We announce our version when joining a raid, but sparingly: the roster
-- changes dozens of times while a raid forms, and not every change is a
-- reason to send anything.
local lastAnnounced = 0

frame:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
  if event == "GROUP_ROSTER_UPDATE" then
    if not IsInGroup() then
      wipe(NS.addons)
      return
    end

    if GetTime() - lastAnnounced > 60 then
      lastAnnounced = GetTime()
      C_Timer.After(2, NS.SendVersion)
    end
    return
  end

  if prefix ~= PREFIX then return end

  -- The sender's name into the profiles' form: NS.Name also drops the
  -- realm. That way responses are recorded under the same name as the
  -- profiles, and the same player never appears as two rows.
  local name = sender and NS.Name(sender) or ""
  if name == "" then return end

  local messageType, body = message:match("^(%S+)%s*(.-)$")
  if not messageType then return end

  -- Our own messages are skipped: they were handled when sent.
  if name == NS.MyName() then return end

  NS.Comm.Handle(messageType, body, name)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end
