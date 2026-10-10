--[[
  LootPrio — ikkunat.

  Yksi paaikkuna, jossa vasemmalla navigointinapit ja oikealla valittu
  nakyma. Komennot ovat olemassa oikotieksi, mutta kaikki loytyy napeista -
  kukaan ei opettele konsolikomentoja kesken raidin.
]]

local ADDON, NS = ...

local LAATUVARI = {
  [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
  [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}

local KULTA = "|cffc9a227"
local HIMMEA = "|cff8b9299"
local OK = "|cff8fd17a"
local VIRHE = "|cffe08c8c"

local function varilla(laatu, teksti)
  return (LAATUVARI[laatu or 1] or "|cffffffff") .. (teksti or "?") .. "|r"
end

local paa          -- paaikkuna
local nakymat = {} -- [avain] = kehys
local navNapit = {}
local nykyinen

--------------------------------------------------------------------------
-- Apurit
--------------------------------------------------------------------------

--- Vierivä alue, johon nakymat piirtavat sisaltonsa.
local function teeVieritys(vanhempi, nimi)
  local vieritys = CreateFrame("ScrollFrame", nimi, vanhempi,
    "UIPanelScrollFrameTemplate")
  vieritys:SetPoint("TOPLEFT", 0, 0)
  vieritys:SetPoint("BOTTOMRIGHT", -26, 0)

  local sisalto = CreateFrame("Frame", nil, vieritys)
  sisalto:SetSize(1, 1)
  vieritys:SetScrollChild(sisalto)

  vieritys.sisalto = sisalto
  return vieritys
end

--- Poistaa aiemmin piirretyt alikehykset ja tekstit.
---
--- Kehyksia ei voi tuhota Luassa, joten ne piilotetaan ja kierratetaan.
--- Ilman kierratysta jokainen piirto jattaisi edellisen alleen.
local function tyhjenna(sailio)
  if sailio.lapset then
    for _, lapsi in ipairs(sailio.lapset) do
      lapsi:Hide()
      lapsi:SetParent(nil)
    end
  end
  sailio.lapset = {}
end

local function lisaaLapsi(sailio, lapsi)
  sailio.lapset = sailio.lapset or {}
  sailio.lapset[#sailio.lapset + 1] = lapsi
  return lapsi
end

local function teksti(vanhempi, fontti, x, y, sisalto)
  local fs = vanhempi:CreateFontString(nil, "ARTWORK", fontti or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(sisalto)
  return fs
end

local function nappi(vanhempi, leveys, korkeus, otsikko, toiminto)
  local b = CreateFrame("Button", nil, vanhempi, "UIPanelButtonTemplate")
  b:SetSize(leveys, korkeus)
  b:SetText(otsikko)
  b:SetScript("OnClick", toiminto)
  return b
end

--------------------------------------------------------------------------
-- Paaikkuna ja navigointi
--------------------------------------------------------------------------

local NAVI = {
  { avain = "loot",     otsikko = "Loot" },
  { avain = "jasenet",  otsikko = "Jäsenet" },
  { avain = "historia", otsikko = "Historia" },
  { avain = "tuonti",   otsikko = "Tuonti" },
  { avain = "asetukset", otsikko = "Asetukset" },
}

local function naytaNakyma(avain)
  nykyinen = avain

  for nimi, kehys in pairs(nakymat) do
    if nimi == avain then kehys:Show() else kehys:Hide() end
  end

  for nimi, b in pairs(navNapit) do
    -- Valittu nappi jaa pohjaan, jotta nakee missa on.
    if nimi == avain then b:LockHighlight() else b:UnlockHighlight() end
  end

  if NS.PaivitaNakyma then NS.PaivitaNakyma(avain) end
end

local function luoPaa()
  paa = CreateFrame("Frame", "LootPrioPaa", UIParent, "BasicFrameTemplateWithInset")
  paa:SetSize(560, 440)
  paa:SetPoint("CENTER")
  paa:SetMovable(true)
  paa:EnableMouse(true)
  paa:RegisterForDrag("LeftButton")
  paa:SetScript("OnDragStart", paa.StartMoving)
  paa:SetScript("OnDragStop", paa.StopMovingOrSizing)
  paa:SetClampedToScreen(true)
  paa:Hide()
  paa.TitleText:SetText("LootPrio")
  tinsert(UISpecialFrames, "LootPrioPaa")

  -- Navigointi vasemmalle.
  local y = -34
  for _, kohta in ipairs(NAVI) do
    local b = nappi(paa, 104, 24, kohta.otsikko, function()
      naytaNakyma(kohta.avain)
    end)
    b:SetPoint("TOPLEFT", 12, y)
    navNapit[kohta.avain] = b
    y = y - 27
  end

  -- Tilarivi alareunassa.
  paa.tila = paa:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  paa.tila:SetPoint("BOTTOMLEFT", 14, 12)
  paa.tila:SetPoint("BOTTOMRIGHT", -14, 12)
  paa.tila:SetJustifyH("LEFT")

  -- Nakymien alue oikealle.
  for _, kohta in ipairs(NAVI) do
    local kehys = CreateFrame("Frame", nil, paa)
    kehys:SetPoint("TOPLEFT", 126, -32)
    kehys:SetPoint("BOTTOMRIGHT", -12, 30)
    kehys:Hide()
    nakymat[kohta.avain] = kehys
  end
end

function NS.Avaa(nakyma)
  if not paa then luoPaa() end
  paa:Show()
  naytaNakyma(nakyma or nykyinen or "loot")
end

local function paivitaTila()
  if not paa then return end

  local kpl = 0
  for _ in pairs(NS.db.profiilit) do kpl = kpl + 1 end

  paa.tila:SetText(("%s%s|r  ·  %d jäsentä  ·  tuotu %s  ·  arvonnat: %s"):format(
    KULTA, NS.db.raidinNimi or "ei dataa", kpl, NS.db.tuotu or "—",
    NS.db.rollienNakyvyys == "raid" and "koko raidi" or "vain officerit"))
end

--------------------------------------------------------------------------
-- Näkymä: Loot
--------------------------------------------------------------------------

local function piirraLoot()
  local kehys = nakymat.loot

  if not kehys.vieritys then
    kehys.vieritys = teeVieritys(kehys, "LootPrioLootScroll")
    kehys.vieritys:SetPoint("BOTTOMRIGHT", -26, 28)

    kehys.lopeta = nappi(kehys, 120, 22, "Päätä jako", function()
      NS.PaataSessio()
    end)
    kehys.lopeta:SetPoint("BOTTOMLEFT", 0, 2)
  end

  local sisalto = kehys.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(kehys:GetWidth() - 26)

  local sessio = NS.sessio
  kehys.lopeta:SetShown(sessio ~= nil)

  if not sessio then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, -4)
    teksti(rivi, "GameFontDisableSmall", 4, 0,
      "Ei jakoa käynnissä.\n\nJako alkaa itsestään kun loottiruutu avautuu,\n"
      .. "tai kokeile Asetukset → Käynnistä testi.")
    sisalto:SetHeight(80)
    return
  end

  local y = -4

  for _, item in ipairs(sessio.itemit) do
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)

    teksti(rivi, "GameFontNormal", 4, 0,
      varilla(item.laatu, item.nimi)
      .. (item.jaettu and ("  " .. HIMMEA .. "(jaettu)|r") or ""))

    local korkeus = 20
    local vastaukset = NS.ItemienVastaukset(item)

    if #vastaukset == 0 then
      teksti(rivi, "GameFontDisableSmall", 16, -korkeus, "ei vastauksia vielä")
      korkeus = korkeus + 18
    else
      for _, v in ipairs(vastaukset) do
        local vast = NS.VASTAUS[v.koodi]

        -- Vaarin perusteltu prio merkitaan. Vastaus tulee pelaajan omalta
        -- koneelta, mutta lootmasterilla on kaikkien profiilit - joten
        -- vaite on tarkistettavissa.
        local huomio = ""
        if v.koodi == "prio" and not v.prioOk then
          huomio = VIRHE .. " (ei profiilissa!)|r"
        end

        teksti(rivi, "GameFontHighlightSmall", 16, -korkeus,
          ("%s%-10s|r %s%3s|r  %s%s"):format(
            vast.vari, vast.nimi,
            KULTA, v.luku and tostring(v.luku) or "—",
            v.nimi, huomio))

        if v.koodi ~= "pass" then
          local b = nappi(rivi, 76, 18, "Assign", function()
            NS.Jaa(item, v.nimi)
          end)
          b:SetPoint("TOPRIGHT", -8, -korkeus + 2)
          b:SetEnabled(not item.jaettu)
        end

        korkeus = korkeus + 20
      end
    end

    local puuttuu = NS.Vastaamatta(item)
    if #puuttuu > 0 then
      teksti(rivi, "GameFontDisableSmall", 16, -korkeus,
        ("odottaa: %d (%s%s)"):format(#puuttuu,
          table.concat(puuttuu, ", ", 1, math.min(4, #puuttuu)),
          #puuttuu > 4 and ", …" or ""))
      korkeus = korkeus + 16
    end

    rivi:SetHeight(korkeus + 6)
    y = y - (korkeus + 10)
  end

  sisalto:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- Näkymä: Jäsenet
--------------------------------------------------------------------------

local function piirraJasenet()
  local kehys = nakymat.jasenet
  if not kehys.vieritys then
    kehys.vieritys = teeVieritys(kehys, "LootPrioJasenScroll")
  end

  local sisalto = kehys.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(kehys:GetWidth() - 26)

  local jasenet = NS.Jasenet()
  local y = -4

  if #jasenet == 0 then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    teksti(rivi, "GameFontDisableSmall", 4, 0,
      "Ei tuotuja profiileja. Tuonti-välilehdeltä.")
    sisalto:SetHeight(30)
    return
  end

  local raidissa = NS.RaidinJasenet()

  local otsikko = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
  otsikko:SetPoint("TOPLEFT", 0, y)
  teksti(otsikko, "GameFontNormalSmall", 4, 0, "HAHMO")
  teksti(otsikko, "GameFontNormalSmall", 200, 0, "VALINNAT")
  teksti(otsikko, "GameFontNormalSmall", 280, 0, "SAATU")
  y = y - 18

  for _, j in ipairs(jasenet) do
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetHeight(16)

    -- Paikalla oleva erottuu: lootmasteria kiinnostaa kuka on nyt mukana.
    local vari = raidissa[j.nimi] and "" or HIMMEA
    teksti(rivi, "GameFontHighlightSmall", 4, 0, vari .. j.nimi .. "|r")
    teksti(rivi, "GameFontHighlightSmall", 200, 0, tostring(j.valintoja))
    teksti(rivi, "GameFontHighlightSmall", 280, 0, tostring(NS.SaatuMaara(j.nimi)))

    y = y - 16
  end

  sisalto:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- Näkymä: Historia
--------------------------------------------------------------------------

local function piirraHistoria()
  local kehys = nakymat.historia

  if not kehys.rakennettu then
    kehys.rakennettu = true

    kehys.ohje = kehys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    kehys.ohje:SetPoint("TOPLEFT", 4, -4)
    kehys.ohje:SetPoint("TOPRIGHT", -4, -4)
    kehys.ohje:SetJustifyH("LEFT")

    local vieritys = CreateFrame("ScrollFrame", "LootPrioHistScroll", kehys,
      "UIPanelScrollFrameTemplate")
    vieritys:SetPoint("TOPLEFT", 0, -40)
    vieritys:SetPoint("BOTTOMRIGHT", -26, 30)

    local kentta = CreateFrame("EditBox", nil, vieritys)
    kentta:SetMultiLine(true)
    kentta:SetFontObject(ChatFontNormal)
    kentta:SetWidth(380)
    kentta:SetAutoFocus(false)
    kentta:SetMaxLetters(0)
    kentta:SetScript("OnEscapePressed", function() paa:Hide() end)
    vieritys:SetScrollChild(kentta)
    kehys.kentta = kentta

    local vie = nappi(kehys, 150, 22, "Luo vienti sivustolle", function()
      kehys.kentta:SetText(NS.HistoriaTeksti())
      kehys.kentta:HighlightText()
      kehys.kentta:SetFocus()
      NS.Tulosta("kopioi teksti Ctrl+C ja liita sivuston ylläpitoon.")
    end)
    vie:SetPoint("BOTTOMLEFT", 0, 4)

    local tyhjennaNappi = nappi(kehys, 110, 22, "Tyhjennä", function()
      NS.db.historia = {}
      kehys.kentta:SetText("")
      NS.PaivitaNakyma("historia")
      NS.Tulosta("historia tyhjennetty.")
    end)
    tyhjennaNappi:SetPoint("BOTTOMLEFT", 156, 4)
  end

  kehys.ohje:SetText(("Jaettuja itemeitä: %s%d|r\nLuo vienti ja liitä teksti sivuston ylläpitoon."):format(
    KULTA, #NS.db.historia))
end

--------------------------------------------------------------------------
-- Näkymä: Tuonti
--------------------------------------------------------------------------

local function piirraTuonti()
  local kehys = nakymat.tuonti

  if not kehys.rakennettu then
    kehys.rakennettu = true

    local ohje = kehys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ohje:SetPoint("TOPLEFT", 4, -4)
    ohje:SetPoint("TOPRIGHT", -4, -4)
    ohje:SetJustifyH("LEFT")
    ohje:SetText("Liitä sivuston \"Vienti addoniin\" -teksti (Ctrl+V) ja paina Tuo.")

    local vieritys = CreateFrame("ScrollFrame", "LootPrioTuontiScroll", kehys,
      "UIPanelScrollFrameTemplate")
    vieritys:SetPoint("TOPLEFT", 0, -34)
    vieritys:SetPoint("BOTTOMRIGHT", -26, 30)

    local kentta = CreateFrame("EditBox", nil, vieritys)
    kentta:SetMultiLine(true)
    kentta:SetFontObject(ChatFontNormal)
    kentta:SetWidth(380)
    kentta:SetAutoFocus(false)
    kentta:SetMaxLetters(0)
    kentta:SetScript("OnEscapePressed", function() paa:Hide() end)
    vieritys:SetScrollChild(kentta)
    kehys.kentta = kentta

    kehys.tila = kehys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    kehys.tila:SetPoint("BOTTOMLEFT", 120, 10)

    local tuo = nappi(kehys, 100, 22, "Tuo", function()
      local data, virhe = NS.Tuo(kehys.kentta:GetText())
      if not data then
        kehys.tila:SetText(VIRHE .. (virhe or "Tuonti epäonnistui.") .. "|r")
        return
      end
      kehys.tila:SetText(("%s%s — %d hahmoa.|r"):format(OK, data.raidinNimi, data.hahmoja))
      kehys.kentta:SetText("")
      paivitaTila()
      naytaNakyma("jasenet")
    end)
    tuo:SetPoint("BOTTOMLEFT", 0, 4)
  end

  kehys.kentta:SetFocus()
end

--------------------------------------------------------------------------
-- Näkymä: Asetukset
--------------------------------------------------------------------------

local function piirraAsetukset()
  local kehys = nakymat.asetukset

  if not kehys.rakennettu then
    kehys.rakennettu = true

    local valinta = CreateFrame("CheckButton", "LootPrioRollitRaidille", kehys,
      "UICheckButtonTemplate")
    valinta:SetPoint("TOPLEFT", 2, -8)
    valinta:SetSize(24, 24)
    _G[valinta:GetName() .. "Text"]:SetText("Näytä arvonnat koko raidille")
    valinta:SetScript("OnClick", function(self)
      NS.db.rollienNakyvyys = self:GetChecked() and "raid" or "officers"
      if self:GetChecked() then NS.JaaRollit() end
      paivitaTila()
    end)
    kehys.valinta = valinta

    local selite = kehys:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    selite:SetPoint("TOPLEFT", 6, -36)
    selite:SetPoint("TOPRIGHT", -6, -36)
    selite:SetJustifyH("LEFT")
    selite:SetText("Pois päältä numerot jäävät officereille: raidikanavaa ei voi "
      .. "rajata osalle, joten niitä ei lähetetä lainkaan.")

    local ilmoita = CreateFrame("CheckButton", "LootPrioIlmoita", kehys,
      "UICheckButtonTemplate")
    ilmoita:SetPoint("TOPLEFT", 2, -76)
    ilmoita:SetSize(24, 24)
    _G[ilmoita:GetName() .. "Text"]:SetText("Ilmoita voittaja raidichattiin")
    ilmoita:SetScript("OnClick", function(self)
      NS.db.ilmoitaVoittaja = self:GetChecked() and true or false
    end)
    kehys.ilmoita = ilmoita

    local testi = nappi(kehys, 160, 24, "Käynnistä testi", function()
      if NS.AloitaTesti() then naytaNakyma("loot") end
    end)
    testi:SetPoint("TOPLEFT", 4, -120)

    local testiSelite = kehys:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    testiSelite:SetPoint("TOPLEFT", 6, -150)
    testiSelite:SetPoint("TOPRIGHT", -6, -150)
    testiSelite:SetJustifyH("LEFT")
    testiSelite:SetText("Tekee kolme kuviteltua loottia tuoduista valinnoista. "
      .. "Assign kirjaa historiaan mutta ei koske pelin loottiin.")

    local tyhjennaProfiilit = nappi(kehys, 160, 24, "Poista profiilit", function()
      NS.db.profiilit = {}
      NS.db.raidinNimi = nil
      NS.db.tuotu = nil
      paivitaTila()
      naytaNakyma("jasenet")
    end)
    tyhjennaProfiilit:SetPoint("TOPLEFT", 4, -196)
  end

  kehys.valinta:SetChecked(NS.db.rollienNakyvyys == "raid")
  kehys.ilmoita:SetChecked(NS.db.ilmoitaVoittaja)
end

--------------------------------------------------------------------------
-- Päivitys
--------------------------------------------------------------------------

function NS.PaivitaNakyma(avain)
  avain = avain or nykyinen
  if not paa or not paa:IsShown() then return end

  paivitaTila()

  if avain == "loot" then piirraLoot()
  elseif avain == "jasenet" then piirraJasenet()
  elseif avain == "historia" then piirraHistoria()
  elseif avain == "tuonti" then piirraTuonti()
  elseif avain == "asetukset" then piirraAsetukset()
  end
end

-- Vanhat nimet, joita muut tiedostot kutsuvat.
function NS.AvaaLootIkkuna() NS.Avaa("loot") end
function NS.AvaaTuonti() NS.Avaa("tuonti") end
function NS.PaivitaLootIkkuna() NS.PaivitaNakyma("loot") end
function NS.PaivitaAsetusUI() NS.PaivitaNakyma(nykyinen) end

--------------------------------------------------------------------------
-- Raiderin vastausikkuna
--------------------------------------------------------------------------

local vastausIkkuna

--- Itemin nimi ja laatu id:n perusteella.
---
--- Peli ei valttamatta tunne itemia heti: tiedot saapuvat omana
--- tapahtumanaan, jolloin ikkuna piirretaan uudelleen.
local function itemTiedot(itemId)
  local nimi, _, laatu = GetItemInfo(itemId)
  return nimi or ("item " .. itemId), laatu or 1
end

function NS.AvaaVastausIkkuna()
  if not NS.omaSessio then return end

  if not vastausIkkuna then
    vastausIkkuna = CreateFrame("Frame", "LootPrioVastaus", UIParent,
      "BasicFrameTemplateWithInset")
    vastausIkkuna:SetSize(430, 330)
    vastausIkkuna:SetPoint("CENTER", 0, 120)
    vastausIkkuna:SetMovable(true)
    vastausIkkuna:EnableMouse(true)
    vastausIkkuna:RegisterForDrag("LeftButton")
    vastausIkkuna:SetScript("OnDragStart", vastausIkkuna.StartMoving)
    vastausIkkuna:SetScript("OnDragStop", vastausIkkuna.StopMovingOrSizing)
    vastausIkkuna:SetClampedToScreen(true)
    vastausIkkuna.TitleText:SetText("LootPrio — vastaa")
    tinsert(UISpecialFrames, "LootPrioVastaus")

    local vieritys = teeVieritys(vastausIkkuna, "LootPrioVastausScroll")
    vieritys:SetPoint("TOPLEFT", 12, -32)
    vieritys:SetPoint("BOTTOMRIGHT", -32, 12)
    vastausIkkuna.vieritys = vieritys
  end

  vastausIkkuna:Show()
  NS.PaivitaVastausIkkuna()
end

function NS.SuljeVastausIkkuna()
  if vastausIkkuna then vastausIkkuna:Hide() end
end

function NS.PaivitaVastausIkkuna()
  if not vastausIkkuna or not vastausIkkuna:IsShown() then return end
  if not NS.omaSessio then return end

  local sisalto = vastausIkkuna.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(370)

  local y = -4
  local indeksit = {}
  for indeksi in pairs(NS.omaSessio.itemit) do indeksit[#indeksit + 1] = indeksi end
  table.sort(indeksit)

  for _, indeksi in ipairs(indeksit) do
    local item = NS.omaSessio.itemit[indeksi]
    local nimi, laatu = itemTiedot(item.itemId)

    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)

    teksti(rivi, "GameFontNormal", 4, 0, varilla(laatu, nimi))

    local valittu = NS.omaSessio.vastattu[indeksi]
    local x = 4

    for _, v in ipairs(NS.VASTAUKSET) do
      -- LootPrio vain jos item on oikeasti omassa profiilissa. Sivusto on
      -- se joka ratkaisee, ei pelaajan oma arvio.
      local sallittu = (v.koodi ~= "prio") or NS.OmassaProfiilissa(item.itemId)

      local b = nappi(rivi, v.koodi == "pass" and 54 or 72, 20, v.nimi, function()
        NS.Vastaa(indeksi, v.koodi)
      end)
      b:SetPoint("TOPLEFT", x, -22)
      b:SetEnabled(sallittu and not valittu)

      if valittu == v.koodi then b:LockHighlight() end

      if not sallittu then
        b:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_TOP")
          GameTooltip:AddLine("Tämä item ei ole profiilissasi sivustolla.", 1, .6, .6)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end

      x = x + (v.koodi == "pass" and 58 or 76)
    end

    if valittu then
      teksti(rivi, "GameFontDisableSmall", 4, -46,
        "Vastattu: " .. (NS.VASTAUS[valittu] and NS.VASTAUS[valittu].nimi or valittu))
      rivi:SetHeight(66)
      y = y - 70
    else
      rivi:SetHeight(48)
      y = y - 52
    end
  end

  sisalto:SetHeight(math.max(1, -y))
end

-- Itemin tiedot voivat saapua vasta ikkunan avaamisen jalkeen.
local itemKehys = CreateFrame("Frame")
itemKehys:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemKehys:SetScript("OnEvent", function()
  if NS.PaivitaVastausIkkuna then NS.PaivitaVastausIkkuna() end
end)

--------------------------------------------------------------------------
-- Minimap-nappi
--------------------------------------------------------------------------

function NS.LuoMinimapNappi()
  if NS.minimapNappi then return end

  local b = CreateFrame("Button", "LootPrioMinimap", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)

  local ikoni = b:CreateTexture(nil, "BACKGROUND")
  ikoni:SetSize(20, 20)
  ikoni:SetPoint("CENTER", -1, 1)
  ikoni:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  ikoni:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local kehys = b:CreateTexture(nil, "OVERLAY")
  kehys:SetSize(53, 53)
  kehys:SetPoint("TOPLEFT")
  kehys:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  --- Asettaa napin minimapin kehalle kulman mukaan.
  local function asetaPaikka()
    local kulma = math.rad(NS.db.minimapKulma or 200)
    b:SetPoint("CENTER", Minimap, "CENTER",
      80 * math.cos(kulma), 80 * math.sin(kulma))
  end

  -- Raahaus kiertaa nappia minimapin ympari. Kulma talletetaan, joten
  -- paikka sailyy myos uloskirjautumisen yli.
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local skaala = Minimap:GetEffectiveScale()
      px, py = px / skaala, py / skaala
      NS.db.minimapKulma = math.deg(math.atan2(py - my, px - mx))
      asetaPaikka()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  b:SetScript("OnClick", function()
    if paa and paa:IsShown() then paa:Hide() else NS.Avaa() end
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("LootPrio")
    GameTooltip:AddLine("Vasen klikkaus: avaa ikkuna", 1, 1, 1)
    GameTooltip:AddLine("Raahaa: siirrä nappia", .6, .6, .6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  asetaPaikka()
  NS.minimapNappi = b
end

--------------------------------------------------------------------------
-- Muilta saadut arvonnat
--------------------------------------------------------------------------

function NS.NaytaSaadutRollit(itemId, rivitLista)
  local nimi = GetItemInfo(itemId) or ("item " .. itemId)

  local osat = {}
  for _, r in ipairs(rivitLista) do
    osat[#osat + 1] = ("%s %d"):format(r.nimi, r.luku)
  end

  NS.Tulosta(("%s — %s"):format(nimi, table.concat(osat, ", ")))
end
