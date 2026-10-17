--[[
  LootPrio — the trade helper.

  The addon cannot give an item away from a bag, but it can fill the
  trade window. When the master opens a trade with a winner, the awarded
  items drop into the trade slots by themselves.

  The addon never accepts a trade. A person presses that button: a trade
  that went wrong cannot be taken back, and an eye always has time to
  look at the screen once.
]]

local ADDON, NS = ...

-- The trade's item slots. The seventh is the "will not be traded" slot
-- and is never touched.
local TRADE_SLOTS = 6

--------------------------------------------------------------------------
-- The queue
--------------------------------------------------------------------------

--- Puts an awarded item in line for a trade.
---
--- A queue is needed because awarding and handing over happen at
--- different times: items are awarded after a boss and traded whenever
--- both people happen to have a moment.
function NS.AddToTrades(itemId, name, itemName, link, historyId)
  if not itemId or not name then return end
  if name == NS.MyName() then return end  -- no trading with yourself

  NS.db.trades[#NS.db.trades + 1] = {
    itemId = itemId,
    name = name,
    itemName = itemName,
    link = link,
    -- The same id as the history row, so an undone award also leaves the
    -- trade queue instead of waiting for a handover that never comes.
    historyId = historyId,
    time = date("%Y-%m-%d %H:%M:%S"),
  }
end

--- Trades not yet delivered, optionally for one player.
function NS.PendingTrades(name)
  local result = {}

  for i, row in ipairs(NS.db.trades) do
    if not row.delivered and (not name or row.name == name) then
      row.index = i
      result[#result + 1] = row
    end
  end

  return result
end

function NS.MarkDelivered(index)
  local row = NS.db.trades[index]
  if not row then return end

  row.delivered = true
  row.deliveredAt = date("%Y-%m-%d %H:%M:%S")

  if NS.RefreshView then NS.RefreshView("trade") end
end

--- Removes an undone award from the queue.
---
--- Only one that has not been delivered: if the item has already changed
--- hands, undoing cannot change that, and removing the row would only
--- lose the information.
function NS.RemoveFromTrades(historyId)
  if not historyId then return false end

  for i, row in ipairs(NS.db.trades) do
    if row.historyId == historyId and not row.delivered then
      table.remove(NS.db.trades, i)
      if NS.RefreshView then NS.RefreshView("trade") end
      return true
    end
  end

  return false
end

--- Drops delivered rows from the queue.
function NS.ClearDeliveredTrades()
  local remaining = {}
  for _, row in ipairs(NS.db.trades) do
    if not row.delivered then remaining[#remaining + 1] = row end
  end

  local removed = #NS.db.trades - #remaining
  NS.db.trades = remaining

  if NS.RefreshView then NS.RefreshView("trade") end
  return removed
end

--------------------------------------------------------------------------
-- Scanning the bags
--------------------------------------------------------------------------

--- Finds an item in the bags. Skips slots already used on this round: an
--- item placed in the trade still shows in the bag, so without this the
--- same copy would be placed twice.
local function findInBags(itemId, used)
  for bag = 0, 4 do
    for slot = 1, NS.BagSize(bag) do
      local key = bag .. ":" .. slot

      if not used[key] then
        local link = NS.BagItemLink(bag, slot)
        if link and NS.ItemIdFromLink(link) == itemId then
          return bag, slot
        end
      end
    end
  end

  return nil
end

--- How many copies of that item are in the bags.
local function countInBags(itemId)
  local n = 0

  for bag = 0, 4 do
    for slot = 1, NS.BagSize(bag) do
      local link = NS.BagItemLink(bag, slot)
      if link and NS.ItemIdFromLink(link) == itemId then n = n + 1 end
    end
  end

  return n
end

local function pickUp(bag, slot)
  if C_Container and C_Container.PickupContainerItem then
    C_Container.PickupContainerItem(bag, slot)
  elseif PickupContainerItem then
    PickupContainerItem(bag, slot)
  end
end

--------------------------------------------------------------------------
-- Filling the trade window
--------------------------------------------------------------------------

--- The trade partner's name, without the realm.
local function tradePartner()
  local name = UnitName("npc")

  -- Fall back to the window's own text: the "npc" unit is not usable
  -- during a trade in every client version.
  if not name and TradeFrameRecipientNameText then
    name = TradeFrameRecipientNameText:GetText()
  end

  -- Into the profiles' form, because the queue is keyed by that name.
  return name and NS.Name(name) or nil
end

local function freeSlot()
  for i = 1, TRADE_SLOTS do
    if not GetTradePlayerItemLink(i) then return i end
  end
  return nil
end

-- What was in the bags when the trade opened. Comparing at the end tells
-- what actually changed hands — a trade can be cancelled, so opening one
-- proves nothing.
local countsBefore = nil
local partner = nil

local function fillTradeWindow()
  partner = tradePartner()
  if not partner then return end

  local queue = NS.PendingTrades(partner)
  if #queue == 0 then return end

  countsBefore = {}
  for _, row in ipairs(queue) do
    countsBefore[row.itemId] = countInBags(row.itemId)
  end

  local used = {}
  local placed, missing = 0, 0

  for _, row in ipairs(queue) do
    local slot = freeSlot()
    if not slot then break end

    local bag, bagSlot = findInBags(row.itemId, used)

    if bag then
      ClearCursor()
      pickUp(bag, bagSlot)

      -- Make sure the item really is on the cursor. A locked or bound
      -- item will not lift, and without this check the click would land
      -- on an empty cursor and remove whatever was already in the slot.
      if GetCursorInfo() then
        ClickTargetTradeButton(slot)
        used[bag .. ":" .. bagSlot] = true
        placed = placed + 1
      end

      ClearCursor()
    else
      missing = missing + 1
    end
  end

  if placed > 0 then
    NS.Print(("%d itemiä tradeen: %s"):format(placed, partner))
  end

  if missing > 0 then
    NS.Print(("%d assignattua itemiä ei löytynyt laukuista."):format(missing))
  end
end

--- Marks the queue rows whose items really left the bags.
---
--- Closing the trade does not say whether it succeeded, so the copies are
--- counted. That way a cancelled trade marks nothing as delivered.
local function checkResult()
  if not partner or not countsBefore then return end

  local who = partner
  local before = countsBefore
  partner, countsBefore = nil, nil

  local queue = NS.PendingTrades(who)
  local delivered = 0

  for itemId, count in pairs(before) do
    local drop = count - countInBags(itemId)

    for _, row in ipairs(queue) do
      if drop <= 0 then break end
      if row.itemId == itemId and not row.delivered then
        row.delivered = true
        row.deliveredAt = date("%Y-%m-%d %H:%M:%S")
        drop = drop - 1
        delivered = delivered + 1
      end
    end
  end

  if delivered > 0 then
    NS.Print(("%s sai %d itemiä. Jonossa %d."):format(
      who, delivered, #NS.PendingTrades()))
    if NS.RefreshView then NS.RefreshView("trade") end
  end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_CLOSED")

frame:SetScript("OnEvent", function(_, event)
  if event == "TRADE_SHOW" then
    if NS.db.autoFillTrade == false then return end

    -- A short delay: the trade window is not ready immediately, and the
    -- partner's name cannot be read on the same frame.
    C_Timer.After(0.2, fillTradeWindow)

  elseif event == "TRADE_CLOSED" then
    -- The bags update only a moment after the trade.
    C_Timer.After(1, checkResult)
  end
end)
