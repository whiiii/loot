--[[
  LootPrio — ikkunat.

  Kaksi ikkunaa: tuonti ja loottilista. Kumpikin tehdaan pelin omista
  malleista, jotta ne nayttavat pelilta eivatka irralliselta laatikolta.
]]

local ADDON, NS = ...

local LAATUVARI = {
  [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
  [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}

local function varilla(laatu, teksti)
  return (LAATUVARI[laatu or 1] or "|cffffffff") .. (teksti or "?") .. "|r"
end

--- Peruskehys otsikolla, suljettavissa ja siirrettavissa.
local function teeIkkuna(nimi, leveys, korkeus, otsikko)
  local f = CreateFrame("Frame", nimi, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(leveys, korkeus)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()

  f.TitleText:SetText(otsikko)
  tinsert(UISpecialFrames, nimi)  -- Escape sulkee
  return f
end

-- Tuonti-ikkuna ------------------------------------------------------------

local tuonti

function NS.AvaaTuonti()
  if not tuonti then
    tuonti = teeIkkuna("LootPrioTuonti", 560, 380, "LootPrio — tuonti")

    local ohje = tuonti:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ohje:SetPoint("TOPLEFT", 16, -32)
    ohje:SetPoint("TOPRIGHT", -16, -32)
    ohje:SetJustifyH("LEFT")
    ohje:SetText("Liita sivustolta kopioitu teksti (Ctrl+V) ja paina Tuo.")

    local vieritys = CreateFrame("ScrollFrame", "LootPrioTuontiScroll", tuonti,
      "UIPanelScrollFrameTemplate")
    vieritys:SetPoint("TOPLEFT", 16, -56)
    vieritys:SetPoint("BOTTOMRIGHT", -36, 52)

    local kentta = CreateFrame("EditBox", nil, vieritys)
    kentta:SetMultiLine(true)
    kentta:SetFontObject(ChatFontNormal)
    kentta:SetWidth(480)
    kentta:SetAutoFocus(false)
    -- Rajaton pituus: koko killan profiilit voivat olla tuhansia merkkeja.
    kentta:SetMaxLetters(0)
    kentta:SetScript("OnEscapePressed", function() tuonti:Hide() end)
    vieritys:SetScrollChild(kentta)
    tuonti.kentta = kentta

    local tila = tuonti:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    tila:SetPoint("BOTTOMLEFT", 16, 20)
    tuonti.tila = tila

    local nappi = CreateFrame("Button", nil, tuonti, "UIPanelButtonTemplate")
    nappi:SetSize(90, 22)
    nappi:SetPoint("BOTTOMRIGHT", -16, 16)
    nappi:SetText("Tuo")
    nappi:SetScript("OnClick", function()
      local data, virhe = NS.Tuo(kentta:GetText())
      if not data then
        tila:SetText("|cffe08c8c" .. (virhe or "Tuonti epaonnistui.") .. "|r")
        return
      end
      tila:SetText(("|cff8fd17a%s — %d hahmoa tuotu.|r"):format(
        data.raidinNimi, data.hahmoja))
      kentta:SetText("")
    end)
  end

  tuonti:Show()
  tuonti.tila:SetText("")
  tuonti.kentta:SetText("")
  tuonti.kentta:SetFocus()
end

-- Loottilista --------------------------------------------------------------

local loottiIkkuna
local rivit = {}

local function tyhjennaRivit()
  for _, r in ipairs(rivit) do r:Hide() end
end

--- Yksi loottirivi: item, halukkaat numeroineen ja jakonappi.
local function piirraLoot(vanhempi, loot, y)
  local rivi = CreateFrame("Frame", nil, vanhempi)
  rivi:SetPoint("TOPLEFT", 0, y)
  rivi:SetPoint("TOPRIGHT", 0, y)

  local otsikko = rivi:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  otsikko:SetPoint("TOPLEFT", 4, 0)
  otsikko:SetText(varilla(loot.laatu, loot.nimi)
    .. (loot.jaettu and "  |cff8b9299(jaettu)|r" or ""))

  local korkeus = 20

  if #loot.rollit == 0 then
    local tyhja = rivi:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tyhja:SetPoint("TOPLEFT", 16, -korkeus)
    tyhja:SetText("ei kenenkaan profiilissa")
    korkeus = korkeus + 16
  else
    for _, r in ipairs(loot.rollit) do
      local teksti = rivi:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      teksti:SetPoint("TOPLEFT", 16, -korkeus)
      teksti:SetText(("|cffc9a227%3d|r  %s  |cff8b9299%s|r"):format(
        r.luku, r.nimi, r.paikka))

      local nappi = CreateFrame("Button", nil, rivi, "UIPanelButtonTemplate")
      nappi:SetSize(80, 18)
      nappi:SetPoint("TOPRIGHT", -8, -korkeus + 2)
      nappi:SetText("Assign")
      nappi:SetEnabled(not loot.jaettu)
      -- Jako tehdaan nimenomaan napin painalluksesta: peli vaatii
      -- laitteistotapahtuman eika hyvaksy kutsua muualta.
      nappi:SetScript("OnClick", function()
        if NS.Jaa(loot, r.nimi) then NS.PaivitaLootIkkuna() end
      end)

      korkeus = korkeus + 20
    end
  end

  rivi:SetHeight(korkeus + 8)
  rivit[#rivit + 1] = rivi
  return korkeus + 8
end

function NS.PaivitaLootIkkuna()
  if not loottiIkkuna or not loottiIkkuna:IsShown() then return end

  tyhjennaRivit()
  wipe(rivit)

  local sisalto = loottiIkkuna.sisalto
  local y = 0

  for _, loot in ipairs(NS.istunto.lootit) do
    y = y - piirraLoot(sisalto, loot, y)
  end

  sisalto:SetHeight(math.max(1, -y))
  loottiIkkuna.tila:SetText(("%s · arvonnat: %s"):format(
    NS.db.raidinNimi or "ei dataa",
    NS.db.rollienNakyvyys == "raid" and "koko raidi" or "vain officerit"))
end

function NS.AvaaLootIkkuna()
  if not loottiIkkuna then
    loottiIkkuna = teeIkkuna("LootPrioLootti", 460, 400, "LootPrio — loot")

    local vieritys = CreateFrame("ScrollFrame", "LootPrioLoottiScroll",
      loottiIkkuna, "UIPanelScrollFrameTemplate")
    vieritys:SetPoint("TOPLEFT", 12, -32)
    vieritys:SetPoint("BOTTOMRIGHT", -32, 56)

    local sisalto = CreateFrame("Frame", nil, vieritys)
    sisalto:SetSize(400, 1)
    vieritys:SetScrollChild(sisalto)
    loottiIkkuna.sisalto = sisalto

    local tila = loottiIkkuna:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    tila:SetPoint("BOTTOMLEFT", 16, 34)
    loottiIkkuna.tila = tila

    -- Nakyvyyden valinta suoraan ikkunassa: sita vaihdetaan kesken raidin,
    -- eika komentoa muisteta silloin.
    local valinta = CreateFrame("CheckButton", "LootPrioRollitRaidille",
      loottiIkkuna, "UICheckButtonTemplate")
    valinta:SetPoint("BOTTOMLEFT", 14, 10)
    valinta:SetSize(22, 22)
    _G[valinta:GetName() .. "Text"]:SetText("Nayta arvonnat koko raidille")
    valinta:SetScript("OnClick", function(self)
      NS.db.rollienNakyvyys = self:GetChecked() and "raid" or "officers"
      if self:GetChecked() then NS.JaaRollit() end
      NS.PaivitaLootIkkuna()
    end)
    loottiIkkuna.valinta = valinta
  end

  loottiIkkuna.valinta:SetChecked(NS.db.rollienNakyvyys == "raid")
  loottiIkkuna:Show()
  NS.PaivitaLootIkkuna()
end

function NS.PaivitaAsetusUI()
  if loottiIkkuna and loottiIkkuna.valinta then
    loottiIkkuna.valinta:SetChecked(NS.db.rollienNakyvyys == "raid")
  end
end

--- Lootmasterin lahettamat arvonnat muille raidilaisille.
function NS.NaytaSaadutRollit(itemId, rivitLista, lahettaja)
  local nimi = GetItemInfo(itemId) or ("item " .. itemId)

  local osat = {}
  for _, r in ipairs(rivitLista) do
    osat[#osat + 1] = ("%s %d"):format(r.nimi, r.luku)
  end

  NS.Tulosta(("%s — %s"):format(nimi, table.concat(osat, ", ")))
end
