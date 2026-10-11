--[[
  LootPrio — the distribution session.

  The session is the same for everyone: the master opens it, and every
  raider's addon builds the same view from it. Responses are sent to the
  raid, so the result and its reason are open.

  Who sees what during the voting is a visibility setting. Officers see
  every response so an item can be discussed before it is given; a raider
  sees their own answer and what has already been awarded.
]]

local ADDON, NS = ...

--- Response options. The order number decides the listing: lowest first.
NS.RESPONSES = {
  { code = "prio", name = "LootPrio",  order = 1, colour = "|cffc9a227" },
  { code = "main", name = "Main spec", order = 2, colour = "|cff8fd17a" },
  { code = "off",  name = "Off spec",  order = 3, colour = "|cff7fb3cc" },
  { code = "muu",  name = "Muu",       order = 4, colour = "|cffb0a99a" },
  { code = "pass", name = "Pass",      order = 5, colour = "|cff6b7278" },
}

NS.RESPONSE = {}
for _, r in ipairs(NS.RESPONSES) do NS.RESPONSE[r.code] = r end

--- The session. The same structure everywhere.
NS.session = nil

--------------------------------------------------------------------------
-- Opening a session
--------------------------------------------------------------------------

local function newSession(id, master, visibility)
  return {
    id = id,
    master = master,
    -- "raid" or "officers". The master's setting travels with the
    -- session, so nobody decides for themselves what they see.
    visibility = visibility or "raid",
    startedAt = GetTime(),
    items = {},
    ownResponse = {},
    selected = 1,
  }
end

--- Should other players' responses be shown to this player.
---
--- This is a visibility setting, not a secret: the data travels on the
--- raid channel and is on everyone's machine regardless. The setting only
--- decides whether it is drawn — a modified addon would still see it.
function NS.ShowAllResponses()
  local s = NS.session
  if not s then return true end
  if s.visibility == "raid" then return true end
  return NS.IsOfficer()
end

--- Is the named player this distribution's master.
---
--- Every act that affects the distribution is checked against this: the
--- roll, awarding, undoing and ending. Officer rank is enough to open a
--- distribution but not to act in one — otherwise another assist could
--- give away an item mid-distribution, and hiding the buttons from them
--- would be a view rather than a rule.
function NS.IsDistributor(name)
  local s = NS.session
  if not s then return false end
  return s.master == (name or NS.MyName())
end

--- Is a distribution running and owned by someone else.
---
--- The master is whoever opened the distribution. There is no separate
--- setting, because that would be one more thing to forget to update —
--- and it would end in an argument about whose name is on it. Opening is
--- an act, and the act is enough.
function NS.DistributionBusy()
  local s = NS.session
  if not s or s.test then return nil end
  if s.master == NS.MyName() then return nil end

  -- A fully awarded distribution reserves nothing: there is nothing left
  -- to decide.
  if #NS.OpenItems() == 0 then return nil end

  -- A master who has dropped offline does not reserve it either.
  -- Otherwise one broken connection would lock the night's distribution,
  -- and the only way out would be a takeover — which needs the leader,
  -- who is not necessarily around right then.
  if not NS.IsPresent(s.master) then return nil end

  return s.master
end

--- Takes over a distribution left hanging.
---
--- Raid leader only. The master can drop offline mid-distribution, and
--- without this the whole raid would wait for them to come back. Assists
--- do not get this: two assists could take it from each other in turn.
function NS.TakeOver()
  local s = NS.session
  if not s then return false end

  if not NS.IsLeader() then
    NS.Print("vain raidin johtaja voi ottaa jaon haltuunsa.")
    return false
  end

  if s.master == NS.MyName() then return false end

  local previous = s.master
  s.master = NS.MyName()
  NS.Comm.Send("TAKEOVER", s.id)
  NS.Print(("jako otettu haltuun: %s -> sinä."):format(previous or "?"))

  if NS.RefreshView then NS.RefreshView("loot") end
  return true
end

function NS.DistributorChanged(sessionId, newMaster)
  local s = NS.session
  if not s or s.id ~= sessionId then return end

  s.master = newMaster
  if NS.RefreshView then NS.RefreshView("loot") end
end

--- The master opens a session from the chosen items.
function NS.OpenSession(chosen, test)
  if #chosen == 0 then
    NS.Print("ei valittuja itemeitä.")
    return false
  end

  -- Two simultaneous distributions would mean two different response
  -- lists for the same people, and the later one would wipe the first.
  local holder = not test and NS.DistributionBusy()
  if holder then
    NS.Print(("%s on jo jakamassa. Odota että jako päättyy."):format(holder))
    return false
  end

  NS.session = newSession(tostring(math.random(100000, 999999)),
    NS.MyName(), NS.db.rollVisibility)
  NS.session.test = test

  for i, loot in ipairs(chosen) do
    NS.session.items[i] = {
      index = i,
      itemId = loot.itemId,
      link = loot.link,
      name = loot.name,
      quality = loot.quality,
      test = loot.test or test,
      awarded = false,
      winner = nil,
      responses = {},
    }
  end

  NS.session.selected = 1

  if not test then NS.SendSession() end

  -- The whole view for the distributor, with the vote window beside it:
  -- the master responds too.
  NS.Open("loot")
  if NS.OpenVote then NS.OpenVote() end
  return true
end

--- Items not yet awarded. Awarded ones vanish from the tabs and stay in
--- the history, so the list shortens as the distribution proceeds.
function NS.OpenItems()
  local list = {}
  for _, item in pairs(NS.session and NS.session.items or {}) do
    if not item.awarded then list[#list + 1] = item end
  end
  table.sort(list, function(a, b) return a.index < b.index end)
  return list
end

--- Sends the session to the raid.
---
--- Item ids in one message as far as they fit. The message limit is 255
--- bytes, so a long list is split into parts.
function NS.SendSession()
  if not NS.session then return end

  local parts, length = {}, 0
  local function flush()
    if #parts > 0 then
      NS.Comm.Send("SESSION", ("%s %s %s"):format(
        NS.session.id, NS.session.visibility, table.concat(parts, ",")))
      parts, length = {}, 0
    end
  end

  for _, item in ipairs(NS.session.items) do
    local piece = item.index .. ":" .. item.itemId
    if length + #piece + 1 > 200 then flush() end
    parts[#parts + 1] = piece
    length = length + #piece + 1
  end
  flush()
end

--- The master opened a session: build the same view here.
function NS.IncomingSession(sessionId, visibility, items, sender)
  -- The same session can arrive in several parts, in which case the items
  -- are added to what is already there.
  if not NS.session or NS.session.id ~= sessionId then
    NS.session = newSession(sessionId, sender, visibility)
  end

  for _, row in ipairs(items) do
    if not NS.session.items[row.index] then
      NS.session.items[row.index] = {
        index = row.index,
        itemId = row.itemId,
        awarded = false,
        responses = {},
      }
    end
  end

  -- Only the vote window for a raider. The main window is the master's
  -- tool: its menus and lists are pure friction after a boss for someone
  -- whose whole job is to press one button. It opens from the minimap.
  if NS.OpenVote then NS.OpenVote() end
  if NS.RefreshView then NS.RefreshView("loot") end
end

--- Closes the responses. The items stay to be awarded, but no new
--- responses are taken — otherwise the list changes mid-decision.
function NS.CloseResponses()
  local s = NS.session
  if not s or s.closed then return false end
  if not s.test and not NS.IsDistributor() then return false end

  s.closed = true
  if not s.test then NS.Comm.Send("CLOSE", s.id) end

  if NS.CloseVote then NS.CloseVote() end
  if NS.RefreshView then NS.RefreshView("loot") end
  return true
end

function NS.ResponsesClosed(sessionId)
  local s = NS.session
  if not s or s.id ~= sessionId then return end

  s.closed = true

  -- The vote window goes away: a button that does nothing is worse than
  -- no button at all.
  if NS.CloseVote then NS.CloseVote() end
  if NS.RefreshView then NS.RefreshView("loot") end
end

--- How many seconds the session has been open.
function NS.SessionElapsed()
  if not NS.session then return 0 end
  return math.floor(GetTime() - (NS.session.startedAt or GetTime()))
end

--- The session's awards per player, for the summary.
local function sessionAwards()
  local perPlayer, order = {}, {}

  -- pairs rather than ipairs: a session can arrive in several parts, so
  -- the indices are not necessarily contiguous.
  for _, item in pairs(NS.session and NS.session.items or {}) do
    if item.awarded and item.winner then
      if not perPlayer[item.winner] then
        perPlayer[item.winner] = {}
        order[#order + 1] = item.winner
      end

      local name = item.name
      if not name and item.itemId then name = GetItemInfo(item.itemId) end

      local row = perPlayer[item.winner]
      row[#row + 1] = name or ("item " .. tostring(item.itemId))
    end
  end

  table.sort(order)
  return perPlayer, order
end

--- A compact summary to raid chat when the distribution ends.
---
--- One line per player rather than per item: the message limit is 255
--- bytes, and a short list gets read while a long one does not.
function NS.SendSummary()
  if not NS.session or NS.session.test then return end
  if not IsInGroup() then return end

  local perPlayer, order = sessionAwards()
  if #order == 0 then return end

  local channel = IsInRaid() and "RAID" or "PARTY"
  SendChatMessage("LootPrio - jaetut itemit:", channel)

  for _, name in ipairs(order) do
    local message = name .. ": " .. table.concat(perPlayer[name], ", ")

    -- A line over the limit is cut here: the game's own truncation would
    -- leave half an item name and say nothing about what was dropped.
    if #message > 230 then message = message:sub(1, 227) .. "..." end
    SendChatMessage(message, channel)
  end
end

function NS.EndSession(withSummary)
  if not NS.session then return end

  -- Ended by whoever is distributing. Otherwise another assist could
  -- close it mid-way, and the unanswered items would vanish from the
  -- tabs.
  if not NS.session.test and not NS.IsDistributor() then
    NS.Print(("vain jaon avaaja voi päättää jaon. Jakaa: %s"):format(
      NS.session.master or "?"))
    return
  end

  if withSummary then NS.SendSummary() end

  NS.Comm.Send("END", NS.session.id)
  NS.session = nil

  if NS.CloseVote then NS.CloseVote() end
  if NS.RefreshView then NS.RefreshView("loot") end
end

function NS.SessionEnded(sessionId)
  if NS.session and NS.session.id == sessionId then
    NS.session = nil

    if NS.CloseVote then NS.CloseVote() end
    if NS.RefreshView then NS.RefreshView("loot") end
  end
end

--------------------------------------------------------------------------
-- Responses
--------------------------------------------------------------------------

--- Sends our own response to the raid.
---
--- To the raid channel rather than as a whisper: officers are meant to
--- see what others answered, otherwise the list would be known only to
--- the master.
function NS.Respond(index, code)
  local s = NS.session
  if not s or s.closed then return end
  if not NS.RESPONSE[code] then return end

  local item = s.items[index]
  if not item or item.awarded then return end

  s.ownResponse[index] = code
  NS.Comm.Send("RESPONSE", ("%s %d %s"):format(s.id, index, code))

  -- Our own response is recorded immediately: we do not receive our own
  -- message back.
  NS.RecordResponse(s.id, index, NS.MyName(), code)
end

--- Records one player's response.
---
--- The roll is made only by the master, who sends the result to the
--- others. If everyone rolled for themselves the numbers would differ
--- from machine to machine and nobody could check anything.
function NS.RecordResponse(sessionId, index, player, code, roll)
  local s = NS.session
  if not s or s.id ~= sessionId then return end
  if s.closed then return end
  if not NS.RESPONSE[code] then return end

  local item = s.items[index]
  if not item or item.awarded then return end

  -- Is the item really in that player's profile.
  --
  -- The response comes from the player's own machine, so it cannot be
  -- trusted. The check is made on every machine against its own imported
  -- profiles, so a false claim shows up as wrong to everyone who has the
  -- data.
  local prioOk = false
  local picks = NS.db.profiles[player]
  if picks then
    for _, id in pairs(picks) do
      if id == item.itemId then prioOk = true break end
    end
  end

  item.responses[player] = {
    code = code,
    roll = roll,
    prioOk = prioOk,
  }

  -- The master rolls and tells the result, so everyone has the same
  -- number.
  if NS.session.master == NS.MyName() and code ~= "pass" and not roll then
    item.responses[player].roll = math.random(1, 100)
    NS.Comm.Send("ROLL", ("%s %d %s %d"):format(
      sessionId, index, player, item.responses[player].roll))
  end

  if NS.RefreshView then NS.RefreshView("loot") end
end

--- A roll sent by the master for one response.
function NS.RecordRoll(sessionId, index, player, roll)
  local s = NS.session
  if not s or s.id ~= sessionId then return end

  local item = s.items[index]
  if not item then return end

  local response = item.responses[player]
  if response then response.roll = roll end

  if NS.RefreshView then NS.RefreshView("loot") end
end

--- One item's responses as a list, best first.
---
--- Order: response type first, then the roll. The top row is the one with
--- the strongest reason, not the one with the biggest number.
function NS.ItemResponses(item)
  local list = {}

  for player, response in pairs(item.responses) do
    list[#list + 1] = {
      name = player,
      code = response.code,
      roll = response.roll,
      prioOk = response.prioOk,
      received = NS.ReceivedCount(player),
      order = NS.RESPONSE[response.code].order,
    }
  end

  -- The default order is reason first and the roll only after it: the
  -- roll settles a tie. The sort can be changed from the column headers.
  local field = NS.sortField or "order"
  local ascending = NS.sortAscending
  if ascending == nil then ascending = true end

  table.sort(list, function(a, b)
    local x, z = a[field], b[field]

    if x ~= z then
      if type(x) == "number" or type(z) == "number" then
        x, z = x or 0, z or 0
        if ascending then return x < z else return x > z end
      end
      if ascending then return tostring(x) < tostring(z) end
      return tostring(x) > tostring(z)
    end

    -- A tie is always settled the same way, so the order does not jump
    -- from one redraw to the next.
    if a.order ~= b.order then return a.order < b.order end
    if (a.roll or 0) ~= (b.roll or 0) then return (a.roll or 0) > (b.roll or 0) end
    return a.name < b.name
  end)

  return list
end

--- Who in the raid has not responded.
function NS.NotResponded(item)
  local missing = {}
  for name, online in pairs(NS.RaidMembers()) do
    if online and not item.responses[name] then
      missing[#missing + 1] = name
    end
  end
  table.sort(missing)
  return missing
end

--- Is the item in our own profile. Decides whether the LootPrio button
--- is enabled.
function NS.InOwnProfile(itemId)
  local own = NS.db.profiles[NS.MyName()]
  if not own then return false end

  for _, id in pairs(own) do
    if id == itemId then return true end
  end
  return false
end

--------------------------------------------------------------------------
-- Marking as awarded
--------------------------------------------------------------------------

--- Records an award on every machine.
---
--- The master broadcasts it so that everyone's received-item counters
--- stay current — not only the one who awarded it.
function NS.RecordAward(sessionId, index, winner, code, roll)
  local s = NS.session
  if not s or s.id ~= sessionId then return end

  local item = s.items[index]
  if not item or item.awarded then return end

  local response = item.responses[winner]
  code = code or (response and response.code)
  roll = roll or (response and response.roll)

  item.awarded = true
  item.winner = winner
  item.winnerCode = code

  -- The reason is stored alongside the number: "who got it and on which
  -- button" is what the history is asked about later.
  item.historyId = NS.AddToHistory(item.itemId, winner, roll, code, item.name)

  -- The latest award is remembered so it can be undone. The buttons are
  -- small and the list dense, so a misclick must not be permanent.
  s.lastAwarded = index

  -- The selected tab vanishes with the award, so move to the next open
  -- one.
  if s.selected == index then
    local open = NS.OpenItems()
    s.selected = open[1] and open[1].index or nil
  end

  -- An awarded item also leaves the vote window: it is not answered any
  -- more.
  if NS.RefreshVote then NS.RefreshVote() end
  if NS.RefreshView then NS.RefreshView("loot") end
end

--- Undoes one award: the item returns to the tabs and the history row
--- disappears.
---
--- The latest award only. Undoing further back would need to know what
--- the order was, and mid-raid that would be more a source of confusion
--- than a help.
function NS.UndoAward(index, sender)
  local s = NS.session
  if not s then return false end

  index = index or s.lastAwarded
  if not index then return false end

  local item = s.items[index]
  if not item or not item.awarded then return false end

  -- A local undo needs distributor rights; one arriving from the network
  -- has already been checked against the sender's rank.
  if not sender and not item.test and not NS.IsDistributor() then
    NS.Print("vain jaon avaaja voi perua jaon.")
    return false
  end

  local winner = item.winner

  NS.RemoveFromHistory(item.historyId)
  if NS.RemoveFromTrades then NS.RemoveFromTrades(item.historyId) end

  item.awarded = false
  item.winner = nil
  item.winnerCode = nil
  item.historyId = nil

  if s.lastAwarded == index then s.lastAwarded = nil end
  s.selected = index

  if not sender and not item.test then
    NS.Comm.Send("UNDO", ("%s %d"):format(s.id, index))
  end

  NS.Print(("jako peruttu: %s -> %s"):format(
    item.name or ("item " .. tostring(item.itemId)), winner or "?"))

  if NS.RefreshVote then NS.RefreshVote() end
  if NS.RefreshView then NS.RefreshView("loot") end
  return true
end
