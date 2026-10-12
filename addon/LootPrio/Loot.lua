--[[
  LootPrio — bags and awarding.

  The master gathers the loot into their own bags first and then puts it
  up for distribution. The addon therefore reads the bags, not the loot
  window.

  For the same reason the addon never gives an item to anyone: it records
  the decision and tells the raid, but the goods change hands in a trade.
  The game's own loot distribution works only through an open loot window,
  and an item sitting in a bag cannot be given away from code.
]]

local ADDON, NS = ...

--------------------------------------------------------------------------
-- Bags
--------------------------------------------------------------------------

-- The container API moved partway through Classic's life. Both are
-- supported so the addon is not tied to one client version. Exposed on
-- the namespace because Trade.lua also looks for items in bags.
function NS.BagSize(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end

function NS.BagItemLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then
    return C_Container.GetContainerItemLink(bag, slot)
  end
  return GetContainerItemLink and GetContainerItemLink(bag, slot)
end

local bagSize, bagItemLink = NS.BagSize, NS.BagItemLink

--- An item from a link, as a distributable row.
---
--- This is how items that an officer links by hand get in: not everything
--- is in the master's bags, and the distribution must not depend on that.
function NS.ItemFromLink(link)
  if type(link) ~= "string" then return nil end

  local itemId = NS.ItemIdFromLink(link)
  if not itemId then return nil end

  -- The link can also be pasted as plain text, so make sure the game
  -- knows the item. The lookup returns nil if the data has not loaded
  -- yet — then the id is used and the name fills in later.
  local name, fullLink, quality = NS.ItemInfo(itemId)

  return {
    itemId = itemId,
    link = fullLink or link,
    name = name or ("item " .. itemId),
    quality = quality or 4,
    manual = true,
  }
end

--- Items in the bags that are worth distributing.
---
--- Limiting by quality and equippability is necessary: without it the
--- list would hold every water flask and bolt of cloth in the bags.
function NS.BagItems(minQuality)
  minQuality = minQuality or NS.db.bagQuality or 3
  local result = {}

  for bag = 0, 4 do
    for slot = 1, bagSize(bag) do
      local link = bagItemLink(bag, slot)

      if link then
        local name, _, quality = NS.ItemInfo(link)
        local itemId = NS.ItemIdFromLink(link)

        if itemId and quality and quality >= minQuality and NS.IsEquippable(link) then
          result[#result + 1] = {
            bag = bag,
            slot = slot,
            itemId = itemId,
            link = link,
            name = name or ("item " .. itemId),
            quality = quality,
          }
        end
      end
    end
  end

  table.sort(result, function(a, b)
    if a.quality ~= b.quality then return a.quality > b.quality end
    return a.name < b.name
  end)

  return result
end

--------------------------------------------------------------------------
-- Awarding
--------------------------------------------------------------------------

--- Marks an item as awarded and tells the raid.
---
--- This does not move the goods. The master hands the item over in a
--- trade; the addon keeps track of who got it and on what grounds.
function NS.Award(item, name)
  if not NS.session then return false end

  local response = item.responses and item.responses[name]
  local code = response and response.code
  local roll = response and response.roll

  if not item.test and not NS.IsDistributor() then
    NS.Print(("vain jaon avaaja voi antaa itemin. Jakaa: %s"):format(
      NS.session.master or "?"))
    return false
  end

  NS.RecordAward(NS.session.id, item.index, name, code, roll)

  if not item.test then
    -- The trade queue is only for the one who awarded it: the goods are
    -- in their bags, and only they can hand them over.
    if NS.AddToTrades and NS.session.master == NS.MyName() then
      NS.AddToTrades(item.itemId, name, item.name, item.link, item.historyId)
    end

    NS.Comm.Send("AWARDED", ("%s %d %s %s %d"):format(
      NS.session.id, item.index, name, code or "muu", roll or 0))

    if NS.db.announceWinner and IsInGroup() then
      local reason = code and NS.RESPONSE[code] and NS.RESPONSE[code].name or "?"
      local message = ("%s -> %s (%s%s)"):format(
        item.link or item.name or "?",
        name, reason,
        roll and (", roll " .. roll) or "")
      SendChatMessage("LootPrio: " .. message, IsInRaid() and "RAID" or "PARTY")
    end
  else
    NS.Print(("TESTI: %s -> %s"):format(item.name or item.itemId, name))
  end

  return true
end

--------------------------------------------------------------------------
-- Test mode
--------------------------------------------------------------------------

--- Builds a test session from the imported profiles.
---
--- The items are taken from real picks and the responses are rolled, so
--- the whole view behaves as it would in a real raid. Nothing is given to
--- anyone and nothing is sent anywhere.
function NS.StartTest()
  local members = NS.Members()
  if #members == 0 then
    NS.Print("tuo ensin profiilit, muuten testissä ei ole ketään.")
    return false
  end

  local counts = {}
  for _, picks in pairs(NS.db.profiles) do
    for _, itemId in pairs(picks) do
      counts[itemId] = (counts[itemId] or 0) + 1
    end
  end

  local ranked = {}
  for itemId, n in pairs(counts) do
    ranked[#ranked + 1] = { itemId = itemId, n = n }
  end
  table.sort(ranked, function(a, b)
    if a.n == b.n then return a.itemId < b.itemId end
    return a.n > b.n
  end)

  if #ranked == 0 then
    NS.Print("tuoduissa profiileissa ei ole yhtään itemiä.")
    return false
  end

  local chosen = {}
  for i = 1, math.min(4, #ranked) do
    local itemId = ranked[i].itemId
    local name, link, quality = NS.ItemInfo(itemId)
    chosen[#chosen + 1] = {
      itemId = itemId,
      link = link,
      name = (name or ("item " .. itemId)) .. " |cff8b9299[testi]|r",
      quality = quality or 4,
      test = true,
    }
  end

  NS.OpenSession(chosen, true)

  -- Roll some responses: those who reserved the item answer LootPrio,
  -- some of the others on another ground.
  local codes = { "main", "off", "muu", "pass" }

  for _, item in pairs(NS.session.items) do
    for _, member in ipairs(members) do
      local picks = NS.db.profiles[member.name]
      local wants = false
      if picks then
        for _, id in pairs(picks) do
          if id == item.itemId then wants = true break end
        end
      end

      if wants then
        item.responses[member.name] =
          { code = "prio", roll = math.random(1, 100), prioOk = true }
      elseif math.random(1, 3) == 1 then
        local code = codes[math.random(1, #codes)]
        item.responses[member.name] = {
          code = code,
          roll = (code ~= "pass") and math.random(1, 100) or nil,
          prioOk = false,
        }
      end
    end
  end

  NS.Print(("testisessio: %d itemiä, vastaukset arvottu."):format(#chosen))
  return true
end
