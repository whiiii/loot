--[[
  LootPrio — windows.

  One main window with navigation buttons on the left and the selected
  view on the right. Commands exist as a shortcut, but everything is
  reachable from buttons — nobody learns console commands mid-raid.

  UI strings are in Finnish because the guild is; the code around them is
  not.
]]

local ADDON, NS = ...

local QUALITY_COLOUR = {
  [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
  [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}

local GOLD = "|cffc9a227"
local DIM = "|cff8b9299"
local OK = "|cff8fd17a"
local BAD = "|cffe08c8c"

local function coloured(quality, text)
  return (QUALITY_COLOUR[quality or 1] or "|cffffffff") .. (text or "?") .. "|r"
end

--- A player's name in their class colour.
---
--- Class colour is the fastest way to tell names apart: a raid has 40 of
--- them, and a plain white list has to be read name by name.
local function classColour(fileName)
  local c = fileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[fileName]
  if not c then return "|cffffffff" end
  return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

--- An item's icon. The game's own database knows it even for an item that
--- has never been seen: the number is enough.
local function iconPath(item)
  if item.icon then return item.icon end
  if item.itemId and GetItemIcon then return GetItemIcon(item.itemId) end
  return nil
end

--- An icon square with a quality border.
local function makeIcon(parent, size, item)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)

  local texture = frame:CreateTexture(nil, "ARTWORK")
  texture:SetAllPoints()
  texture:SetTexture(iconPath(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
  -- Trim the edges: the game's icons have blank margins that make a list
  -- look restless.
  texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local colour = QUALITY_COLOUR[item.quality or 1]
  if colour then
    local r = tonumber(colour:sub(5, 6), 16) / 255
    local g = tonumber(colour:sub(7, 8), 16) / 255
    local b = tonumber(colour:sub(9, 10), 16) / 255
    frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    if frame.border.SetBackdrop then
      frame.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
      })
      frame.border:SetBackdropBorderColor(r, g, b, 1)
    end
  end

  return frame
end

local main            -- the main window
local views = {}      -- [key] = frame
local navButtons = {}
local currentView

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

--- A scrolling area that views draw their content into.
local function makeScroll(parent, name)
  local scroll = CreateFrame("ScrollFrame", name, parent,
    "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  scroll.content = content
  return scroll
end

--- Removes previously drawn child frames and strings.
---
--- Frames cannot be destroyed in Lua, so they are hidden and recycled.
--- Without recycling every redraw would leave the previous one underneath.
local function clear(container)
  if container.children then
    for _, child in ipairs(container.children) do
      child:Hide()
      child:SetParent(nil)
    end
  end
  container.children = {}
end

local function addChild(container, child)
  container.children = container.children or {}
  container.children[#container.children + 1] = child
  return child
end

local function label(parent, font, x, y, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

--- Attaches the game's item tooltip to a frame.
---
--- Mid-raid nobody remembers what "Wristguards of True Flight" is, and
--- opening a bag during a distribution is not an option.
local function itemTooltip(frame, link, itemId)
  if not link and not itemId then return frame end

  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    if link then
      GameTooltip:SetHyperlink(link)
    else
      GameTooltip:SetHyperlink("item:" .. itemId)
    end

    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return frame
end

--- Measures text so a tooltip's mouse area does not reach into blank space.
local measure
local function textWidth(text, font)
  if not measure then
    measure = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    measure:Hide()
  end

  measure:SetFontObject(_G[font or "GameFontHighlightSmall"])
  measure:SetText(text or "")
  return measure:GetStringWidth()
end

--- A mouse area over the name at the start of a row.
---
--- Only as wide as the name rather than the whole row: a full-row area
--- would pop the tooltip whenever the cursor crossed the list, and it
--- would cover the row's buttons.
local function nameArea(row, name, itemId, link, font)
  local area = CreateFrame("Frame", nil, row)
  area:SetPoint("TOPLEFT", 4, 0)
  area:SetSize(textWidth(name, font) + 8, row:GetHeight())
  return itemTooltip(area, link, itemId)
end

local function button(parent, width, height, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

--------------------------------------------------------------------------
-- Main window and navigation
--------------------------------------------------------------------------

local NAV = {
  { key = "loot",     title = "Loot" },
  { key = "trade",    title = "Kauppa" },
  { key = "members",  title = "Jäsenet" },
  { key = "history",  title = "Historia" },
  { key = "import",   title = "Tuonti" },
  { key = "settings", title = "Asetukset" },
}

local function showView(key)
  currentView = key

  for name, frame in pairs(views) do
    if name == key then frame:Show() else frame:Hide() end
  end

  for name, b in pairs(navButtons) do
    -- The selected button stays pushed in, so you can see where you are.
    if name == key then b:LockHighlight() else b:UnlockHighlight() end
  end

  if NS.RefreshView then NS.RefreshView(key) end
end

local function createMain()
  main = CreateFrame("Frame", "LootPrioMain", UIParent,
    "BasicFrameTemplateWithInset")
  main:SetSize(660, 500)
  main:SetPoint("CENTER")
  main:SetMovable(true)
  main:EnableMouse(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", main.StartMoving)
  main:SetScript("OnDragStop", main.StopMovingOrSizing)
  main:SetClampedToScreen(true)
  main:Hide()
  main.TitleText:SetText("LootPrio")
  tinsert(UISpecialFrames, "LootPrioMain")

  -- Navigation on the left.
  local y = -34
  for _, entry in ipairs(NAV) do
    local b = button(main, 104, 24, entry.title, function()
      showView(entry.key)
    end)
    b:SetPoint("TOPLEFT", 12, y)
    navButtons[entry.key] = b
    y = y - 27
  end

  -- Status line along the bottom.
  main.status = main:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  main.status:SetPoint("BOTTOMLEFT", 14, 12)
  main.status:SetPoint("BOTTOMRIGHT", -14, 12)
  main.status:SetJustifyH("LEFT")

  -- The view area on the right.
  for _, entry in ipairs(NAV) do
    local frame = CreateFrame("Frame", nil, main)
    frame:SetPoint("TOPLEFT", 126, -32)
    frame:SetPoint("BOTTOMRIGHT", -12, 30)
    frame:Hide()
    views[entry.key] = frame
  end
end

function NS.Open(view)
  if not main then createMain() end
  main:Show()
  showView(view or currentView or "loot")
end

local function refreshStatus()
  if not main then return end

  local count = 0
  for _ in pairs(NS.db.profiles) do count = count + 1 end

  main.status:SetText(("%s%s|r  ·  %d jäsentä  ·  tuotu %s  ·  arvonnat: %s"):format(
    GOLD, NS.db.raidName or "ei dataa", count, NS.db.importedAt or "—",
    NS.db.rollVisibility == "raid" and "koko raidi" or "vain officerit"))

  -- The number of undelivered trades on the nav button: it is a to-do
  -- list, and a forgotten handover must not hide behind a tab.
  if navButtons.trade then
    local pending = NS.PendingTrades and #NS.PendingTrades() or 0
    navButtons.trade:SetText(
      pending > 0 and ("Kauppa (" .. pending .. ")") or "Kauppa")
  end
end

--------------------------------------------------------------------------
-- View: Loot
--------------------------------------------------------------------------

--- An item's name and quality. The master gets them from the bags, others
--- from the game's database — which may not know the item immediately.
local function itemName(item)
  if item.name then return item.name, item.quality or 1 end
  local name, _, quality = GetItemInfo(item.itemId)
  return name or ("item " .. item.itemId), quality or 1
end

--- The current distribution's results: who got what and on which button.
---
--- This is what a raider sees. They do not see who answered what during
--- the voting, but the outcome and its reason are open — otherwise the
--- master's decision could not be followed at all.
---
--- For an officer the same list is a summary of the night below the
--- response list.
local function drawAwarded(content, y)
  local session = NS.session
  if not session then return y end

  local awarded = {}
  for _, item in pairs(session.items) do
    if item.awarded then awarded[#awarded + 1] = item end
  end
  if #awarded == 0 then return y end

  table.sort(awarded, function(a, b) return a.index < b.index end)

  local header = addChild(content, CreateFrame("Frame", nil, content))
  header:SetPoint("TOPLEFT", 0, y - 8)
  header:SetPoint("TOPRIGHT", 0, y - 8)
  header:SetHeight(18)
  label(header, "GameFontNormalSmall", 8, 0, "JAETUT")
  y = y - 28

  local classes = NS.RaidClasses()

  for _, item in ipairs(awarded) do
    local name, quality = itemName(item)

    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(22)

    local icon = makeIcon(row, 18, item)
    icon:SetPoint("TOPLEFT", 8, -2)
    itemTooltip(icon, item.link, item.itemId)

    local short = name:len() > 24 and (name:sub(1, 23) .. "…") or name
    label(row, "GameFontHighlightSmall", 32, -4, coloured(quality, short))

    label(row, "GameFontHighlightSmall", 210, -4,
      OK .. "→|r " .. classColour(classes[item.winner])
        .. (item.winner or "?") .. "|r")

    -- On which button: without the reason the list would give only the
    -- outcome, not why it is the outcome.
    local response = item.winnerCode and NS.RESPONSE[item.winnerCode]
    label(row, "GameFontHighlightSmall", 340, -4,
      response and (response.colour .. response.name .. "|r") or (DIM .. "—|r"))

    y = y - 22
  end

  return y
end

local function drawLoot()
  local frame = views.loot

  if not frame.built then
    frame.built = true

    frame.tabs = CreateFrame("Frame", nil, frame)
    frame.tabs:SetPoint("TOPLEFT", 0, 0)
    frame.tabs:SetPoint("TOPRIGHT", 0, 0)
    frame.tabs:SetHeight(36)

    frame.scroll = makeScroll(frame, "LootPrioLootScroll")
    frame.scroll:SetPoint("TOPLEFT", 0, -42)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 28)

    frame.buttons = CreateFrame("Frame", nil, frame)
    frame.buttons:SetPoint("BOTTOMLEFT", 0, 0)
    frame.buttons:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.buttons:SetHeight(26)

    frame.endButton = button(frame.buttons, 110, 22, "Päätä jako", function()
      -- A summary to raid chat: it removes arguments before there are any.
      NS.EndSession(true)
    end)
    frame.endButton:SetPoint("BOTTOMLEFT", 0, 0)

    frame.closeButton = button(frame.buttons, 130, 22, "Sulje vastaukset", function()
      NS.CloseResponses()
    end)
    frame.closeButton:SetPoint("BOTTOMLEFT", 114, 0)

    frame.undoButton = button(frame.buttons, 100, 22, "Peru jako", function()
      NS.UndoAward()
    end)
    frame.undoButton:SetPoint("BOTTOMLEFT", 248, 0)

    -- The master can drop offline mid-distribution. Without this the
    -- whole raid would wait for them to come back.
    frame.takeOver = button(frame.buttons, 150, 22, "Ota jako haltuun", function()
      NS.TakeOver()
    end)
    frame.takeOver:SetPoint("BOTTOMLEFT", 352, 0)

    -- Elapsed time on the right. Nothing forces an end, but there has to
    -- be somewhere to see when waiting stops producing responses.
    frame.clock = frame.buttons:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.clock:SetPoint("BOTTOMRIGHT", -4, 4)

    frame.buttons:SetScript("OnUpdate", function(self, elapsed)
      self.sinceUpdate = (self.sinceUpdate or 0) + elapsed
      if self.sinceUpdate < 1 then return end
      self.sinceUpdate = 0

      if not NS.session then
        frame.clock:SetText("")
        return
      end

      local seconds = NS.SessionElapsed()
      local limit = NS.db.responseTime or 90
      local colour = (seconds > limit and not NS.session.closed) and BAD or DIM

      frame.clock:SetText(("%s%d:%02d%s"):format(
        colour, math.floor(seconds / 60), seconds % 60,
        NS.session.closed and "  suljettu|r" or "|r"))
    end)
  end

  clear(frame.tabs)
  clear(frame.buttons)

  local content = frame.scroll.content
  clear(content)
  content:SetWidth(frame:GetWidth() - 26)

  local session = NS.session
  local officer = NS.IsOfficer()

  -- The distribution buttons only for the one distributing. They used to
  -- show for every assist, which let two officers push the same item in
  -- different directions.
  local distributor = session ~= nil and session.master == NS.MyName()

  frame.endButton:SetShown(distributor)
  frame.closeButton:SetShown(distributor and not session.closed)
  frame.undoButton:SetShown(distributor and session.lastAwarded ~= nil)

  -- Taking over only for the leader, and only if someone else holds it.
  frame.takeOver:SetShown(
    session ~= nil and not distributor and NS.IsLeader() and not session.test)

  if not session then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, -4)
    row:SetPoint("TOPRIGHT", 0, -4)
    row:SetHeight(90)

    if officer then
      label(row, "GameFontDisableSmall", 4, 0,
        "Ei jakoa käynnissä.\n\nKerää lootit laukkuihisi ja paina Jaa lootit.\n"
        .. "Jaon avaaja on sen illan lootmaster.")

      local b = button(row, 130, 24, "Jaa lootit", function()
        NS.OpenPicker()
      end)
      b:SetPoint("TOPLEFT", 4, -56)
    elseif not NS.IsSiteOfficer(NS.MyName()) and NS.HasRaidRank() then
      -- A raid assist without guild officer rights. Without this
      -- explanation the button would simply be missing and nothing would
      -- say why.
      label(row, "GameFontDisableSmall", 4, 0,
        "Ei jakoa käynnissä.\n\n"
        .. BAD .. "Sinulla on raid assist, mutta et ole officer\n"
        .. "killan sivustolla — jakoa ei voi avata.|r\n"
        .. "Pyydä officer-oikeutta tai anna jako toiselle.")
    else
      label(row, "GameFontDisableSmall", 4, 0,
        "Ei jakoa käynnissä.\n\nVastausikkuna aukeaa itsestään kun\n"
        .. "lootmaster laittaa lootit jakoon.")
    end

    content:SetHeight(96)
    return
  end

  -- Tabs only for items not yet awarded: an awarded one leaves the list
  -- and stays in the history, so what is left is always what is still
  -- undecided.
  local open = NS.OpenItems()

  if #open == 0 then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, -4)
    row:SetHeight(40)
    label(row, "GameFontNormal", 4, 0, OK .. "Kaikki jaettu.|r")
    label(row, "GameFontDisableSmall", 4, -20,
      "Tulokset jäävät Historia-välilehdelle.")

    -- The results here too: without them the last award would leave an
    -- empty screen exactly when everyone wants to know what went where.
    local y = drawAwarded(content, -44)
    content:SetHeight(math.max(1, -y))
    return
  end

  if not session.selected or not session.items[session.selected]
     or session.items[session.selected].awarded then
    session.selected = open[1].index
  end

  -- Tabs as icons rather than names. Six items do not fit on a row as
  -- names without cutting them to thirteen characters, and a cut name is
  -- worse to recognise than an icon.
  local x = 0
  for _, item in ipairs(open) do
    local b = CreateFrame("Button", nil, frame.tabs)
    b:SetSize(34, 34)
    b:SetPoint("TOPLEFT", x, 0)

    local texture = b:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture(iconPath(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- The selected one stands out bright, the rest are dimmed. A border
    -- alone does not read clearly enough with icons side by side.
    if session.selected == item.index then
      local glow = b:CreateTexture(nil, "OVERLAY")
      glow:SetPoint("TOPLEFT", -2, 2)
      glow:SetPoint("BOTTOMRIGHT", 2, -2)
      glow:SetColorTexture(0.79, 0.64, 0.15, 0.85)
      glow:SetDrawLayer("BACKGROUND")
    else
      texture:SetVertexColor(0.45, 0.45, 0.45)
    end

    -- The response count in the icon's corner: it shows at a glance which
    -- item is still waiting.
    --
    -- Only for those who may see the responses. The number does not say
    -- who answered what, but it is still information about how the vote
    -- is going — and a raider is meant to see only the outcome.
    if NS.ShowAllResponses() then
      local responded = 0
      for _ in pairs(item.responses) do responded = responded + 1 end

      local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      count:SetPoint("BOTTOMRIGHT", -1, 1)
      count:SetText(responded > 0 and tostring(responded) or "")
    end

    b:SetScript("OnClick", function()
      session.selected = item.index
      NS.RefreshView("loot")
    end)

    itemTooltip(b, item.link, item.itemId)
    addChild(frame.tabs, b)

    x = x + 38
  end

  local item = session.items[session.selected]
  if not item then return end

  local name, quality = itemName(item)
  local y = -4

  -- Header row: icon, name and who is distributing. The master's name is
  -- here because everyone needs to see whose decision is being waited on.
  local header = addChild(content, CreateFrame("Frame", nil, content))
  header:SetPoint("TOPLEFT", 0, y)
  header:SetPoint("TOPRIGHT", 0, y)
  header:SetHeight(38)

  local icon = makeIcon(header, 32, item)
  icon:SetPoint("TOPLEFT", 4, -2)
  itemTooltip(icon, item.link, item.itemId)

  label(header, "GameFontNormal", 42, -2,
    coloured(quality, name)
    .. (item.awarded and ("  " .. OK .. "→ " .. (item.winner or "?") .. "|r") or ""))

  local master = session.master or "?"
  label(header, "GameFontDisableSmall", 42, -20,
    ("jakaa: %s%s|r%s"):format(
      NS.IsPresent(master) and DIM or BAD, master,
      NS.IsPresent(master) and "" or (BAD .. " (poissa)|r")))

  y = y - 42

  -- Our own response buttons, if the item has not been awarded yet.
  if not item.awarded then
    local buttons = addChild(content, CreateFrame("Frame", nil, content))
    buttons:SetPoint("TOPLEFT", 0, y)
    buttons:SetPoint("TOPRIGHT", 0, y)
    buttons:SetHeight(24)

    local chosen = session.ownResponse[item.index]
    local bx = 4

    for _, response in ipairs(NS.RESPONSES) do
      -- LootPrio only if the item really is in our own profile. The
      -- website decides that, not the player's own estimate.
      local allowed = (response.code ~= "prio") or NS.InOwnProfile(item.itemId)
      local width = (response.code == "pass") and 50 or 68

      local b = button(buttons, width, 20, response.name, function()
        NS.Respond(item.index, response.code)
      end)
      b:SetPoint("TOPLEFT", bx, 0)
      b:SetEnabled(allowed and not chosen and not session.closed)
      if chosen == response.code then b:LockHighlight() end

      bx = bx + width + 4
    end

    y = y - 28

    -- The reason for a greyed button, visible. Without it the player
    -- cannot tell whether the distribution is closed, the profile is
    -- missing, or their own answer already went through.
    if session.closed or not NS.InOwnProfile(item.itemId) then
      local reason = addChild(content, CreateFrame("Frame", nil, content))
      reason:SetPoint("TOPLEFT", 0, y)
      reason:SetHeight(14)
      label(reason, "GameFontDisableSmall", 8, 0,
        session.closed and "vastaukset suljettu"
          or "LootPrio ei käytössä: item ei ole profiilissasi")
      y = y - 16
    end
  end

  -- Responses. The master's setting decides whether everyone's responses
  -- are shown or only our own.
  local showAll = NS.ShowAllResponses()
  local responses = NS.ItemResponses(item)

  if not showAll then
    local own = {}
    for _, r in ipairs(responses) do
      if r.name == NS.MyName() then own[#own + 1] = r end
    end
    responses = own
  end

  if #responses == 0 then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    row:SetHeight(18)
    label(row, "GameFontDisableSmall", 8, 0, "ei vastauksia vielä")
    y = y - 20
  else
    -- The headers sort. The default is the reason, because that decides —
    -- but received items or the roll may be what is being looked for.
    local headers = addChild(content, CreateFrame("Frame", nil, content))
    headers:SetPoint("TOPLEFT", 0, y)
    headers:SetPoint("TOPRIGHT", 0, y)
    headers:SetHeight(18)

    local COLUMNS = {
      { field = "order",    title = "VASTAUS", x = 8 },
      { field = "roll",     title = "ROLL",    x = 92 },
      { field = "name",     title = "PELAAJA", x = 130 },
      { field = "received", title = "SAATU",   x = 250 },
    }

    for _, column in ipairs(COLUMNS) do
      local marker = ""
      if NS.sortField == column.field then
        marker = NS.sortAscending and " ▲" or " ▼"
      end

      local b = CreateFrame("Button", nil, headers)
      b:SetSize(76, 16)
      b:SetPoint("TOPLEFT", column.x - 4, 0)

      local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      fs:SetPoint("LEFT", 4, 0)
      fs:SetText(column.title .. marker)

      b:SetScript("OnClick", function()
        if NS.sortField == column.field then
          NS.sortAscending = not NS.sortAscending
        else
          NS.sortField = column.field
          NS.sortAscending = (column.field == "order" or column.field == "name")
        end
        NS.RefreshView("loot")
      end)
    end

    y = y - 18

    local classes = NS.RaidClasses()
    local striped = false

    for _, r in ipairs(responses) do
      local response = NS.RESPONSE[r.code]

      local row = addChild(content, CreateFrame("Frame", nil, content))
      row:SetPoint("TOPLEFT", 0, y)
      row:SetPoint("TOPRIGHT", 0, y)
      row:SetHeight(20)

      -- Every other row darker. In a list of forty names the eye loses
      -- the row without it.
      striped = not striped
      if striped then
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(1, 1, 1, 0.03)
      end

      label(row, "GameFontHighlightSmall", 8, -3,
        response.colour .. response.name .. "|r")
      label(row, "GameFontHighlightSmall", 92, -3,
        GOLD .. (r.roll and tostring(r.roll) or "—") .. "|r")

      -- A wrongly justified prio is marked. The check is made on every
      -- machine against the imported profiles, so the claim shows to all.
      local warning = ""
      if r.code == "prio" and not r.prioOk then
        warning = BAD .. " (!)|r"
      end

      label(row, "GameFontHighlightSmall", 130, -3,
        classColour(classes[r.name]) .. r.name .. "|r" .. warning)

      -- How many items the player has already received. The master's most
      -- important number right after the reason.
      label(row, "GameFontHighlightSmall", 250, -3,
        (r.received > 0 and GOLD or DIM) .. tostring(r.received) .. "|r")

      if distributor and not item.awarded and r.code ~= "pass" then
        local b = button(row, 70, 18, "Anna", function()
          NS.Award(item, r.name)
        end)
        b:SetPoint("TOPRIGHT", -8, -1)
      end

      y = y - 20
    end
  end

  local missing = NS.NotResponded(item)
  if #missing > 0 and not item.awarded and showAll then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y - 6)
    row:SetPoint("TOPRIGHT", 0, y - 6)
    row:SetHeight(30)
    label(row, "GameFontDisableSmall", 8, 0,
      ("odottaa %d vastausta: %s%s"):format(#missing,
        table.concat(missing, ", ", 1, math.min(6, #missing)),
        #missing > 6 and ", …" or ""))
    y = y - 36
  end

  y = drawAwarded(content, y)

  content:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- View: Trade
--------------------------------------------------------------------------

--- Items waiting to be handed over.
---
--- The addon cannot give an item away from a bag, but it fills the trade
--- window when the master opens a trade with a winner. This list is what
--- is still undelivered.
local function drawTrade()
  local frame = views.trade

  if not frame.built then
    frame.built = true

    frame.info = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.info:SetPoint("TOPLEFT", 4, -4)
    frame.info:SetPoint("TOPRIGHT", -4, -4)
    frame.info:SetJustifyH("LEFT")

    frame.scroll = makeScroll(frame, "LootPrioTradeScroll")
    frame.scroll:SetPoint("TOPLEFT", 0, -38)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 30)

    local tidy = button(frame, 150, 22, "Siivoa toimitetut", function()
      local n = NS.ClearDeliveredTrades()
      NS.Print(("%d toimitettua riviä poistettu."):format(n))
    end)
    tidy:SetPoint("BOTTOMLEFT", 0, 4)
  end

  local queue = NS.PendingTrades()

  frame.info:SetText(("Luovuttamatta: %s%d|r\nAvaa kauppa pelaajan kanssa — "
    .. "itemit asettuvat paikoilleen itsestään."):format(GOLD, #queue))

  local content = frame.scroll.content
  clear(content)
  content:SetWidth(frame:GetWidth() - 26)

  local y = -4

  if #queue == 0 then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    label(row, "GameFontDisableSmall", 4, 0, "Ei luovuttamattomia itemeitä.")
    content:SetHeight(30)
    return
  end

  local header = addChild(content, CreateFrame("Frame", nil, content))
  header:SetPoint("TOPLEFT", 0, y)
  label(header, "GameFontNormalSmall", 4, 0, "ITEM")
  label(header, "GameFontNormalSmall", 200, 0, "SAAJA")
  label(header, "GameFontNormalSmall", 300, 0, "LAUKUSSA")
  y = y - 18

  -- Is the item really in a bag. If not, the trade window would stay
  -- empty — and the reason is better seen here than after it opens.
  local inBags = {}
  for _, item in ipairs(NS.BagItems(0)) do
    inBags[item.itemId] = true
  end

  for _, entry in ipairs(queue) do
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(18)

    local name = entry.itemName
    if not name and entry.itemId then name = GetItemInfo(entry.itemId) end
    name = name or ("item " .. tostring(entry.itemId))
    if name:len() > 28 then name = name:sub(1, 27) .. "…" end

    label(row, "GameFontHighlightSmall", 4, 0, name)
    nameArea(row, name, entry.itemId, entry.link)
    label(row, "GameFontHighlightSmall", 200, 0, entry.name or "?")
    label(row, "GameFontHighlightSmall", 300, 0,
      inBags[entry.itemId] and (OK .. "kyllä|r") or (BAD .. "ei|r"))

    -- An item handed over outside a trade has to be markable by hand: the
    -- addon only sees bag changes in its own trade.
    local b = button(row, 80, 18, "Annettu", function()
      NS.MarkDelivered(entry.index)
    end)
    b:SetPoint("TOPRIGHT", -8, 0)

    y = y - 18
  end

  content:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- View: Members
--------------------------------------------------------------------------

--- One player's addon status: text and colour.
---
--- Three distinct states, because each needs a different action: a
--- missing addon has to be installed, an old one updated, and an
--- unimported export imported. One shared "did not answer" would not say
--- which it is.
local function addonStatus(name)
  local entry = NS.addons and NS.addons[name]

  if not entry then return DIM .. "—|r" end
  if NS.VersionOlder(entry.version, NS.VERSION) then
    return BAD .. "v" .. entry.version .. "|r"
  end
  if entry.profileCount == 0 then return BAD .. "ei dataa|r" end

  return OK .. "v" .. entry.version .. "|r"
end

local function drawMembers()
  local frame = views.members

  if not frame.built then
    frame.built = true

    frame.scroll = makeScroll(frame, "LootPrioMemberScroll")
    frame.scroll:SetPoint("TOPLEFT", 0, 0)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 28)

    local check = button(frame, 150, 22, "Tarkista addonit", function()
      NS.AskVersions()
      NS.Print("kysytty. Vastaukset saapuvat parin sekunnin kuluessa.")
    end)
    check:SetPoint("BOTTOMLEFT", 0, 0)

    frame.note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.note:SetPoint("BOTTOMLEFT", 158, 6)
    frame.note:SetPoint("BOTTOMRIGHT", -4, 6)
    frame.note:SetJustifyH("LEFT")
  end

  local content = frame.scroll.content
  clear(content)
  content:SetWidth(frame:GetWidth() - 26)

  local members = NS.Members()
  local y = -4

  if #members == 0 then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    label(row, "GameFontDisableSmall", 4, 0,
      "Ei tuotuja profiileja. Tuonti-välilehdeltä.")
    content:SetHeight(30)
    frame.note:SetText("")
    return
  end

  local inRaid = NS.RaidMembers()

  local header = addChild(content, CreateFrame("Frame", nil, content))
  header:SetPoint("TOPLEFT", 0, y)
  label(header, "GameFontNormalSmall", 4, 0, "HAHMO")
  label(header, "GameFontNormalSmall", 150, 0, "VALINNAT")
  label(header, "GameFontNormalSmall", 215, 0, "SAATU")
  label(header, "GameFontNormalSmall", 280, 0, "ADDON")
  y = y - 18

  local withoutAddon = 0

  for _, member in ipairs(members) do
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(16)

    -- Someone present stands out: the master cares who is here now.
    local present = inRaid[member.name]
    local colour = present and "" or DIM

    -- Officers are marked: it shows who can open a distribution without
    -- having to guess who has rights on the website.
    local marker = (NS.db.officers and NS.db.officers[member.name])
      and (GOLD .. " \226\151\134|r") or ""

    label(row, "GameFontHighlightSmall", 4, 0,
      colour .. member.name .. "|r" .. marker)
    label(row, "GameFontHighlightSmall", 150, 0, tostring(member.picks))

    -- The website's number in brackets: it shows whether SAATU is the
    -- guild's history or only what this machine recorded.
    local total = NS.ReceivedCount(member.name)
    local fromSite = NS.ReceivedFromSite(member.name)
    label(row, "GameFontHighlightSmall", 215, 0,
      tostring(total)
      .. (total > fromSite and (DIM .. " (+" .. (total - fromSite) .. ")|r") or ""))

    if present then
      label(row, "GameFontHighlightSmall", 280, 0, addonStatus(member.name))
      if not (NS.addons and NS.addons[member.name]) then
        withoutAddon = withoutAddon + 1
      end
    end

    y = y - 16
  end

  content:SetHeight(math.max(1, -y))

  -- Those present with no profile at all: for them the distribution looks
  -- broken, because the LootPrio button is grey and nothing says why.
  local withoutProfile = {}
  for name, online in pairs(inRaid) do
    if online and not NS.db.profiles[name] then
      withoutProfile[#withoutProfile + 1] = name
    end
  end
  table.sort(withoutProfile)

  local parts = {}
  if withoutAddon > 0 then
    parts[#parts + 1] = ("%s%d ilman addonia|r"):format(BAD, withoutAddon)
  end
  if #withoutProfile > 0 then
    parts[#parts + 1] = ("%sei profiilia: %s%s|r"):format(BAD,
      table.concat(withoutProfile, ", ", 1, math.min(4, #withoutProfile)),
      #withoutProfile > 4 and ", …" or "")
  end

  frame.note:SetText(table.concat(parts, "  ·  "))
end

--------------------------------------------------------------------------
-- View: History
--------------------------------------------------------------------------

local function drawHistory()
  local frame = views.history

  if not frame.built then
    frame.built = true

    frame.info = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.info:SetPoint("TOPLEFT", 4, -4)
    frame.info:SetPoint("TOPRIGHT", -4, -4)
    frame.info:SetJustifyH("LEFT")

    -- The list and the export box share one place, one at a time. The
    -- list is what is usually looked at, the export only at the end of a
    -- raid.
    frame.scroll = makeScroll(frame, "LootPrioHistListScroll")
    frame.scroll:SetPoint("TOPLEFT", 0, -24)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 30)

    local exportScroll = CreateFrame("ScrollFrame", "LootPrioHistScroll", frame,
      "UIPanelScrollFrameTemplate")
    exportScroll:SetPoint("TOPLEFT", 0, -24)
    exportScroll:SetPoint("BOTTOMRIGHT", -26, 30)
    exportScroll:Hide()
    frame.exportScroll = exportScroll

    local editBox = CreateFrame("EditBox", nil, exportScroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(380)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function() main:Hide() end)
    exportScroll:SetScrollChild(editBox)
    frame.editBox = editBox

    frame.exportButton = button(frame, 150, 22, "Luo vienti sivustolle", function()
      if frame.exportScroll:IsShown() then
        frame.exportScroll:Hide()
        frame.scroll:Show()
        frame.exportButton:SetText("Luo vienti sivustolle")
        return
      end

      frame.scroll:Hide()
      frame.exportScroll:Show()
      frame.exportButton:SetText("Takaisin listaan")
      frame.editBox:SetText(NS.HistoryText())
      frame.editBox:HighlightText()
      frame.editBox:SetFocus()
      NS.Print("kopioi teksti Ctrl+C ja liitä sivuston ylläpitoon.")
    end)
    frame.exportButton:SetPoint("BOTTOMLEFT", 0, 4)

    local clearButton = button(frame, 110, 22, "Tyhjennä", function()
      NS.db.history = {}
      frame.editBox:SetText("")
      NS.RefreshView("history")
      NS.Print("historia tyhjennetty.")
    end)
    clearButton:SetPoint("BOTTOMLEFT", 156, 4)
  end

  -- The instance, visible: the website names the log from it, and if the
  -- wrong place is shown here the export should be made before the next
  -- raid.
  local zone, size = NS.Instance()
  local place = zone and (zone .. (size > 0 and (" " .. size .. "-man") or ""))

  frame.info:SetText(("Jaettuja itemeitä: %s%d|r   %s"):format(
    GOLD, #NS.db.history,
    place and (DIM .. place .. "|r") or ""))

  local content = frame.scroll.content
  clear(content)
  content:SetWidth(frame:GetWidth() - 26)

  local y = -4

  if #NS.db.history == 0 then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    label(row, "GameFontDisableSmall", 4, 0,
      "Ei jaettuja itemeitä. Jaetut näkyvät täällä heti kun ne on annettu.")
    content:SetHeight(30)
    return
  end

  local header = addChild(content, CreateFrame("Frame", nil, content))
  header:SetPoint("TOPLEFT", 0, y)
  label(header, "GameFontNormalSmall", 4, 0, "ITEM")
  label(header, "GameFontNormalSmall", 190, 0, "SAAJA")
  label(header, "GameFontNormalSmall", 300, 0, "PERUSTE")
  label(header, "GameFontNormalSmall", 390, 0, "ROLL")
  y = y - 18

  -- Newest at the top: the most recent award is what usually gets checked.
  for i = #NS.db.history, 1, -1 do
    local entry = NS.db.history[i]

    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(16)

    local name = entry.itemName
    if not name and entry.itemId then name = GetItemInfo(entry.itemId) end
    name = name or ("item " .. tostring(entry.itemId))
    if name:len() > 26 then name = name:sub(1, 25) .. "…" end

    label(row, "GameFontHighlightSmall", 4, 0, name)
    nameArea(row, name, entry.itemId)
    label(row, "GameFontHighlightSmall", 190, 0, entry.name or "?")

    -- The reason, i.e. "on which button": the same colour as the response
    -- button.
    local response = entry.response and NS.RESPONSE[entry.response]
    label(row, "GameFontHighlightSmall", 300, 0,
      response and (response.colour .. response.name .. "|r") or (DIM .. "—|r"))

    label(row, "GameFontHighlightSmall", 390, 0,
      entry.roll and (GOLD .. tostring(entry.roll) .. "|r") or (DIM .. "—|r"))

    y = y - 16
  end

  content:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- View: Import
--------------------------------------------------------------------------

local function drawImport()
  local frame = views.import

  if not frame.built then
    frame.built = true

    local info = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", 4, -4)
    info:SetPoint("TOPRIGHT", -4, -4)
    info:SetJustifyH("LEFT")
    info:SetText("Liitä sivuston \"Vienti addoniin\" -teksti (Ctrl+V) ja paina Tuo.")

    local scroll = CreateFrame("ScrollFrame", "LootPrioImportScroll", frame,
      "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -34)
    scroll:SetPoint("BOTTOMRIGHT", -26, 30)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(380)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function() main:Hide() end)
    scroll:SetScrollChild(editBox)
    frame.editBox = editBox

    frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.status:SetPoint("BOTTOMLEFT", 120, 10)

    local importButton = button(frame, 100, 22, "Tuo", function()
      local data, err = NS.Import(frame.editBox:GetText())
      if not data then
        frame.status:SetText(BAD .. (err or "Tuonti epäonnistui.") .. "|r")
        return
      end
      frame.status:SetText(("%s%s — %d hahmoa.|r"):format(
        OK, data.raidName, data.characterCount))
      frame.editBox:SetText("")
      refreshStatus()
      showView("members")
    end)
    importButton:SetPoint("BOTTOMLEFT", 0, 4)
  end

  frame.editBox:SetFocus()
end

--------------------------------------------------------------------------
-- View: Settings
--------------------------------------------------------------------------

local function drawSettings()
  local frame = views.settings

  if not frame.built then
    frame.built = true

    local visibility = CreateFrame("CheckButton", "LootPrioRaidRolls", frame,
      "UICheckButtonTemplate")
    visibility:SetPoint("TOPLEFT", 2, -8)
    visibility:SetSize(24, 24)
    _G[visibility:GetName() .. "Text"]:SetText(
      "Myös raiderit näkevät kaikki vastaukset")
    visibility:SetScript("OnClick", function(self)
      NS.db.rollVisibility = self:GetChecked() and "raid" or "officers"
      refreshStatus()
    end)
    frame.visibility = visibility

    local note = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 6, -36)
    note:SetPoint("TOPRIGHT", -6, -36)
    note:SetJustifyH("LEFT")
    note:SetText("Pois päältä raideri näkee oman vastauksensa ja sen mitä "
      .. "on jo jaettu — kuka sai ja millä napilla. Officerit näkevät kaikkien "
      .. "vastaukset, jotta itemistä voi keskustella ennen antamista. Asetus "
      .. "koskee vain sinun avaamiasi jakoja, ja se on näkyvyysvalinta eikä "
      .. "salaisuus: tiedot kulkevat raidikanavalla joka tapauksessa.")

    local announce = CreateFrame("CheckButton", "LootPrioAnnounce", frame,
      "UICheckButtonTemplate")
    announce:SetPoint("TOPLEFT", 2, -76)
    announce:SetSize(24, 24)
    _G[announce:GetName() .. "Text"]:SetText("Ilmoita voittaja raidichattiin")
    announce:SetScript("OnClick", function(self)
      NS.db.announceWinner = self:GetChecked() and true or false
    end)
    frame.announce = announce

    local trade = CreateFrame("CheckButton", "LootPrioAutoTrade", frame,
      "UICheckButtonTemplate")
    trade:SetPoint("TOPLEFT", 2, -98)
    trade:SetSize(24, 24)
    _G[trade:GetName() .. "Text"]:SetText("Täytä kauppaikkuna itsestään")
    trade:SetScript("OnClick", function(self)
      NS.db.autoFillTrade = self:GetChecked() and true or false
    end)
    frame.trade = trade

    -- The quality limit decides what the bags offer for distribution.
    local qualityLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    qualityLabel:SetPoint("TOPLEFT", 6, -124)
    qualityLabel:SetText("Jaettavien vähimmäislaatu:")

    local qualities = {
      { quality = 2, name = "Vihreä" },
      { quality = 3, name = "Sininen" },
      { quality = 4, name = "Violetti" },
    }

    frame.qualityButtons = {}
    local qx = 4
    for _, entry in ipairs(qualities) do
      local b = button(frame, 74, 22, entry.name, function()
        NS.db.bagQuality = entry.quality
        drawSettings()
      end)
      b:SetPoint("TOPLEFT", qx, -144)
      frame.qualityButtons[entry.quality] = b
      qx = qx + 78
    end

    -- The response time forces nothing: it changes the clock's colour,
    -- and the master decides when waiting stops producing responses.
    local timeLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    timeLabel:SetPoint("TOPLEFT", 6, -176)
    timeLabel:SetText("Muistuta vastauksista:")

    local times = { 60, 90, 120 }
    frame.timeButtons = {}
    local tx = 4
    for _, seconds in ipairs(times) do
      local b = button(frame, 74, 22, seconds .. " s", function()
        NS.db.responseTime = seconds
        drawSettings()
      end)
      b:SetPoint("TOPLEFT", tx, -196)
      frame.timeButtons[seconds] = b
      tx = tx + 78
    end

    local test = button(frame, 160, 24, "Käynnistä testi", function()
      if NS.StartTest() then showView("loot") end
    end)
    test:SetPoint("TOPLEFT", 4, -228)

    local testNote = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    testNote:SetPoint("TOPLEFT", 6, -256)
    testNote:SetPoint("TOPRIGHT", -6, -256)
    testNote:SetJustifyH("LEFT")
    testNote:SetText("Tekee neljä kuviteltua loottia tuoduista valinnoista ja "
      .. "arpoo niihin vastaukset. Anna kirjaa historiaan mutta ei koske "
      .. "pelin loottiin eikä lähetä mitään raidille.")

    local clearProfiles = button(frame, 160, 24, "Poista profiilit", function()
      NS.db.profiles = {}
      NS.db.raidName = nil
      NS.db.importedAt = nil
      refreshStatus()
      showView("members")
    end)
    clearProfiles:SetPoint("TOPLEFT", 4, -300)
  end

  frame.visibility:SetChecked(NS.db.rollVisibility == "raid")
  frame.announce:SetChecked(NS.db.announceWinner)
  frame.trade:SetChecked(NS.db.autoFillTrade ~= false)

  -- The chosen value stays pushed in, so the current setting is visible.
  for quality, b in pairs(frame.qualityButtons) do
    if quality == (NS.db.bagQuality or 3) then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end

  for seconds, b in pairs(frame.timeButtons) do
    if seconds == (NS.db.responseTime or 90) then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end
end

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

function NS.RefreshView(key)
  key = key or currentView
  if not main or not main:IsShown() then return end

  refreshStatus()

  if key == "loot" then drawLoot()
  elseif key == "trade" then drawTrade()
  elseif key == "members" then drawMembers()
  elseif key == "history" then drawHistory()
  elseif key == "import" then drawImport()
  elseif key == "settings" then drawSettings()
  end
end

--------------------------------------------------------------------------
-- Picking items from the bags
--------------------------------------------------------------------------

local picker
local selected = {}

-- Items linked by hand. Not everything to be distributed is in the
-- master's bags: an item may be held by another player or already traded
-- wrongly, and the distribution must not depend on that.
local manual = {}

--- The window where an officer picks the items to distribute.
---
--- The list is limited to equippable items of decent quality: without the
--- limit it would hold every water flask and bolt of cloth.
function NS.OpenPicker()
  if not picker then
    picker = CreateFrame("Frame", "LootPrioPicker", UIParent,
      "BasicFrameTemplateWithInset")
    picker:SetSize(460, 460)
    picker:SetPoint("CENTER")
    picker:SetMovable(true)
    picker:EnableMouse(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker:SetClampedToScreen(true)
    picker.TitleText:SetText("LootPrio — valitse jaettavat")
    tinsert(UISpecialFrames, "LootPrioPicker")

    -- The link field: shift-clicking an item pastes its link into the
    -- focused edit box, so an item can come from anywhere — a bag, chat,
    -- or another player's message.
    local linkHelp = picker:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    linkHelp:SetPoint("TOPLEFT", 14, -32)
    linkHelp:SetText("Lisää item käsin: shift-klikkaa item kenttään ja paina Lisää.")

    local editBox = CreateFrame("EditBox", "LootPrioPickerInput", picker,
      "InputBoxTemplate")
    editBox:SetSize(300, 20)
    editBox:SetPoint("TOPLEFT", 18, -48)
    editBox:SetAutoFocus(false)
    picker.editBox = editBox

    local function addLink()
      local item = NS.ItemFromLink(editBox:GetText())
      if not item then
        NS.Print("kenttään ei liitetty kelvollista item-linkkiä.")
        return
      end

      manual[#manual + 1] = item
      selected["m:" .. #manual] = true
      editBox:SetText("")
      NS.RefreshPicker()
    end

    editBox:SetScript("OnEnterPressed", addLink)
    editBox:SetScript("OnEscapePressed", function(self)
      self:SetText("")
      self:ClearFocus()
    end)

    local addButton = button(picker, 80, 22, "Lisää", addLink)
    addButton:SetPoint("TOPLEFT", 326, -47)

    local scroll = makeScroll(picker, "LootPrioPickerScroll")
    scroll:SetPoint("TOPLEFT", 12, -76)
    scroll:SetPoint("BOTTOMRIGHT", -32, 56)
    picker.scroll = scroll

    picker.startButton = button(picker, 150, 24, "Aloita jako", function()
      local list = {}

      for i, item in ipairs(manual) do
        if selected["m:" .. i] then list[#list + 1] = item end
      end

      for _, item in ipairs(NS.BagItems()) do
        local key = item.bag .. ":" .. item.slot
        if selected[key] then list[#list + 1] = item end
      end

      if #list == 0 then
        NS.Print("valitse ensin vähintään yksi item.")
        return
      end

      picker:Hide()
      NS.OpenSession(list)
    end)
    picker.startButton:SetPoint("BOTTOMLEFT", 14, 14)

    local selectAll = button(picker, 100, 24, "Valitse kaikki", function()
      for i in ipairs(manual) do selected["m:" .. i] = true end
      for _, item in ipairs(NS.BagItems()) do
        selected[item.bag .. ":" .. item.slot] = true
      end
      NS.RefreshPicker()
    end)
    selectAll:SetPoint("BOTTOMLEFT", 170, 14)

    local selectNone = button(picker, 90, 24, "Tyhjennä", function()
      wipe(selected)
      wipe(manual)
      NS.RefreshPicker()
    end)
    selectNone:SetPoint("BOTTOMLEFT", 276, 14)
  end

  wipe(selected)
  wipe(manual)
  picker.editBox:SetText("")
  picker:Show()
  NS.RefreshPicker()
end

function NS.RefreshPicker()
  if not picker or not picker:IsShown() then return end

  local content = picker.scroll.content
  clear(content)
  content:SetWidth(400)

  local items = NS.BagItems()
  local y = -4
  local count = 0

  if #items == 0 and #manual == 0 then
    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    label(row, "GameFontDisableSmall", 4, 0,
      "Laukuissa ei ole jaettavia itemeitä.\n\n"
      .. "Lista näyttää puettavat itemit joiden laatu on\n"
      .. "vähintään sininen. Rajan voi muuttaa Asetuksista.\n\n"
      .. "Voit myös linkata itemin käsin yllä olevaan kenttään.")
    content:SetHeight(84)
    picker.startButton:SetText("Aloita jako")
    return
  end

  --- One row: a checkbox, the name and the demand. The same shape for a
  --- hand-linked item and one found in a bag, so the distribution does
  --- not depend on where the item came from.
  local function drawRow(key, item, manualIndex)
    if selected[key] then count = count + 1 end

    local row = addChild(content, CreateFrame("Frame", nil, content))
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(22)

    local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    checkbox:SetSize(22, 22)
    checkbox:SetPoint("TOPLEFT", 0, 2)
    checkbox:SetChecked(selected[key] and true or false)
    checkbox:SetScript("OnClick", function(self)
      selected[key] = self:GetChecked() and true or nil
      NS.RefreshPicker()
    end)

    label(row, "GameFontHighlightSmall", 28, -4,
      coloured(item.quality, item.name)
      .. (manualIndex and (" " .. DIM .. "(käsin)|r") or ""))

    local area = CreateFrame("Frame", nil, row)
    area:SetPoint("TOPLEFT", 28, -2)
    area:SetSize(textWidth(item.name) + 8, 18)
    itemTooltip(area, item.link, item.itemId)

    -- How many people present have reserved this: the officer sees at
    -- once whether there is demand or whether it goes to the vendor
    -- anyway.
    local wanted = #NS.WhoWantsPresent(item.itemId)
    if wanted > 0 then
      label(row, "GameFontHighlightSmall", 330, -4,
        GOLD .. wanted .. " prio|r")
    end

    if manualIndex then
      local b = button(row, 24, 18, "x", function()
        -- The keys are indices, so a removal shifts them. The checks have
        -- to be renumbered at the same time, or a check would end up on
        -- the wrong item.
        --
        -- false rather than nil, so table.remove gets a contiguous array:
        -- an array with holes does not keep its length reliably.
        local state, length = {}, #manual
        for i = 1, length do state[i] = selected["m:" .. i] and true or false end

        table.remove(manual, manualIndex)
        table.remove(state, manualIndex)

        for i = 1, length do selected["m:" .. i] = state[i] or nil end

        NS.RefreshPicker()
      end)
      b:SetPoint("TOPRIGHT", -4, -2)
    end

    y = y - 22
  end

  -- Hand-linked items at the top: they were just added and are therefore
  -- what gets looked at.
  for i, item in ipairs(manual) do
    drawRow("m:" .. i, item, i)
  end

  for _, item in ipairs(items) do
    drawRow(item.bag .. ":" .. item.slot, item, nil)
  end

  content:SetHeight(math.max(1, -y))
  picker.startButton:SetText(
    count > 0 and ("Aloita jako (" .. count .. ")") or "Aloita jako")
end

-- The bags can change mid-pick: the master gathers the remaining items
-- while the window is open. Without this the list would go stale.
local bagWatcher = CreateFrame("Frame")
bagWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
bagWatcher:SetScript("OnEvent", function()
  if NS.RefreshPicker then NS.RefreshPicker() end
end)

--------------------------------------------------------------------------
-- Vote window
--------------------------------------------------------------------------

--- The raider's own window: one item at a time and five buttons.
---
--- Separate from the main window because a raider's whole job is to press
--- one button. The main window's menus, lists and sorting are the
--- master's tools, and browsing them after a boss is pure friction.
---
--- The window always shows the oldest item this player has not answered,
--- and closes itself when there is nothing left to answer.
local vote

local function voteItem()
  local s = NS.session
  if not s or s.closed then return nil end

  for _, item in ipairs(NS.OpenItems()) do
    if not s.ownResponse[item.index] then return item end
  end
  return nil
end

function NS.RefreshVote()
  if not vote or not vote:IsShown() then return end

  local item = voteItem()
  if not item then
    vote:Hide()
    return
  end

  local name, quality = itemName(item)

  vote.texture:SetTexture(iconPath(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
  vote.name:SetText(coloured(quality, name))
  vote.link = item.link
  vote.itemId = item.itemId
  vote.index = item.index

  -- How many are still ahead. Without this the player cannot tell whether
  -- this is the last button or the fifth of six.
  local remaining = 0
  for _, open in ipairs(NS.OpenItems()) do
    if not NS.session.ownResponse[open.index] then remaining = remaining + 1 end
  end

  vote.status:SetText(remaining > 1
    and (DIM .. remaining .. " itemiä vastaamatta|r")
    or (DIM .. "viimeinen item|r"))

  local ownPrio = NS.InOwnProfile(item.itemId)
  for code, b in pairs(vote.buttons) do
    b:SetEnabled(code ~= "prio" or ownPrio)
  end

  vote.note:SetText(ownPrio
    and (GOLD .. "Tämä item on profiilissasi.|r")
    or (DIM .. "Ei profiilissasi — LootPrio ei käytössä.|r"))

  -- The last award, visible here too. A raider should not have to open
  -- the main window to see what came of the previous item.
  local latest
  for _, other in pairs(NS.session.items) do
    if other.awarded and (not latest or other.index > latest.index) then
      latest = other
    end
  end

  if latest then
    local latestName, latestQuality = itemName(latest)
    local response = latest.winnerCode and NS.RESPONSE[latest.winnerCode]
    local classes = NS.RaidClasses()

    vote.result:SetText(("%sViimeksi:|r %s %s→|r %s%s|r %s"):format(
      DIM,
      coloured(latestQuality, latestName),
      OK,
      classColour(classes[latest.winner]),
      latest.winner or "?",
      response and (response.colour .. response.name .. "|r") or ""))
  else
    vote.result:SetText("")
  end
end

function NS.OpenVote()
  if not voteItem() then return end

  if not vote then
    vote = CreateFrame("Frame", "LootPrioVote", UIParent,
      "BasicFrameTemplateWithInset")
    vote:SetSize(420, 196)
    vote:SetPoint("CENTER", 0, 160)
    vote:SetMovable(true)
    vote:EnableMouse(true)
    vote:RegisterForDrag("LeftButton")
    vote:SetScript("OnDragStart", vote.StartMoving)
    vote:SetScript("OnDragStop", vote.StopMovingOrSizing)
    vote:SetClampedToScreen(true)
    vote:SetFrameStrata("HIGH")
    vote.TitleText:SetText("LootPrio — vastaa")
    tinsert(UISpecialFrames, "LootPrioVote")

    local iconFrame = CreateFrame("Frame", nil, vote)
    iconFrame:SetSize(44, 44)
    iconFrame:SetPoint("TOPLEFT", 16, -34)

    vote.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    vote.texture:SetAllPoints()
    vote.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    iconFrame:EnableMouse(true)
    iconFrame:SetScript("OnEnter", function(self)
      if not vote.link and not vote.itemId then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(vote.link or ("item:" .. vote.itemId))
      GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    vote.name = vote:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    vote.name:SetPoint("TOPLEFT", 70, -38)
    vote.name:SetPoint("TOPRIGHT", -16, -38)
    vote.name:SetJustifyH("LEFT")

    vote.status = vote:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    vote.status:SetPoint("TOPLEFT", 70, -60)

    vote.note = vote:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    vote.note:SetPoint("TOPLEFT", 16, -86)
    vote.note:SetPoint("TOPRIGHT", -16, -86)
    vote.note:SetJustifyH("LEFT")

    vote.result = vote:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    vote.result:SetPoint("TOPLEFT", 16, -106)
    vote.result:SetPoint("TOPRIGHT", -16, -106)
    vote.result:SetJustifyH("LEFT")
    vote.result:SetWordWrap(false)

    -- Big buttons on one row: they are pressed during the aftermath of a
    -- fight, and a small button does not get hit.
    vote.buttons = {}
    local x = 14
    for _, response in ipairs(NS.RESPONSES) do
      local width = (response.code == "pass") and 56 or 76

      local b = button(vote, width, 28, response.name, function()
        if vote.index then NS.Respond(vote.index, response.code) end
        NS.RefreshVote()
      end)
      b:SetPoint("BOTTOMLEFT", x, 14)

      vote.buttons[response.code] = b
      x = x + width + 4
    end
  end

  vote:Show()
  NS.RefreshVote()
end

function NS.CloseVote()
  if vote then vote:Hide() end
end

--------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------

function NS.CreateMinimapButton()
  if NS.minimapButton then return end

  local b = CreateFrame("Button", "LootPrioMinimap", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", -1, 1)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  --- Places the button on the minimap's edge according to the angle.
  local function place()
    local angle = math.rad(NS.db.minimapAngle or 200)
    b:SetPoint("CENTER", Minimap, "CENTER",
      80 * math.cos(angle), 80 * math.sin(angle))
  end

  -- Dragging rotates the button around the minimap. The angle is saved,
  -- so the position survives a logout.
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      NS.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, mouseButton)
    -- A right click reopens the vote window if it was closed by accident
    -- mid-distribution. Without this an unanswered item would be lost.
    if mouseButton == "RightButton" then
      NS.OpenVote()
      return
    end

    if main and main:IsShown() then main:Hide() else NS.Open() end
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("LootPrio")
    GameTooltip:AddLine("Vasen klikkaus: avaa ikkuna", 1, 1, 1)
    GameTooltip:AddLine("Oikea klikkaus: avaa vastausikkuna", 1, 1, 1)

    if NS.session then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Jako käynnissä — jakaa "
        .. (NS.session.master or "?"), .79, .64, .15)
    end

    GameTooltip:AddLine("Raahaa: siirrä nappia", .6, .6, .6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  place()
  NS.minimapButton = b
end
