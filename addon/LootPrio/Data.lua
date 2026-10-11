--[[
  LootPrio — importing and querying profiles.

  The format comes from the website as-is:

    LOOTPRIO1
    RAID=Molten Core
    TIME=2026-10-10 07:05:32
    SLOTS=head,neck,shoulder,...
    P=Betonimylly|head:18817,neck:18814,...
    S=Betonimylly|4
    A=Betonimylly|Beto Nimylly,Betonimylly99
    O=Pulu,Homo

  A line-based format beats JSON here for one simple reason: Lua reads it
  with three gmatch calls. JSON would need a parser or a library, and it
  would add nothing.
]]

local ADDON, NS = ...

--- Parses the export. Returns a table, or nil and an error.
function NS.Parse(text)
  if type(text) ~= "string" or text == "" then
    return nil, "Teksti puuttuu."
  end

  -- Strip Windows line endings so comparisons match.
  text = text:gsub("\r", "")

  local first = text:match("^%s*(%S+)")
  if first ~= "LOOTPRIO1" then
    return nil, "Tuntematon muoto. Odotettiin LOOTPRIO1."
  end

  local result = {
    raidName = text:match("\nRAID=([^\n]*)") or "?",
    time = text:match("\nTIME=([^\n]*)") or "?",
    profiles = {},
    received = {},
    aliases = {},
    officers = {},
    characterCount = 0,
  }

  for line in text:gmatch("P=([^\n]+)") do
    local character, picks = line:match("^([^|]+)|(.*)$")

    if character and character ~= "" then
      character = character:match("^%s*(.-)%s*$")
      local own = {}

      for slot, itemId in (picks or ""):gmatch("([%w_]+):(%d+)") do
        own[slot] = tonumber(itemId)
      end

      result.profiles[character] = own
      result.characterCount = result.characterCount + 1
    end
  end

  -- Items received across the website's whole history. Optional line: an
  -- older export does not contain it, and that is no reason to reject the
  -- import.
  for line in text:gmatch("S=([^\n]+)") do
    local character, count = line:match("^([^|]+)|(%d+)$")
    if character then
      result.received[character:match("^%s*(.-)%s*$")] = tonumber(count)
    end
  end

  -- Other spellings of a character name. The website does not know which
  -- form the game uses, so it sends the alternatives and the addon picks
  -- the one that matches.
  for line in text:gmatch("A=([^\n]+)") do
    local character, others = line:match("^([^|]+)|(.*)$")

    if character then
      character = character:match("^%s*(.-)%s*$")

      for alias in (others or ""):gmatch("[^,]+") do
        alias = alias:match("^%s*(.-)%s*$")
        if alias ~= "" then
          result.aliases[alias:lower()] = character
        end
      end
    end
  end

  -- Guild officers. Raid rank alone is not enough to open a distribution,
  -- because assist is often handed out for markers rather than loot.
  local officerLine = text:match("\nO=([^\n]*)")
  if officerLine then
    for name in officerLine:gmatch("[^,]+") do
      name = name:match("^%s*(.-)%s*$")
      if name ~= "" then result.officers[name] = true end
    end
  end

  if result.characterCount == 0 then
    return nil, "Yhtään profiilia ei löytynyt."
  end

  return result
end

--- The name the game gives, as a profile name.
---
--- All internal comparison uses the profile name. The conversion happens
--- where the game's name enters the addon — the roster, a message sender
--- or a trade partner — so that the same player never has two different
--- names anywhere else.
function NS.Name(gameName)
  if not gameName or gameName == "" then return gameName end

  -- Drop the realm: a name from the raid channel can be "Name-Realm".
  gameName = gameName:match("^[^-]+") or gameName

  -- An event can fire before the saved data has loaded.
  if not NS.db then return gameName end

  if NS.db.profiles[gameName] then return gameName end

  local canonical = NS.db.aliases and NS.db.aliases[gameName:lower()]
  return canonical or gameName
end

--- Imports the text into the database. Replaces the old data entirely.
---
--- Replaces rather than merges: the export is the website's whole truth
--- about that raid, and merging would leave removed picks in force.
function NS.Import(text)
  local data, err = NS.Parse(text)
  if not data then return nil, err end

  NS.db.profiles = data.profiles
  NS.db.received = data.received
  NS.db.aliases = data.aliases
  NS.db.officers = data.officers
  NS.db.raidName = data.raidName
  NS.db.importedAt = date("%Y-%m-%d %H:%M")

  return data
end

--- Who has reserved this item.
---
--- Returns a list of { name = , slot = }, sorted by name so the same
--- situation always looks the same.
function NS.WhoWants(itemId)
  local result = {}
  if not itemId then return result end

  for character, picks in pairs(NS.db.profiles) do
    for slot, id in pairs(picks) do
      if id == itemId then
        result[#result + 1] = { name = character, slot = slot }
        break
      end
    end
  end

  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Same as WhoWants, but only those present in the raid.
---
--- The master does not care that someone who is not here reserved the
--- item — the list would only be longer without being more useful.
function NS.WhoWantsPresent(itemId)
  local all = NS.WhoWants(itemId)
  local inRaid = NS.RaidMembers()
  local result = {}

  for _, row in ipairs(all) do
    if inRaid[row.name] then
      result[#result + 1] = row
    end
  end

  return result
end

--- Imported characters in alphabetical order, with their pick counts.
function NS.Members()
  local list = {}

  for character, picks in pairs(NS.db.profiles) do
    local n = 0
    for _ in pairs(picks) do n = n + 1 end
    list[#list + 1] = { name = character, picks = n }
  end

  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

--- How many items this character has already received.
---
--- The website's number plus the awards this machine recorded: the site
--- knows everything that has been exported to it, and the local history
--- knows what has been awarded since. Once the history is exported and
--- the profiles re-imported, the count moves to the S lines and the local
--- history is cleared — which is why these do not double up.
function NS.ReceivedCount(character)
  local n = NS.db.received[character] or 0

  for _, row in ipairs(NS.db.history) do
    if row.name == character then n = n + 1 end
  end

  return n
end

--- How much of the number comes from the website. Shown separately so
--- the master can see whether it is really the guild's history or only
--- tonight's.
function NS.ReceivedFromSite(character)
  return NS.db.received[character] or 0
end

--- Records an awarded item in the history.
---
--- The timestamp is stored as text in the same format the website uses,
--- so the import does not have to guess the format.
--- Returns the row's id, which is what an undo needs.
function NS.AddToHistory(itemId, name, roll, response, itemName)
  -- A running id rather than an index: an index shifts when a row is
  -- removed, and an undo would then hit the wrong row.
  local id = NS.db.nextHistoryId or 1
  NS.db.nextHistoryId = id + 1

  -- The instance and size are recorded at award time rather than at
  -- export: one history can hold two nights if the export was forgotten
  -- in between.
  local zone, size = NS.Instance()

  NS.db.history[#NS.db.history + 1] = {
    id = id,
    itemId = itemId,
    name = name,
    roll = roll,
    zone = zone,
    size = size,
    -- The reason is stored alongside the number: "who got it and on
    -- which button" is what the history is asked about later.
    response = response,
    itemName = itemName,
    time = date("%Y-%m-%d %H:%M:%S"),
    raid = NS.db.raidName,
  }

  return id
end

--- Removes a history row by id. Used only when undoing an award.
function NS.RemoveFromHistory(id)
  if not id then return false end

  for i, row in ipairs(NS.db.history) do
    if row.id == id then
      table.remove(NS.db.history, i)
      return true
    end
  end

  return false
end

--- The history as text, ready to export to the website.
---
--- The same line-based format as the import, in the other direction.
function NS.HistoryText()
  -- Zone and size for the header: primarily where we are now, otherwise
  -- the place of the most recent award. The website names the log from
  -- these.
  local zone, size = NS.Instance()

  if not zone then
    for i = #NS.db.history, 1, -1 do
      if NS.db.history[i].zone then
        zone = NS.db.history[i].zone
        size = NS.db.history[i].size or size
        break
      end
    end
  end

  local lines = {
    "LOOTHIST1",
    "RAID=" .. (NS.db.raidName or "?"),
    "TIME=" .. date("%Y-%m-%d %H:%M:%S"),
  }

  if zone then lines[#lines + 1] = "ZONE=" .. zone end
  if size and size > 0 then lines[#lines + 1] = "SIZE=" .. size end

  for _, row in ipairs(NS.db.history) do
    -- The zone per row as well: if one export holds two nights, the
    -- header can only name one of them.
    lines[#lines + 1] = ("L=%d|%s|%s|%s|%s|%s"):format(
      row.itemId, row.name, row.time,
      row.roll and tostring(row.roll) or "-",
      row.response or "-",
      row.zone or "-")
  end

  return table.concat(lines, "\n")
end

function NS.PrintProfiles()
  local count = 0
  for _ in pairs(NS.db.profiles) do count = count + 1 end

  if count == 0 then
    NS.Print("ei tuotuja profiileja. /lp tuo")
    return
  end

  NS.Print(("%s — %d hahmoa, tuotu %s"):format(
    NS.db.raidName or "?", count, NS.db.importedAt or "?"))

  local names = {}
  for character in pairs(NS.db.profiles) do names[#names + 1] = character end
  table.sort(names)

  for _, character in ipairs(names) do
    local n = 0
    for _ in pairs(NS.db.profiles[character]) do n = n + 1 end
    print(("  %s — %d valintaa"):format(character, n))
  end
end
