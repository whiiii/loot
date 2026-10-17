--[[
  LootPrio — foundation.

  The addon has no network access: WoW gives Lua code no way out. Profiles
  are therefore imported by pasting text copied from the website, and kept
  in SavedVariables.
]]

local ADDON, NS = ...

NS.NAME = ADDON
NS.GOLD = "|cffc9a227"   -- same gold as the website
NS.RESET = "|r"

--- Default settings. Missing keys are filled in on every load so an older
--- saved file does not break on a new setting.
local DEFAULTS = {
  -- Who sees the rolls: "officers" or "raid".
  rollVisibility = "officers",

  -- Announce the winner in raid chat when loot is awarded.
  announceWinner = true,

  -- Imported profiles: [characterName] = { [slot] = itemId }
  profiles = {},

  -- The website's count of how many items each player has received:
  -- [character] = count. The addon's own history is one machine's view
  -- only, so without this the number resets whenever the master changes.
  received = {},

  -- Import details, so you can see when the data is from.
  raidName = nil,
  importedAt = nil,

  -- Awarded loot. Rows of { itemId, name, time, roll, response, itemName }.
  -- The export to the website is built from this.
  history = {},

  -- Minimum quality for the bag list: 2 green, 3 blue, 4 purple. Without
  -- a limit the list would hold every water flask and bolt of cloth.
  bagQuality = 3,

  -- Awarded items still waiting to be handed over. Rows of
  -- { itemId, name, itemName, link, time, delivered }.
  trades = {},

  -- Fill the trade window automatically. The addon never accepts a trade,
  -- it only puts the items in place.
  autoFillTrade = true,

  -- Running id for history rows. Needed to undo an award: an index shifts
  -- when a row is removed, an id does not.
  nextHistoryId = 1,

  -- How many seconds to wait for responses before the clock turns red.
  -- Forces nothing: the master decides when it is enough.
  responseTime = 90,

  -- Other spellings of a character name: [alias in lowercase] = profile
  -- name. The game and the website do not necessarily use the same form.
  aliases = {},

  -- Guild officers from the website: [character] = true. Empty means
  -- "not known", in which case raid rank alone is enough.
  officers = {},

  -- Minimap button angle in degrees. The position survives sessions.
  minimapAngle = 200,
}

local function fillDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil then
      if type(value) == "table" then
        target[key] = {}
        fillDefaults(target[key], value)
      else
        target[key] = value
      end
    end
  end
end

function NS.Print(...)
  print(NS.GOLD .. "LootPrio" .. NS.RESET .. ":", ...)
end

--- A field from our own .toc.
---
--- The API moved into the C_AddOns namespace partway through Classic's
--- life. Both are supported, because this addon's whole problem is that
--- the client version is not certain.
local function tocField(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, field)
  end
  return nil
end

--- The Interface number declared by our own .toc.
function NS.TocInterface()
  return tocField("Interface")
end

--------------------------------------------------------------------------
-- Game API compatibility
--------------------------------------------------------------------------

--[[
  The item functions live in different places on different clients.

  They were plain globals for most of WoW's life and later moved into the
  C_Item namespace. This addon runs on a client whose version number
  matches no Blizzard build, so "this is Classic, therefore GetItemInfo
  exists" does not hold -- on WoW Forever 1.60.1 there is no global
  GetItemInfo at all, and calling it took the test mode down.

  The container functions already had this treatment in Loot.lua and
  Trade.lua. These are the same problem, missed because they happened to
  work on the client they were written against.

  Nothing here raises an error when a client has neither name. Every
  caller already handles nil, because the game itself returns nil for an
  item whose data has not loaded yet -- so a missing function degrades
  into "the name fills in later", not into a broken addon.
]]

--- Item details: name, link, quality and the rest, as GetItemInfo gives.
function NS.ItemInfo(key)
  if not key then return nil end
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(key) end
  if GetItemInfo then return GetItemInfo(key) end
  return nil
end

--- An item's icon texture.
function NS.ItemIcon(itemId)
  if not itemId then return nil end
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemId) end
  if GetItemIcon then return GetItemIcon(itemId) end

  -- The instant variant knows the icon without the item being cached, and
  -- hands it back as the fifth return value.
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if instant then return (select(5, instant(itemId))) end
  return nil
end

--- Can the item be worn. Used to keep flasks and cloth out of the bag list.
---
--- An unknown client answers yes. Too many items in the list is a nuisance
--- the quality filter still trims; too few would look like the addon
--- cannot see the bags at all.
function NS.IsEquippable(link)
  if C_Item and C_Item.IsEquippableItem then return C_Item.IsEquippableItem(link) end
  if IsEquippableItem then return IsEquippableItem(link) end
  return true
end

--- Which of the APIs this addon needs the client actually has.
---
--- Printed by /lp api. On a client that reports a version number matching
--- no Blizzard build, asking it directly beats reasoning about which
--- expansion it resembles -- and it turns "the addon does nothing" into
--- one line naming the function that is missing.
function NS.ReportApi()
  local paths = {
    "GetItemInfo", "C_Item.GetItemInfo",
    "GetItemIcon", "C_Item.GetItemIconByID",
    "GetItemInfoInstant", "C_Item.GetItemInfoInstant",
    "IsEquippableItem", "C_Item.IsEquippableItem",
    "GetContainerNumSlots", "C_Container.GetContainerNumSlots",
    "GetContainerItemLink", "C_Container.GetContainerItemLink",
    "PickupContainerItem", "C_Container.PickupContainerItem",
    "C_ChatInfo.SendAddonMessage",
    "GetRaidRosterInfo", "GetInstanceInfo", "GetNumGroupMembers",
    "SendChatMessage", "ClickTargetTradeButton", "RAID_CLASS_COLORS",
  }

  NS.Print(("client %s, .toc %s"):format(
    tostring(select(4, GetBuildInfo())), tostring(NS.TocInterface())))

  for _, path in ipairs(paths) do
    local namespace, field = path:match("^(%w+)%.(%w+)$")
    local value

    if namespace then
      local container = _G[namespace]
      value = container and container[field]
    else
      value = _G[path]
    end

    NS.Print((value and "  + " or "  - ") .. path)
  end
end

-- The version comes from the .toc rather than being written out here as
-- well. Two copies drift apart, and they already had: the .toc said 0.11
-- while this file said 0.10, so the load message named a version nobody
-- was running.
NS.VERSION = tocField("Version") or "?"

--- The player's name in the profiles' form.
---
--- Converted here rather than at every call site: if our own name were
--- sometimes in the game's form and sometimes the website's, comparisons
--- would match at random. NS.Name comes from Data.lua, which loads after
--- this file — hence the check.
function NS.MyName()
  local name = UnitName("player")
  if NS.Name then return NS.Name(name) end
  return name
end

--- The name the game gives, without conversion.
---
--- Needed in the few places where the name is used to talk to the game
--- rather than to compare against profiles.
function NS.MyGameName()
  return UnitName("player")
end

--- Does the player have guild officer rights on the website.
---
--- The list arrives on the export's O line. An empty list means "not
--- known": an older export does not contain it, and an addon that has
--- imported nothing knows nothing. In that case nothing is restricted —
--- an addon that locks itself over missing data is less useful than one
--- that trusts raid rank.
function NS.IsSiteOfficer(name)
  local list = NS.db and NS.db.officers
  if not list then return true end

  local count = 0
  for _ in pairs(list) do count = count + 1 end
  if count == 0 then return true end

  return list[name] == true
end

--- Raid rank only, without the guild officer check.
---
--- Needed only to explain why the distribute button is missing: an assist
--- who is not a guild officer deserves a reason, not an empty screen.
function NS.HasRaidRank(name)
  name = name or NS.MyName()

  if not IsInRaid() then
    return UnitIsGroupLeader("player") and name == NS.MyName()
  end

  for i = 1, GetNumGroupMembers() do
    local rosterName, rank = GetRaidRosterInfo(i)
    if rosterName and NS.Name(rosterName) == name then
      return (rank or 0) >= 1
    end
  end
  return false
end

--- May the player open a distribution and see everyone's responses.
---
--- Requires both raid rank and guild officer rights. Raid rank alone is
--- not enough: assist is often handed out for markers, not loot. Guild
--- rank alone is not enough either: in a raid, loot is distributed by
--- whoever holds raid rights, not by an officer who is only watching.
---
--- Neither comes from a message body — raid rank is read from the game
--- and the officer list from the imported export — so a modified addon
--- cannot claim to be either.
function NS.IsOfficer(name)
  name = name or NS.MyName()

  if not NS.IsSiteOfficer(name) then return false end
  return NS.HasRaidRank(name)
end

--- Is the player the raid leader.
---
--- Different from officer: there can be many assists, there is one
--- leader. Only the leader can take over a distribution left hanging,
--- because otherwise two assists could take it from each other in turn.
---
--- Also requires guild officer rights: taking over grants the right to
--- distribute, and that must not be easier to get than opening one.
function NS.IsLeader(name)
  name = name or NS.MyName()

  if not NS.IsSiteOfficer(name) then return false end

  if not IsInRaid() then
    return UnitIsGroupLeader("player") and name == NS.MyName()
  end

  for i = 1, GetNumGroupMembers() do
    local rosterName, rank = GetRaidRosterInfo(i)
    if rosterName and NS.Name(rosterName) == name then
      return (rank or 0) >= 2
    end
  end
  return false
end

--- Is the named player present and online.
function NS.IsPresent(name)
  if not name then return false end
  return NS.RaidMembers()[name] == true
end

--- Classes of everyone in the raid: [profileName] = "WARRIOR".
---
--- Class colour is the fastest way to tell names apart in a list, and the
--- game already knows it — no need to ask the website.
function NS.RaidClasses()
  local classes = {}

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
      if name then classes[NS.Name(name)] = fileName end
    end
  else
    classes[NS.MyName()] = select(2, UnitClass("player"))
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      local name = UnitName(unit)
      if name then classes[NS.Name(name)] = select(2, UnitClass(unit)) end
    end
  end

  return classes
end

--- Is the player the master looter.
function NS.IsMasterLooter()
  local method, mlPartyID, mlRaidID = GetLootMethod()
  if method ~= "master" then return false end

  if IsInRaid() then
    if not mlRaidID then return false end
    local name = GetRaidRosterInfo(mlRaidID)
    return name == NS.MyGameName()
  end

  -- In a party, 0 means the player themselves.
  return mlPartyID == 0
end

--- Where we are and how large the raid is.
---
--- The website tells nights apart by these: one week can hold one 40-man
--- and a couple of 20-mans, run by different masters. Without the
--- instance and the size the logs would look identical afterwards.
function NS.Instance()
  local name, instanceType, _, _, maxPlayers, _, _, _, groupSize =
    GetInstanceInfo()

  -- Outside an instance the name is a world map zone, which says nothing
  -- about the raid.
  if instanceType ~= "raid" and instanceType ~= "party" then name = nil end

  local size = 0
  if maxPlayers and maxPlayers > 0 then
    size = maxPlayers
  elseif groupSize and groupSize > 0 then
    size = groupSize
  else
    size = GetNumGroupMembers() or 0
  end

  return name, size
end

--- The item number from a link. A link looks like |cff...|Hitem:19019:...
function NS.ItemIdFromLink(link)
  if not link then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

--- Raid members who are present, as a set keyed by profile name.
---
--- Names are converted to the profiles' form right here: this is the
--- place where the game's names flow into the addon, and one conversion
--- here is enough.
function NS.RaidMembers()
  local set = {}

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
      if name then set[NS.Name(name)] = online ~= false end
    end
  elseif IsInGroup() then
    set[NS.MyName()] = true
    for i = 1, GetNumSubgroupMembers() do
      local name = UnitName("party" .. i)
      if name then set[NS.Name(name)] = true end
    end
  else
    set[NS.MyName()] = true
  end

  return set
end

-- Load handling ------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
  if event ~= "ADDON_LOADED" or name ~= ADDON then return end

  LootPrioDB = LootPrioDB or {}
  fillDefaults(LootPrioDB, DEFAULTS)
  NS.db = LootPrioDB

  local count = 0
  for _ in pairs(NS.db.profiles) do count = count + 1 end

  NS.Print(("v%s ladattu. Profiileja %d. Avaa ikkuna minimapin napista tai /lp"):format(
    NS.VERSION, count))

  -- Show the client's Interface number right away. A wrong number in the
  -- .toc shows up only as "Incompatible" in the addon list, and nothing
  -- tells you what the right number would be — except this line, once the
  -- addon loads at all.
  local tocNumber = NS.TocInterface()
  local clientNumber = select(4, GetBuildInfo())

  if tocNumber and clientNumber and tostring(tocNumber) ~= tostring(clientNumber) then
    NS.Print(("HUOM: .toc sanoo %s, client on %s. Korjaa .toc-tiedoston "
      .. "ensimmäinen rivi muotoon '## Interface: %s'."):format(
      tocNumber, clientNumber, clientNumber))
  end

  if NS.CreateMinimapButton then NS.CreateMinimapButton() end
end)

-- Commands -----------------------------------------------------------------

SLASH_LOOTPRIO1 = "/lootprio"
SLASH_LOOTPRIO2 = "/lp"

SlashCmdList.LOOTPRIO = function(input)
  local command = input:match("^(%S*)")
  command = (command or ""):lower()

  -- Commands are a shortcut, not the only way: everything is reachable
  -- from the window's buttons.
  if command == "" then
    NS.Open()
  elseif command == "loot" then
    NS.Open("loot")
  elseif command == "tuo" or command == "import" then
    NS.Open("import")
  elseif command == "jasenet" or command == "members" then
    NS.Open("members")
  elseif command == "historia" or command == "history" then
    NS.Open("history")
  elseif command == "kauppa" or command == "trade" then
    NS.Open("trade")
  elseif command == "api" then
    NS.ReportApi()
  else
    -- The running version goes in the answer to an unknown command.
    --
    -- An unknown command usually means the game is running an older copy
    -- than the one on disk, because the command it does not know is one
    -- that was only just added. Saying which version is talking turns
    -- that from a guess into a reading.
    NS.Print(("v%s — käytä: /lp  (avaa ikkunan)  tai  /lp api  "
      .. "(clientin API-tuki)"):format(NS.VERSION))
  end
end
