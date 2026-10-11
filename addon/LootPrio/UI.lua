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

--- Pelaajan nimi luokan varissa.
---
--- Luokkavari on nopein tapa erottaa nimet toisistaan: raidissa on 40
--- nimea, ja pelkka valkoinen lista vaatii lukemista jokaisen kohdalla.
local function pelaajanVari(tiedosto)
  local c = tiedosto and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tiedosto]
  if not c then return "|cffffffff" end
  return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

--- Itemin kuvake. Pelin oma tietokanta tuntee sen vaikka itemia ei olisi
--- nahty: numero riittaa.
local function ikoni(item)
  if item.ikoni then return item.ikoni end
  if item.itemId and GetItemIcon then return GetItemIcon(item.itemId) end
  return nil
end

--- Kuvakeruutu laatureunuksella.
local function teeIkoni(vanhempi, koko, item)
  local kehys = CreateFrame("Frame", nil, vanhempi)
  kehys:SetSize(koko, koko)

  local kuva = kehys:CreateTexture(nil, "ARTWORK")
  kuva:SetAllPoints()
  kuva:SetTexture(ikoni(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
  -- Reunat pois: pelin kuvakkeissa on tyhjaa reunaa, joka tekee listasta
  -- levottoman nakoisen.
  kuva:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local reunus = kehys:CreateTexture(nil, "OVERLAY")
  reunus:SetAllPoints()
  reunus:SetColorTexture(0, 0, 0, 0)

  local vari = LAATUVARI[item.laatu or 1]
  if vari then
    local r = tonumber(vari:sub(5, 6), 16) / 255
    local g = tonumber(vari:sub(7, 8), 16) / 255
    local b = tonumber(vari:sub(9, 10), 16) / 255
    kehys.reuna = CreateFrame("Frame", nil, kehys, "BackdropTemplate")
    kehys.reuna:SetPoint("TOPLEFT", -1, 1)
    kehys.reuna:SetPoint("BOTTOMRIGHT", 1, -1)
    if kehys.reuna.SetBackdrop then
      kehys.reuna:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
      })
      kehys.reuna:SetBackdropBorderColor(r, g, b, 1)
    end
  end

  return kehys
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

--- Liittaa pelin item-tooltipin kehykseen.
---
--- Raidin keskella kukaan ei muista ulkoa mita "Wristguards of True Flight"
--- on, eika laukun avaaminen kesken jaon ole vaihtoehto.
local function itemTooltip(kehys, linkki, itemId)
  if not linkki and not itemId then return kehys end

  kehys:EnableMouse(true)
  kehys:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    if linkki then
      GameTooltip:SetHyperlink(linkki)
    else
      GameTooltip:SetHyperlink("item:" .. itemId)
    end

    GameTooltip:Show()
  end)
  kehys:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return kehys
end

--- Mitta tekstille, jotta tooltipin hiirialue ei ulotu tyhjaan tilaan.
local mitta
local function tekstinLeveys(sisalto, fontti)
  if not mitta then
    mitta = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mitta:Hide()
  end

  mitta:SetFontObject(_G[fontti or "GameFontHighlightSmall"])
  mitta:SetText(sisalto or "")
  return mitta:GetStringWidth()
end

--- Hiirialue nimen kohdalle rivin alkuun.
---
--- Vain nimen levyinen eika koko rivi: koko rivin alue avaisi tooltipin
--- aina kun kursori kulkee listan yli, ja peittaisi rivin napit.
local function nimiAlue(rivi, nimi, itemId, linkki, fontti)
  local alue = CreateFrame("Frame", nil, rivi)
  alue:SetPoint("TOPLEFT", 4, 0)
  alue:SetSize(tekstinLeveys(nimi, fontti) + 8, rivi:GetHeight())
  return itemTooltip(alue, linkki, itemId)
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
  { avain = "kauppa",   otsikko = "Kauppa" },
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
  paa:SetSize(660, 500)
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

  -- Luovuttamatta olevien maara navinappiin: se on tehtavalista, ja
  -- tekematta jaanyt kauppa ei saa jaada valilehden taakse huomaamatta.
  if navNapit.kauppa then
    local odottaa = NS.OdottavatKaupat and #NS.OdottavatKaupat() or 0
    navNapit.kauppa:SetText(odottaa > 0 and ("Kauppa (" .. odottaa .. ")") or "Kauppa")
  end
end

--------------------------------------------------------------------------
-- Näkymä: Loot
--------------------------------------------------------------------------

--- Itemin nimi ja laatu. Lootmasterilla ne tulevat loottiruudusta, muilla
--- pelin omasta tietokannasta - joka ei valttamatta tunne itemia heti.
local function itemNimi(item)
  if item.nimi then return item.nimi, item.laatu or 1 end
  local nimi, _, laatu = GetItemInfo(item.itemId)
  return nimi or ("item " .. item.itemId), laatu or 1
end

--- Tamanhetkisen jaon tulokset: kuka sai ja milla napilla.
---
--- Tama on se mika raiderille nakyy. Han ei nae ketka vastasivat mita
--- aanestyksen aikana, mutta lopputulos ja sen peruste ovat avoimia -
--- muuten lootmasterin paatosta ei voisi seurata lainkaan.
---
--- Officerille sama lista on yhteenveto illan kulusta vastauslistan alla.
local function piirraJaetut(sisalto, y)
  local sessio = NS.sessio
  if not sessio then return y end

  local jaetut = {}
  for _, item in pairs(sessio.itemit) do
    if item.jaettu then jaetut[#jaetut + 1] = item end
  end
  if #jaetut == 0 then return y end

  table.sort(jaetut, function(a, b) return a.indeksi < b.indeksi end)

  local otsikko = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
  otsikko:SetPoint("TOPLEFT", 0, y - 8)
  otsikko:SetPoint("TOPRIGHT", 0, y - 8)
  otsikko:SetHeight(18)
  teksti(otsikko, "GameFontNormalSmall", 8, 0, "JAETUT")
  y = y - 28

  local luokat = NS.RaidinLuokat()

  for _, item in ipairs(jaetut) do
    local nimi, laatu = itemNimi(item)

    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)
    rivi:SetHeight(22)

    local kuvake = teeIkoni(rivi, 18, item)
    kuvake:SetPoint("TOPLEFT", 8, -2)
    itemTooltip(kuvake, item.linkki, item.itemId)

    local lyhyt = nimi:len() > 24 and (nimi:sub(1, 23) .. "…") or nimi
    teksti(rivi, "GameFontHighlightSmall", 32, -4, varilla(laatu, lyhyt))

    teksti(rivi, "GameFontHighlightSmall", 210, -4,
      OK .. "→|r " .. pelaajanVari(luokat[item.saaja])
        .. (item.saaja or "?") .. "|r")

    -- Milla napilla: ilman perustetta lista kertoisi vain lopputuloksen,
    -- ei sita miksi se on se.
    local vast = item.saajanKoodi and NS.VASTAUS[item.saajanKoodi]
    teksti(rivi, "GameFontHighlightSmall", 340, -4,
      vast and (vast.vari .. vast.nimi .. "|r") or (HIMMEA .. "—|r"))

    y = y - 22
  end

  return y
end

local function piirraLoot()
  local kehys = nakymat.loot

  if not kehys.rakennettu then
    kehys.rakennettu = true

    kehys.valilehdet = CreateFrame("Frame", nil, kehys)
    kehys.valilehdet:SetPoint("TOPLEFT", 0, 0)
    kehys.valilehdet:SetPoint("TOPRIGHT", 0, 0)
    kehys.valilehdet:SetHeight(36)

    kehys.vieritys = teeVieritys(kehys, "LootPrioLootScroll")
    kehys.vieritys:SetPoint("TOPLEFT", 0, -42)
    kehys.vieritys:SetPoint("BOTTOMRIGHT", -26, 28)

    kehys.napit = CreateFrame("Frame", nil, kehys)
    kehys.napit:SetPoint("BOTTOMLEFT", 0, 0)
    kehys.napit:SetPoint("BOTTOMRIGHT", 0, 0)
    kehys.napit:SetHeight(26)

    kehys.lopeta = nappi(kehys.napit, 110, 22, "Päätä jako", function()
      -- Yhteenveto raidichattiin: se poistaa riidat ennen kuin niita on.
      NS.PaataSessio(true)
    end)
    kehys.lopeta:SetPoint("BOTTOMLEFT", 0, 0)

    kehys.sulje = nappi(kehys.napit, 130, 22, "Sulje vastaukset", function()
      NS.SuljeVastaukset()
    end)
    kehys.sulje:SetPoint("BOTTOMLEFT", 114, 0)

    kehys.peru = nappi(kehys.napit, 100, 22, "Peru jako", function()
      NS.PeruJako()
    end)
    kehys.peru:SetPoint("BOTTOMLEFT", 248, 0)

    -- Lootmaster voi pudota linjoilta kesken jaon. Ilman tata koko raidi
    -- jaisi odottamaan hanen paluutaan.
    kehys.haltuun = nappi(kehys.napit, 150, 22, "Ota jako haltuun", function()
      NS.OtaHaltuun()
    end)
    kehys.haltuun:SetPoint("BOTTOMLEFT", 352, 0)

    -- Kulunut aika oikeaan reunaan. Mikaan ei pakota lopettamaan, mutta
    -- jostain on nahtava milloin odottaminen ei enaa tuota vastauksia.
    kehys.kello = kehys.napit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    kehys.kello:SetPoint("BOTTOMRIGHT", -4, 4)

    kehys.napit:SetScript("OnUpdate", function(self, kulunut)
      self.viive = (self.viive or 0) + kulunut
      if self.viive < 1 then return end
      self.viive = 0

      if not NS.sessio then
        kehys.kello:SetText("")
        return
      end

      local s = NS.SessionKesto()
      local raja = NS.db.vastausAika or 90
      local vari = (s > raja and not NS.sessio.suljettu) and VIRHE or HIMMEA

      kehys.kello:SetText(("%s%d:%02d%s"):format(
        vari, math.floor(s / 60), s % 60,
        NS.sessio.suljettu and "  suljettu|r" or "|r"))
    end)
  end

  tyhjenna(kehys.valilehdet)
  tyhjenna(kehys.napit)

  local sisalto = kehys.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(kehys:GetWidth() - 26)

  local sessio = NS.sessio
  local officer = NS.OnOfficer()

  -- Jakonapit vain sille joka jakaa. Officerin napit nakyivat aiemmin
  -- kaikille apulaisille, jolloin kaksi officeria saattoi painaa samaa
  -- itemia eri suuntiin.
  local jakaja = sessio ~= nil and sessio.lootmaster == NS.OmaNimi()

  kehys.lopeta:SetShown(jakaja)
  kehys.sulje:SetShown(jakaja and not sessio.suljettu)
  kehys.peru:SetShown(jakaja and sessio.viimeisin ~= nil)

  -- Haltuunotto vain johtajalle ja vain jos joku muu jakaa.
  kehys.haltuun:SetShown(
    sessio ~= nil and not jakaja and NS.OnJohtaja() and not sessio.testi)

  if not sessio then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, -4)
    rivi:SetPoint("TOPRIGHT", 0, -4)
    rivi:SetHeight(90)

    if officer then
      teksti(rivi, "GameFontDisableSmall", 4, 0,
        "Ei jakoa käynnissä.\n\nKerää lootit laukkuihisi ja paina Jaa lootit.\n"
        .. "Jaon avaaja on sen illan lootmaster.")

      local b = nappi(rivi, 130, 24, "Jaa lootit", function()
        NS.AvaaValinta()
      end)
      b:SetPoint("TOPLEFT", 4, -56)
    else
      teksti(rivi, "GameFontDisableSmall", 4, 0,
        "Ei jakoa käynnissä.\n\nVastausikkuna aukeaa itsestään kun\n"
        .. "lootmaster laittaa lootit jakoon.")
    end

    sisalto:SetHeight(96)
    return
  end

  -- Välilehdet vain jakamattomista: jaettu item katoaa listasta ja jää
  -- historiaan, joten jäljellä on aina se mikä on vielä päättämättä.
  local avoimet = NS.AvoimetItemit()

  if #avoimet == 0 then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, -4)
    rivi:SetHeight(40)
    teksti(rivi, "GameFontNormal", 4, 0, OK .. "Kaikki jaettu.|r")
    teksti(rivi, "GameFontDisableSmall", 4, -20,
      "Tulokset jäävät Historia-välilehdelle.")

    -- Tulokset nakyviin myos tassa: ilman niita viimeisen itemin jalkeen
    -- jaisi tyhja ruutu juuri silloin kun kaikkia kiinnostaa mita meni
    -- kenellekin.
    local y = piirraJaetut(sisalto, -44)
    sisalto:SetHeight(math.max(1, -y))
    return
  end

  if not sessio.valittu or not sessio.itemit[sessio.valittu]
     or sessio.itemit[sessio.valittu].jaettu then
    sessio.valittu = avoimet[1].indeksi
  end

  -- Valilehdet kuvakkeina eika nimina. Kuusi itemia ei mahdu nimina
  -- riville ilman etta nimet katkaistaan kolmeentoista merkkiin, ja
  -- katkaistu nimi on huonompi tunnistettava kuin kuvake.
  local x = 0
  for _, item in ipairs(avoimet) do
    local nimi, laatu = itemNimi(item)

    local b = CreateFrame("Button", nil, kehys.valilehdet)
    b:SetSize(34, 34)
    b:SetPoint("TOPLEFT", x, 0)

    local kuva = b:CreateTexture(nil, "ARTWORK")
    kuva:SetAllPoints()
    kuva:SetTexture(ikoni(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
    kuva:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Valittu erottuu kirkkaana, muut himmennettyina. Pelkka reunus ei
    -- erotu tarpeeksi kun kuvakkeet ovat vierekkain.
    if sessio.valittu == item.indeksi then
      local kehystys = b:CreateTexture(nil, "OVERLAY")
      kehystys:SetPoint("TOPLEFT", -2, 2)
      kehystys:SetPoint("BOTTOMRIGHT", 2, -2)
      kehystys:SetColorTexture(0.79, 0.64, 0.15, 0.85)
      kehystys:SetDrawLayer("BACKGROUND")
    else
      kuva:SetVertexColor(0.45, 0.45, 0.45)
    end

    -- Vastanneiden maara kuvakkeen kulmaan: siita nakee yhdella
    -- silmayksella mika item odottaa viela vastauksia.
    --
    -- Vain niille jotka saavat nahda vastaukset. Luku ei kerro kuka
    -- vastasi mita, mutta se on silti tietoa aanestyksen kulusta - ja
    -- raiderin kuuluu nahda vasta lopputulos.
    if NS.NaytaKaikkiVastaukset() then
      local vastanneet = 0
      for _ in pairs(item.vastaukset) do vastanneet = vastanneet + 1 end

      local luku = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      luku:SetPoint("BOTTOMRIGHT", -1, 1)
      luku:SetText(vastanneet > 0 and tostring(vastanneet) or "")
    end

    b:SetScript("OnClick", function()
      sessio.valittu = item.indeksi
      NS.PaivitaNakyma("loot")
    end)

    itemTooltip(b, item.linkki, item.itemId)
    lisaaLapsi(kehys.valilehdet, b)

    x = x + 38
  end

  local item = sessio.itemit[sessio.valittu]
  if not item then return end

  local nimi, laatu = itemNimi(item)
  local y = -4

  -- Otsikkorivi: kuvake, nimi ja kuka jakaa. Lootmasterin nimi on tassa
  -- siksi, etta jokaisen pitaa nahda kenen paatosta odotetaan.
  local otsikko = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
  otsikko:SetPoint("TOPLEFT", 0, y)
  otsikko:SetPoint("TOPRIGHT", 0, y)
  otsikko:SetHeight(38)

  local kuvake = teeIkoni(otsikko, 32, item)
  kuvake:SetPoint("TOPLEFT", 4, -2)
  itemTooltip(kuvake, item.linkki, item.itemId)

  teksti(otsikko, "GameFontNormal", 42, -2,
    varilla(laatu, nimi)
    .. (item.jaettu and ("  " .. OK .. "→ " .. (item.saaja or "?") .. "|r") or ""))

  local lm = sessio.lootmaster or "?"
  teksti(otsikko, "GameFontDisableSmall", 42, -20,
    ("jakaa: %s%s|r%s"):format(
      NS.Paikalla(lm) and HIMMEA or VIRHE, lm,
      NS.Paikalla(lm) and "" or (VIRHE .. " (poissa)|r")))

  y = y - 42

  -- Omat vastausnapit, jos itemia ei ole viela jaettu.
  if not item.jaettu then
    local napit = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    napit:SetPoint("TOPLEFT", 0, y)
    napit:SetPoint("TOPRIGHT", 0, y)
    napit:SetHeight(24)

    local valittu = sessio.omaVastaus[item.indeksi]
    local nx = 4

    for _, v in ipairs(NS.VASTAUKSET) do
      -- LootPrio vain jos item on oikeasti omassa profiilissa. Sivusto on
      -- se joka ratkaisee, ei pelaajan oma arvio.
      local sallittu = (v.koodi ~= "prio") or NS.OmassaProfiilissa(item.itemId)
      local leveys = (v.koodi == "pass") and 50 or 68

      local b = nappi(napit, leveys, 20, v.nimi, function()
        NS.Vastaa(item.indeksi, v.koodi)
      end)
      b:SetPoint("TOPLEFT", nx, 0)
      b:SetEnabled(sallittu and not valittu and not sessio.suljettu)
      if valittu == v.koodi then b:LockHighlight() end

      nx = nx + leveys + 4
    end

    y = y - 28

    -- Syy harmaalle napille nakyviin. Ilman tata pelaaja ei tieda onko
    -- kyse suljetusta jaosta, puuttuvasta profiilista vai omasta
    -- vastauksesta joka jo meni lapi.
    if sessio.suljettu or not NS.OmassaProfiilissa(item.itemId) then
      local syy = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
      syy:SetPoint("TOPLEFT", 0, y)
      syy:SetHeight(14)
      teksti(syy, "GameFontDisableSmall", 8, 0,
        sessio.suljettu and "vastaukset suljettu"
          or "LootPrio ei käytössä: item ei ole profiilissasi")
      y = y - 16
    end
  end

  -- Vastaukset. Lootmasterin asetuksesta riippuu naytetaanko kaikkien
  -- vastaukset vai vain oma.
  local kaikki = NS.NaytaKaikkiVastaukset()
  local vastaukset = NS.ItemienVastaukset(item)

  if not kaikki then
    local omat = {}
    for _, v in ipairs(vastaukset) do
      if v.nimi == NS.OmaNimi() then omat[#omat + 1] = v end
    end
    vastaukset = omat
  end

  if #vastaukset == 0 then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetHeight(18)
    teksti(rivi, "GameFontDisableSmall", 8, 0, "ei vastauksia vielä")
    y = y - 20
  else
    -- Otsikoista voi lajitella. Oletus on peruste, koska se ratkaisee -
    -- mutta saadut itemit tai arvonta voivat olla se mita haetaan.
    local otsikot = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    otsikot:SetPoint("TOPLEFT", 0, y)
    otsikot:SetPoint("TOPRIGHT", 0, y)
    otsikot:SetHeight(18)

    local SARAKKEET = {
      { avain = "jarjestys", otsikko = "VASTAUS", x = 8 },
      { avain = "luku",      otsikko = "ROLL",    x = 92 },
      { avain = "nimi",      otsikko = "PELAAJA", x = 130 },
      { avain = "saatu",     otsikko = "SAATU",   x = 250 },
    }

    for _, s in ipairs(SARAKKEET) do
      local merkki = ""
      if NS.lajittelu == s.avain then
        merkki = NS.lajitteluNouseva and " ▲" or " ▼"
      end

      local b = CreateFrame("Button", nil, otsikot)
      b:SetSize(76, 16)
      b:SetPoint("TOPLEFT", s.x - 4, 0)

      local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      fs:SetPoint("LEFT", 4, 0)
      fs:SetText(s.otsikko .. merkki)

      b:SetScript("OnClick", function()
        if NS.lajittelu == s.avain then
          NS.lajitteluNouseva = not NS.lajitteluNouseva
        else
          NS.lajittelu = s.avain
          NS.lajitteluNouseva = (s.avain == "jarjestys" or s.avain == "nimi")
        end
        NS.PaivitaNakyma("loot")
      end)
    end

    y = y - 18

    local luokat = NS.RaidinLuokat()
    local pariton = false

    for _, v in ipairs(vastaukset) do
      local vast = NS.VASTAUS[v.koodi]

      local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
      rivi:SetPoint("TOPLEFT", 0, y)
      rivi:SetPoint("TOPRIGHT", 0, y)
      rivi:SetHeight(20)

      -- Joka toinen rivi tummempi. Nelikymmenen nimen listassa silma
      -- hukkaa rivin ilman sita.
      pariton = not pariton
      if pariton then
        local tausta = rivi:CreateTexture(nil, "BACKGROUND")
        tausta:SetAllPoints()
        tausta:SetColorTexture(1, 1, 1, 0.03)
      end

      teksti(rivi, "GameFontHighlightSmall", 8, -3, vast.vari .. vast.nimi .. "|r")
      teksti(rivi, "GameFontHighlightSmall", 92, -3,
        KULTA .. (v.luku and tostring(v.luku) or "—") .. "|r")

      -- Vaarin perusteltu prio merkitaan. Tarkistus tehdaan jokaisella
      -- koneella tuotuja profiileja vasten, joten vaite nakyy kaikille.
      local huomio = ""
      if v.koodi == "prio" and not v.prioOk then
        huomio = VIRHE .. " (!)|r"
      end

      teksti(rivi, "GameFontHighlightSmall", 130, -3,
        pelaajanVari(luokat[v.nimi]) .. v.nimi .. "|r" .. huomio)

      -- Montako itemia pelaaja on jo saanut. Lootmasterin tarkein luku
      -- heti perusteen jalkeen.
      teksti(rivi, "GameFontHighlightSmall", 250, -3,
        (v.saatu > 0 and KULTA or HIMMEA) .. tostring(v.saatu) .. "|r")

      if jakaja and not item.jaettu and v.koodi ~= "pass" then
        local b = nappi(rivi, 70, 18, "Anna", function()
          NS.Jaa(item, v.nimi)
        end)
        b:SetPoint("TOPRIGHT", -8, -1)
      end

      y = y - 20
    end
  end

  local puuttuu = NS.Vastaamatta(item)
  if #puuttuu > 0 and not item.jaettu and kaikki then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y - 6)
    rivi:SetPoint("TOPRIGHT", 0, y - 6)
    rivi:SetHeight(30)
    teksti(rivi, "GameFontDisableSmall", 8, 0,
      ("odottaa %d vastausta: %s%s"):format(#puuttuu,
        table.concat(puuttuu, ", ", 1, math.min(6, #puuttuu)),
        #puuttuu > 6 and ", …" or ""))
    y = y - 36
  end

  y = piirraJaetut(sisalto, y)

  sisalto:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- Näkymä: Kauppa
--------------------------------------------------------------------------

--- Luovutusta odottavat itemit.
---
--- Addon ei voi antaa laukussa olevaa itemia koodista kasin, mutta se
--- tayttaa kauppaikkunan kun lootmaster avaa kaupan voittajan kanssa.
--- Tama lista on se mika on viela antamatta.
local function piirraKauppa()
  local kehys = nakymat.kauppa

  if not kehys.rakennettu then
    kehys.rakennettu = true

    kehys.ohje = kehys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    kehys.ohje:SetPoint("TOPLEFT", 4, -4)
    kehys.ohje:SetPoint("TOPRIGHT", -4, -4)
    kehys.ohje:SetJustifyH("LEFT")

    kehys.vieritys = teeVieritys(kehys, "LootPrioKauppaScroll")
    kehys.vieritys:SetPoint("TOPLEFT", 0, -38)
    kehys.vieritys:SetPoint("BOTTOMRIGHT", -26, 30)

    local siivoa = nappi(kehys, 150, 22, "Siivoa toimitetut", function()
      local n = NS.SiivoaKaupat()
      NS.Tulosta(("%d toimitettua riviä poistettu."):format(n))
    end)
    siivoa:SetPoint("BOTTOMLEFT", 0, 4)
  end

  local jono = NS.OdottavatKaupat()

  kehys.ohje:SetText(("Luovuttamatta: %s%d|r\nAvaa kauppa pelaajan kanssa — "
    .. "itemit asettuvat paikoilleen itsestään."):format(KULTA, #jono))

  local sisalto = kehys.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(kehys:GetWidth() - 26)

  local y = -4

  if #jono == 0 then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    teksti(rivi, "GameFontDisableSmall", 4, 0,
      "Ei luovuttamattomia itemeitä.")
    sisalto:SetHeight(30)
    return
  end

  local otsikko = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
  otsikko:SetPoint("TOPLEFT", 0, y)
  teksti(otsikko, "GameFontNormalSmall", 4, 0, "ITEM")
  teksti(otsikko, "GameFontNormalSmall", 200, 0, "SAAJA")
  teksti(otsikko, "GameFontNormalSmall", 300, 0, "LAUKUSSA")
  y = y - 18

  -- Onko item oikeasti laukussa. Jos ei ole, kauppaikkuna jaa tyhjaksi -
  -- ja syy on parempi nahda tassa kuin kaupan auettua.
  local laukuissa = {}
  for _, item in ipairs(NS.LaukkujenItemit(0)) do
    laukuissa[item.itemId] = true
  end

  for _, r in ipairs(jono) do
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)
    rivi:SetHeight(18)

    local nimi = r.itemNimi
    if not nimi and r.itemId then nimi = GetItemInfo(r.itemId) end
    nimi = nimi or ("item " .. tostring(r.itemId))
    if nimi:len() > 28 then nimi = nimi:sub(1, 27) .. "…" end

    teksti(rivi, "GameFontHighlightSmall", 4, 0, nimi)
    nimiAlue(rivi, nimi, r.itemId, r.linkki)
    teksti(rivi, "GameFontHighlightSmall", 200, 0, r.nimi or "?")
    teksti(rivi, "GameFontHighlightSmall", 300, 0,
      laukuissa[r.itemId] and (OK .. "kyllä|r") or (VIRHE .. "ei|r"))

    -- Kaupan ulkopuolella annettu item pitaa voida merkita kasin: addon
    -- nakee vain laukkujen muutokset omassa kaupassa.
    local b = nappi(rivi, 80, 18, "Annettu", function()
      NS.MerkitseToimitetuksi(r.indeksi)
    end)
    b:SetPoint("TOPRIGHT", -8, 0)

    y = y - 18
  end

  sisalto:SetHeight(math.max(1, -y))
end

--------------------------------------------------------------------------
-- Näkymä: Jäsenet
--------------------------------------------------------------------------

--- Addonin tila yhdelle pelaajalle: teksti ja vari.
---
--- Kolme eri tilaa, koska ne vaativat eri toimen: puuttuva addon pitaa
--- asentaa, vanha paivittaa, ja tuomaton vienti tuoda. Yksi yhteinen
--- "ei vastannut" ei kerro kummasta on kyse.
local function addonTila(nimi)
  local a = NS.addonit and NS.addonit[nimi]

  if not a then return HIMMEA .. "—|r" end
  if NS.VersioVanhempi(a.versio, NS.VERSIO) then
    return VIRHE .. "v" .. a.versio .. "|r"
  end
  if a.profiileja == 0 then return VIRHE .. "ei dataa|r" end

  return OK .. "v" .. a.versio .. "|r"
end

local function piirraJasenet()
  local kehys = nakymat.jasenet

  if not kehys.rakennettu then
    kehys.rakennettu = true

    kehys.vieritys = teeVieritys(kehys, "LootPrioJasenScroll")
    kehys.vieritys:SetPoint("TOPLEFT", 0, 0)
    kehys.vieritys:SetPoint("BOTTOMRIGHT", -26, 28)

    local tarkista = nappi(kehys, 150, 22, "Tarkista addonit", function()
      NS.PyydaVersiot()
      NS.Tulosta("kysytty. Vastaukset saapuvat parin sekunnin kuluessa.")
    end)
    tarkista:SetPoint("BOTTOMLEFT", 0, 0)

    kehys.selite = kehys:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    kehys.selite:SetPoint("BOTTOMLEFT", 158, 6)
    kehys.selite:SetPoint("BOTTOMRIGHT", -4, 6)
    kehys.selite:SetJustifyH("LEFT")
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
    kehys.selite:SetText("")
    return
  end

  local raidissa = NS.RaidinJasenet()

  local otsikko = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
  otsikko:SetPoint("TOPLEFT", 0, y)
  teksti(otsikko, "GameFontNormalSmall", 4, 0, "HAHMO")
  teksti(otsikko, "GameFontNormalSmall", 150, 0, "VALINNAT")
  teksti(otsikko, "GameFontNormalSmall", 215, 0, "SAATU")
  teksti(otsikko, "GameFontNormalSmall", 280, 0, "ADDON")
  y = y - 18

  local puuttuu = 0

  for _, j in ipairs(jasenet) do
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)
    rivi:SetHeight(16)

    -- Paikalla oleva erottuu: lootmasteria kiinnostaa kuka on nyt mukana.
    local paikalla = raidissa[j.nimi]
    local vari = paikalla and "" or HIMMEA
    teksti(rivi, "GameFontHighlightSmall", 4, 0, vari .. j.nimi .. "|r")
    teksti(rivi, "GameFontHighlightSmall", 150, 0, tostring(j.valintoja))

    -- Sivuston luku suluissa: siita nakee onko SAATU killan historia vai
    -- vain taman koneen kirjaamat jaot.
    local kaikki = NS.SaatuMaara(j.nimi)
    local sivustolta = NS.SaatuSivustolta(j.nimi)
    teksti(rivi, "GameFontHighlightSmall", 215, 0,
      tostring(kaikki)
      .. (kaikki > sivustolta and (HIMMEA .. " (+" .. (kaikki - sivustolta) .. ")|r") or ""))

    if paikalla then
      teksti(rivi, "GameFontHighlightSmall", 280, 0, addonTila(j.nimi))
      if not (NS.addonit and NS.addonit[j.nimi]) then puuttuu = puuttuu + 1 end
    end

    y = y - 16
  end

  sisalto:SetHeight(math.max(1, -y))

  -- Paikalla olevat joilla ei ole profiilia lainkaan: heille jako nayttaa
  -- rikkinaiselta, koska LootPrio-nappi on harmaa eika syy nay mistaan.
  local ilmanProfiilia = {}
  for nimi, online in pairs(raidissa) do
    if online and not NS.db.profiilit[nimi] then
      ilmanProfiilia[#ilmanProfiilia + 1] = nimi
    end
  end
  table.sort(ilmanProfiilia)

  local osat = {}
  if puuttuu > 0 then
    osat[#osat + 1] = ("%s%d ilman addonia|r"):format(VIRHE, puuttuu)
  end
  if #ilmanProfiilia > 0 then
    osat[#osat + 1] = ("%sei profiilia: %s%s|r"):format(VIRHE,
      table.concat(ilmanProfiilia, ", ", 1, math.min(4, #ilmanProfiilia)),
      #ilmanProfiilia > 4 and ", …" or "")
  end

  kehys.selite:SetText(table.concat(osat, "  ·  "))
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

    -- Lista ja vientikentta ovat samassa paikassa: toinen kerrallaan.
    -- Lista on se mita yleensa katsotaan, vienti vain raidin paatteeksi.
    kehys.vieritys = teeVieritys(kehys, "LootPrioHistListScroll")
    kehys.vieritys:SetPoint("TOPLEFT", 0, -24)
    kehys.vieritys:SetPoint("BOTTOMRIGHT", -26, 30)

    local vientiVieritys = CreateFrame("ScrollFrame", "LootPrioHistScroll", kehys,
      "UIPanelScrollFrameTemplate")
    vientiVieritys:SetPoint("TOPLEFT", 0, -24)
    vientiVieritys:SetPoint("BOTTOMRIGHT", -26, 30)
    vientiVieritys:Hide()
    kehys.vientiVieritys = vientiVieritys

    local kentta = CreateFrame("EditBox", nil, vientiVieritys)
    kentta:SetMultiLine(true)
    kentta:SetFontObject(ChatFontNormal)
    kentta:SetWidth(380)
    kentta:SetAutoFocus(false)
    kentta:SetMaxLetters(0)
    kentta:SetScript("OnEscapePressed", function() paa:Hide() end)
    vientiVieritys:SetScrollChild(kentta)
    kehys.kentta = kentta

    kehys.vie = nappi(kehys, 150, 22, "Luo vienti sivustolle", function()
      if kehys.vientiVieritys:IsShown() then
        kehys.vientiVieritys:Hide()
        kehys.vieritys:Show()
        kehys.vie:SetText("Luo vienti sivustolle")
        return
      end

      kehys.vieritys:Hide()
      kehys.vientiVieritys:Show()
      kehys.vie:SetText("Takaisin listaan")
      kehys.kentta:SetText(NS.HistoriaTeksti())
      kehys.kentta:HighlightText()
      kehys.kentta:SetFocus()
      NS.Tulosta("kopioi teksti Ctrl+C ja liita sivuston ylläpitoon.")
    end)
    kehys.vie:SetPoint("BOTTOMLEFT", 0, 4)

    local tyhjennaNappi = nappi(kehys, 110, 22, "Tyhjennä", function()
      NS.db.historia = {}
      kehys.kentta:SetText("")
      NS.PaivitaNakyma("historia")
      NS.Tulosta("historia tyhjennetty.")
    end)
    tyhjennaNappi:SetPoint("BOTTOMLEFT", 156, 4)
  end

  -- Instanssi nakyviin: sivusto nimeaa lokin sen mukaan, ja jos tassa
  -- lukee vaara paikka, vienti kannattaa tehda ennen seuraavaa raidia.
  local alue, koko = NS.Instanssi()
  local paikka = alue and (alue .. (koko > 0 and (" " .. koko .. "-man") or ""))

  kehys.ohje:SetText(("Jaettuja itemeitä: %s%d|r   %s"):format(
    KULTA, #NS.db.historia,
    paikka and (HIMMEA .. paikka .. "|r") or ""))

  local sisalto = kehys.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(kehys:GetWidth() - 26)

  local y = -4

  if #NS.db.historia == 0 then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    teksti(rivi, "GameFontDisableSmall", 4, 0,
      "Ei jaettuja itemeitä. Jaetut näkyvät täällä heti kun ne on assignattu.")
    sisalto:SetHeight(30)
    return
  end

  local otsikko = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
  otsikko:SetPoint("TOPLEFT", 0, y)
  teksti(otsikko, "GameFontNormalSmall", 4, 0, "ITEM")
  teksti(otsikko, "GameFontNormalSmall", 190, 0, "SAAJA")
  teksti(otsikko, "GameFontNormalSmall", 300, 0, "PERUSTE")
  teksti(otsikko, "GameFontNormalSmall", 390, 0, "ROLL")
  y = y - 18

  -- Uusin ylos: viimeksi jaettu on se mita yleensa tarkistetaan.
  for i = #NS.db.historia, 1, -1 do
    local r = NS.db.historia[i]

    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)
    rivi:SetHeight(16)

    local nimi = r.itemNimi
    if not nimi and r.itemId then nimi = GetItemInfo(r.itemId) end
    nimi = nimi or ("item " .. tostring(r.itemId))
    if nimi:len() > 26 then nimi = nimi:sub(1, 25) .. "…" end

    teksti(rivi, "GameFontHighlightSmall", 4, 0, nimi)
    nimiAlue(rivi, nimi, r.itemId)
    teksti(rivi, "GameFontHighlightSmall", 190, 0, r.nimi or "?")

    -- Peruste eli "milla napilla": sama vari kuin vastausnapissa.
    local vast = r.koodi and NS.VASTAUS[r.koodi]
    teksti(rivi, "GameFontHighlightSmall", 300, 0,
      vast and (vast.vari .. vast.nimi .. "|r") or (HIMMEA .. "—|r"))

    teksti(rivi, "GameFontHighlightSmall", 390, 0,
      r.luku and (KULTA .. tostring(r.luku) .. "|r") or (HIMMEA .. "—|r"))

    y = y - 16
  end

  sisalto:SetHeight(math.max(1, -y))
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
    _G[valinta:GetName() .. "Text"]:SetText("Myös raiderit näkevät kaikki vastaukset")
    valinta:SetScript("OnClick", function(self)
      NS.db.rollienNakyvyys = self:GetChecked() and "raid" or "officers"
      paivitaTila()
    end)
    kehys.valinta = valinta

    local selite = kehys:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    selite:SetPoint("TOPLEFT", 6, -36)
    selite:SetPoint("TOPRIGHT", -6, -36)
    selite:SetJustifyH("LEFT")
    selite:SetText("Pois päältä raideri näkee oman vastauksensa ja sen mitä "
      .. "on jo jaettu — kuka sai ja millä napilla. Officerit näkevät kaikkien "
      .. "vastaukset, jotta itemistä voi keskustella ennen antamista. Asetus "
      .. "koskee vain sinun avaamiasi jakoja, ja se on näkyvyysvalinta eikä "
      .. "salaisuus: tiedot kulkevat raidikanavalla joka tapauksessa.")

    local ilmoita = CreateFrame("CheckButton", "LootPrioIlmoita", kehys,
      "UICheckButtonTemplate")
    ilmoita:SetPoint("TOPLEFT", 2, -76)
    ilmoita:SetSize(24, 24)
    _G[ilmoita:GetName() .. "Text"]:SetText("Ilmoita voittaja raidichattiin")
    ilmoita:SetScript("OnClick", function(self)
      NS.db.ilmoitaVoittaja = self:GetChecked() and true or false
    end)
    kehys.ilmoita = ilmoita

    local kauppa = CreateFrame("CheckButton", "LootPrioTaytaKauppa", kehys,
      "UICheckButtonTemplate")
    kauppa:SetPoint("TOPLEFT", 2, -98)
    kauppa:SetSize(24, 24)
    _G[kauppa:GetName() .. "Text"]:SetText("Täytä kauppaikkuna itsestään")
    kauppa:SetScript("OnClick", function(self)
      NS.db.taytaKauppa = self:GetChecked() and true or false
    end)
    kehys.kauppa = kauppa

    -- Laaturaja ratkaisee mita laukuista tarjotaan jaettavaksi.
    local laatuSelite = kehys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    laatuSelite:SetPoint("TOPLEFT", 6, -124)
    laatuSelite:SetText("Jaettavien vähimmäislaatu:")

    local laatuNapit = {
      { laatu = 2, nimi = "Vihreä" },
      { laatu = 3, nimi = "Sininen" },
      { laatu = 4, nimi = "Violetti" },
    }

    kehys.laatuNapit = {}
    local lx = 4
    for _, l in ipairs(laatuNapit) do
      local b = nappi(kehys, 74, 22, l.nimi, function()
        NS.db.laukkuLaatu = l.laatu
        piirraAsetukset()
      end)
      b:SetPoint("TOPLEFT", lx, -144)
      kehys.laatuNapit[l.laatu] = b
      lx = lx + 78
    end

    -- Vastausaika ei pakota mitaan: se vaihtaa kellon varin, ja lootmaster
    -- paattaa itse milloin odottaminen ei enaa tuota vastauksia.
    local aikaSelite = kehys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    aikaSelite:SetPoint("TOPLEFT", 6, -176)
    aikaSelite:SetText("Muistuta vastauksista:")

    local ajat = { 60, 90, 120 }
    kehys.aikaNapit = {}
    local ax = 4
    for _, s in ipairs(ajat) do
      local b = nappi(kehys, 74, 22, s .. " s", function()
        NS.db.vastausAika = s
        piirraAsetukset()
      end)
      b:SetPoint("TOPLEFT", ax, -196)
      kehys.aikaNapit[s] = b
      ax = ax + 78
    end

    local testi = nappi(kehys, 160, 24, "Käynnistä testi", function()
      if NS.AloitaTesti() then naytaNakyma("loot") end
    end)
    testi:SetPoint("TOPLEFT", 4, -228)

    local testiSelite = kehys:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    testiSelite:SetPoint("TOPLEFT", 6, -256)
    testiSelite:SetPoint("TOPRIGHT", -6, -256)
    testiSelite:SetJustifyH("LEFT")
    testiSelite:SetText("Tekee neljä kuviteltua loottia tuoduista valinnoista ja "
      .. "arpoo niihin vastaukset. Assign kirjaa historiaan mutta ei koske "
      .. "pelin loottiin eikä lähetä mitään raidille.")

    local tyhjennaProfiilit = nappi(kehys, 160, 24, "Poista profiilit", function()
      NS.db.profiilit = {}
      NS.db.raidinNimi = nil
      NS.db.tuotu = nil
      paivitaTila()
      naytaNakyma("jasenet")
    end)
    tyhjennaProfiilit:SetPoint("TOPLEFT", 4, -300)
  end

  kehys.valinta:SetChecked(NS.db.rollienNakyvyys == "raid")
  kehys.ilmoita:SetChecked(NS.db.ilmoitaVoittaja)
  kehys.kauppa:SetChecked(NS.db.taytaKauppa ~= false)

  -- Valittu arvo jaa pohjaan, jotta nykyinen asetus nakyy.
  for laatu, b in pairs(kehys.laatuNapit) do
    if laatu == (NS.db.laukkuLaatu or 3) then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end

  for s, b in pairs(kehys.aikaNapit) do
    if s == (NS.db.vastausAika or 90) then
      b:LockHighlight()
    else
      b:UnlockHighlight()
    end
  end
end

--------------------------------------------------------------------------
-- Päivitys
--------------------------------------------------------------------------

function NS.PaivitaNakyma(avain)
  avain = avain or nykyinen
  if not paa or not paa:IsShown() then return end

  paivitaTila()

  if avain == "loot" then piirraLoot()
  elseif avain == "kauppa" then piirraKauppa()
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
-- Itemien valinta laukuista
--------------------------------------------------------------------------

local valinta
local valitut = {}

-- Kasin linkatut itemit. Kaikki jaettava ei ole lootmasterin laukussa:
-- item voi olla toisen pelaajan hallussa tai jo kaupattu vaarin, eika jako
-- saa olla siita kiinni.
local manuaaliset = {}

--- Ikkuna, josta officer poimii jaettavat itemit laukuistaan.
---
--- Lista on rajattu puettaviin ja riittavan hyviin itemeihin: ilman
--- rajausta siina olisi jokainen juomapullo ja kangaspala.
function NS.AvaaValinta()
  if not valinta then
    valinta = CreateFrame("Frame", "LootPrioValinta", UIParent,
      "BasicFrameTemplateWithInset")
    valinta:SetSize(460, 460)
    valinta:SetPoint("CENTER")
    valinta:SetMovable(true)
    valinta:EnableMouse(true)
    valinta:RegisterForDrag("LeftButton")
    valinta:SetScript("OnDragStart", valinta.StartMoving)
    valinta:SetScript("OnDragStop", valinta.StopMovingOrSizing)
    valinta:SetClampedToScreen(true)
    valinta.TitleText:SetText("LootPrio — valitse jaettavat")
    tinsert(UISpecialFrames, "LootPrioValinta")

    -- Linkkikentta: shift-klikkaus itemista liittaa linkin kohdistettuun
    -- kenttaan, joten tahan saa itemin mista tahansa - laukusta, chatista
    -- tai toisen pelaajan viestista.
    local linkkiOhje = valinta:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    linkkiOhje:SetPoint("TOPLEFT", 14, -32)
    linkkiOhje:SetText("Lisää item käsin: shift-klikkaa item kenttään ja paina Lisää.")

    local kentta = CreateFrame("EditBox", "LootPrioValintaKentta", valinta,
      "InputBoxTemplate")
    kentta:SetSize(300, 20)
    kentta:SetPoint("TOPLEFT", 18, -48)
    kentta:SetAutoFocus(false)
    valinta.kentta = kentta

    local function lisaaLinkki()
      local item = NS.LinkistaItem(kentta:GetText())
      if not item then
        NS.Tulosta("kenttaan ei liitetty kelvollista item-linkkia.")
        return
      end

      manuaaliset[#manuaaliset + 1] = item
      valitut["m:" .. #manuaaliset] = true
      kentta:SetText("")
      NS.PaivitaValinta()
    end

    kentta:SetScript("OnEnterPressed", lisaaLinkki)
    kentta:SetScript("OnEscapePressed", function(self)
      self:SetText("")
      self:ClearFocus()
    end)

    local lisaa = nappi(valinta, 80, 22, "Lisää", lisaaLinkki)
    lisaa:SetPoint("TOPLEFT", 326, -47)

    local vieritys = teeVieritys(valinta, "LootPrioValintaScroll")
    vieritys:SetPoint("TOPLEFT", 12, -76)
    vieritys:SetPoint("BOTTOMRIGHT", -32, 56)
    valinta.vieritys = vieritys

    valinta.aloita = nappi(valinta, 150, 24, "Aloita jako", function()
      local lista = {}

      for i, item in ipairs(manuaaliset) do
        if valitut["m:" .. i] then lista[#lista + 1] = item end
      end

      for _, item in ipairs(NS.LaukkujenItemit()) do
        local avain = item.laukku .. ":" .. item.paikka
        if valitut[avain] then lista[#lista + 1] = item end
      end

      if #lista == 0 then
        NS.Tulosta("valitse ensin vahintaan yksi item.")
        return
      end

      valinta:Hide()
      NS.AvaaSessio(lista)
    end)
    valinta.aloita:SetPoint("BOTTOMLEFT", 14, 14)

    local kaikki = nappi(valinta, 100, 24, "Valitse kaikki", function()
      for i in ipairs(manuaaliset) do valitut["m:" .. i] = true end
      for _, item in ipairs(NS.LaukkujenItemit()) do
        valitut[item.laukku .. ":" .. item.paikka] = true
      end
      NS.PaivitaValinta()
    end)
    kaikki:SetPoint("BOTTOMLEFT", 170, 14)

    local eiMitaan = nappi(valinta, 90, 24, "Tyhjennä", function()
      wipe(valitut)
      wipe(manuaaliset)
      NS.PaivitaValinta()
    end)
    eiMitaan:SetPoint("BOTTOMLEFT", 276, 14)
  end

  wipe(valitut)
  wipe(manuaaliset)
  valinta.kentta:SetText("")
  valinta:Show()
  NS.PaivitaValinta()
end

function NS.PaivitaValinta()
  if not valinta or not valinta:IsShown() then return end

  local sisalto = valinta.vieritys.sisalto
  tyhjenna(sisalto)
  sisalto:SetWidth(400)

  local itemit = NS.LaukkujenItemit()
  local y = -4
  local n = 0

  if #itemit == 0 and #manuaaliset == 0 then
    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    teksti(rivi, "GameFontDisableSmall", 4, 0,
      "Laukuissa ei ole jaettavia itemeitä.\n\n"
      .. "Lista näyttää puettavat itemit joiden laatu on\n"
      .. "vähintään sininen. Rajan voi muuttaa Asetuksista.\n\n"
      .. "Voit myös linkata itemin käsin yllä olevaan kenttään.")
    sisalto:SetHeight(84)
    valinta.aloita:SetText("Aloita jako")
    return
  end

  --- Yksi rivi: rasti, nimi ja kysynta. Sama muoto kasin linkatulle ja
  --- laukusta loytyneelle, jottei jako riipu siita mista item tuli.
  local function piirraRivi(avain, item, poistaIndeksi)
    if valitut[avain] then n = n + 1 end

    local rivi = lisaaLapsi(sisalto, CreateFrame("Frame", nil, sisalto))
    rivi:SetPoint("TOPLEFT", 0, y)
    rivi:SetPoint("TOPRIGHT", 0, y)
    rivi:SetHeight(22)

    local ruutu = CreateFrame("CheckButton", nil, rivi, "UICheckButtonTemplate")
    ruutu:SetSize(22, 22)
    ruutu:SetPoint("TOPLEFT", 0, 2)
    ruutu:SetChecked(valitut[avain] and true or false)
    ruutu:SetScript("OnClick", function(self)
      valitut[avain] = self:GetChecked() and true or nil
      NS.PaivitaValinta()
    end)

    teksti(rivi, "GameFontHighlightSmall", 28, -4,
      varilla(item.laatu, item.nimi)
      .. (poistaIndeksi and (" " .. HIMMEA .. "(käsin)|r") or ""))

    local alue = CreateFrame("Frame", nil, rivi)
    alue:SetPoint("TOPLEFT", 28, -2)
    alue:SetSize(tekstinLeveys(item.nimi) + 8, 18)
    itemTooltip(alue, item.linkki, item.itemId)

    -- Montako paikalla olevaa on varannut taman: officer nakee heti onko
    -- itemille kysyntaa vai meneeko se joka tapauksessa vendorille.
    local halukkaita = #NS.KukaHaluaaPaikalla(item.itemId)
    if halukkaita > 0 then
      teksti(rivi, "GameFontHighlightSmall", 330, -4,
        KULTA .. halukkaita .. " prio|r")
    end

    if poistaIndeksi then
      local b = nappi(rivi, 24, 18, "x", function()
        -- Avaimet ovat indekseja, joten poisto siirtaa niita. Rastit on
        -- numeroitava uudelleen samalla - muuten rasti jaisi vaaran
        -- itemin kohdalle.
        -- false eika nil, jotta table.remove saa yhtenaisen taulukon:
        -- aukkoinen taulukko ei sailo pituuttaan luotettavasti.
        local tila, pituus = {}, #manuaaliset
        for i = 1, pituus do tila[i] = valitut["m:" .. i] and true or false end

        table.remove(manuaaliset, poistaIndeksi)
        table.remove(tila, poistaIndeksi)

        for i = 1, pituus do valitut["m:" .. i] = tila[i] or nil end

        NS.PaivitaValinta()
      end)
      b:SetPoint("TOPRIGHT", -4, -2)
    end

    y = y - 22
  end

  -- Kasin linkatut ylimmaksi: ne ovat juuri lisattyja ja siksi niita
  -- katsotaan.
  for i, item in ipairs(manuaaliset) do
    piirraRivi("m:" .. i, item, i)
  end

  for _, item in ipairs(itemit) do
    piirraRivi(item.laukku .. ":" .. item.paikka, item, nil)
  end

  sisalto:SetHeight(math.max(1, -y))
  valinta.aloita:SetText(n > 0 and ("Aloita jako (" .. n .. ")") or "Aloita jako")
end

-- Laukut voivat muuttua kesken valinnan: lootmaster kerää loppuja itemejä
-- ikkunan ollessa auki. Ilman tätä lista jäisi vanhentuneeksi.
local laukkuTarkkailija = CreateFrame("Frame")
laukkuTarkkailija:RegisterEvent("BAG_UPDATE_DELAYED")
laukkuTarkkailija:SetScript("OnEvent", function()
  if NS.PaivitaValinta then NS.PaivitaValinta() end
end)

--------------------------------------------------------------------------
-- Äänestysikkuna
--------------------------------------------------------------------------

--- Raidaajan oma ikkuna: yksi item kerrallaan ja viisi nappia.
---
--- Erillaan paaikkunasta siksi, etta raidaajan koko tehtava on painaa yhta
--- nappia. Paaikkunan valikot, listat ja lajittelut ovat lootmasterin
--- tyokaluja, ja bossin jalkeen niiden selaaminen on vain hidaste.
---
--- Ikkuna nayttaa aina vanhimman itemin johon tama pelaaja ei ole
--- vastannut, ja sulkeutuu itsestaan kun vastattavaa ei ole.
local aanestys

local function aanestysItem()
  local s = NS.sessio
  if not s or s.suljettu then return nil end

  for _, item in ipairs(NS.AvoimetItemit()) do
    if not s.omaVastaus[item.indeksi] then return item end
  end
  return nil
end

function NS.PaivitaAanestys()
  if not aanestys or not aanestys:IsShown() then return end

  local item = aanestysItem()
  if not item then
    aanestys:Hide()
    return
  end

  local nimi, laatu = itemNimi(item)

  aanestys.kuva:SetTexture(ikoni(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
  aanestys.nimi:SetText(varilla(laatu, nimi))
  aanestys.linkki = item.linkki
  aanestys.itemId = item.itemId
  aanestys.indeksi = item.indeksi

  -- Montako on viela edessa. Ilman tata pelaaja ei tieda onko tama
  -- viimeinen nappi vai viides kuudesta.
  local jaljella = 0
  for _, i in ipairs(NS.AvoimetItemit()) do
    if not NS.sessio.omaVastaus[i.indeksi] then jaljella = jaljella + 1 end
  end

  aanestys.tila:SetText(jaljella > 1
    and (HIMMEA .. jaljella .. " itemiä vastaamatta|r")
    or (HIMMEA .. "viimeinen item|r"))

  local omaPrio = NS.OmassaProfiilissa(item.itemId)
  for koodi, b in pairs(aanestys.napit) do
    b:SetEnabled(koodi ~= "prio" or omaPrio)
  end

  aanestys.selite:SetText(omaPrio
    and (KULTA .. "Tämä item on profiilissasi.|r")
    or (HIMMEA .. "Ei profiilissasi — LootPrio ei käytössä.|r"))

  -- Viimeksi jaettu nakyviin tassakin. Raiderin ei tarvitse avata
  -- paaikkunaa nahdakseen mita edellisesta itemista tuli.
  local viimeisin
  for _, i in pairs(NS.sessio.itemit) do
    if i.jaettu and (not viimeisin or i.indeksi > viimeisin.indeksi) then
      viimeisin = i
    end
  end

  if viimeisin then
    local vNimi, vLaatu = itemNimi(viimeisin)
    local vast = viimeisin.saajanKoodi and NS.VASTAUS[viimeisin.saajanKoodi]
    local luokat = NS.RaidinLuokat()

    aanestys.tulos:SetText(("%sViimeksi:|r %s %s→|r %s%s|r %s"):format(
      HIMMEA,
      varilla(vLaatu, vNimi),
      OK,
      pelaajanVari(luokat[viimeisin.saaja]),
      viimeisin.saaja or "?",
      vast and (vast.vari .. vast.nimi .. "|r") or ""))
  else
    aanestys.tulos:SetText("")
  end
end

function NS.AvaaAanestys()
  if not aanestysItem() then return end

  if not aanestys then
    aanestys = CreateFrame("Frame", "LootPrioAanestys", UIParent,
      "BasicFrameTemplateWithInset")
    aanestys:SetSize(420, 196)
    aanestys:SetPoint("CENTER", 0, 160)
    aanestys:SetMovable(true)
    aanestys:EnableMouse(true)
    aanestys:RegisterForDrag("LeftButton")
    aanestys:SetScript("OnDragStart", aanestys.StartMoving)
    aanestys:SetScript("OnDragStop", aanestys.StopMovingOrSizing)
    aanestys:SetClampedToScreen(true)
    aanestys:SetFrameStrata("HIGH")
    aanestys.TitleText:SetText("LootPrio — vastaa")
    tinsert(UISpecialFrames, "LootPrioAanestys")

    local ruutu = CreateFrame("Frame", nil, aanestys)
    ruutu:SetSize(44, 44)
    ruutu:SetPoint("TOPLEFT", 16, -34)

    aanestys.kuva = ruutu:CreateTexture(nil, "ARTWORK")
    aanestys.kuva:SetAllPoints()
    aanestys.kuva:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    ruutu:EnableMouse(true)
    ruutu:SetScript("OnEnter", function(self)
      if not aanestys.linkki and not aanestys.itemId then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(aanestys.linkki or ("item:" .. aanestys.itemId))
      GameTooltip:Show()
    end)
    ruutu:SetScript("OnLeave", function() GameTooltip:Hide() end)

    aanestys.nimi = aanestys:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    aanestys.nimi:SetPoint("TOPLEFT", 70, -38)
    aanestys.nimi:SetPoint("TOPRIGHT", -16, -38)
    aanestys.nimi:SetJustifyH("LEFT")

    aanestys.tila = aanestys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    aanestys.tila:SetPoint("TOPLEFT", 70, -60)

    aanestys.selite = aanestys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    aanestys.selite:SetPoint("TOPLEFT", 16, -86)
    aanestys.selite:SetPoint("TOPRIGHT", -16, -86)
    aanestys.selite:SetJustifyH("LEFT")

    aanestys.tulos = aanestys:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    aanestys.tulos:SetPoint("TOPLEFT", 16, -106)
    aanestys.tulos:SetPoint("TOPRIGHT", -16, -106)
    aanestys.tulos:SetJustifyH("LEFT")
    aanestys.tulos:SetWordWrap(false)

    -- Napit isoina ja yhdella rivilla: ne painetaan kesken taistelun
    -- jalkipyykin, eika pieni nappi osu.
    aanestys.napit = {}
    local x = 14
    for _, v in ipairs(NS.VASTAUKSET) do
      local leveys = (v.koodi == "pass") and 56 or 76

      local b = nappi(aanestys, leveys, 28, v.nimi, function()
        if aanestys.indeksi then NS.Vastaa(aanestys.indeksi, v.koodi) end
        NS.PaivitaAanestys()
      end)
      b:SetPoint("BOTTOMLEFT", x, 14)

      aanestys.napit[v.koodi] = b
      x = x + leveys + 4
    end
  end

  aanestys:Show()
  NS.PaivitaAanestys()
end

function NS.SuljeAanestys()
  if aanestys then aanestys:Hide() end
end

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

  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, nappi)
    -- Oikea klikkaus avaa vastausikkunan uudelleen, jos sen sulki vahingossa
    -- kesken jaon. Ilman tata vastaamatta jaanyt item olisi menetetty.
    if nappi == "RightButton" then
      NS.AvaaAanestys()
      return
    end

    if paa and paa:IsShown() then paa:Hide() else NS.Avaa() end
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("LootPrio")
    GameTooltip:AddLine("Vasen klikkaus: avaa ikkuna", 1, 1, 1)
    GameTooltip:AddLine("Oikea klikkaus: avaa vastausikkuna", 1, 1, 1)

    if NS.sessio then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Jako käynnissä — jakaa "
        .. (NS.sessio.lootmaster or "?"), .79, .64, .15)
    end

    GameTooltip:AddLine("Raahaa: siirrä nappia", .6, .6, .6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  asetaPaikka()
  NS.minimapNappi = b
end

