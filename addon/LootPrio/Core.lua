--[[
  LootPrio — perusta.

  Addon ei paase verkkoon: WoW ei anna Lua-koodille mitaan yhteytta
  ulospain. Siksi profiilit tuodaan liittamalla sivustolta kopioitu teksti,
  ja ne sailotaan SavedVariables-tiedostoon.
]]

local ADDON, NS = ...

NS.NIMI = ADDON
NS.VERSIO = "0.6"
NS.VARI = "|cffc9a227"   -- sama kulta kuin sivustolla
NS.LOPPU = "|r"

--- Oletusasetukset. Puuttuvat kentat taytetaan naista joka latauksella,
--- jotta vanha tallennus ei kaadu uuteen asetukseen.
local OLETUKSET = {
  -- Kuka nakee arvonnat: "officers" tai "raid".
  rollienNakyvyys = "officers",

  -- Ilmoitetaanko voittaja raidichattiin kun loot jaetaan.
  ilmoitaVoittaja = true,

  -- Tuodut profiilit: [hahmonNimi] = { [paikka] = itemId }
  profiilit = {},

  -- Sivuston tieto siita montako itemia kukin on saanut: [hahmo] = maara.
  -- Addonin oma historia on vain taman koneen tieto, joten ilman tata luku
  -- nollautuu heti kun lootmaster vaihtuu.
  saadut = {},

  -- Tuonnin tiedot, jotta nakee milloin data on peraisin.
  raidinNimi = nil,
  tuotu = nil,

  -- Jaettu loot. Lista rivia { itemId, nimi, aika, luku, koodi, itemNimi }.
  -- Tasta tehdaan vienti sivustolle.
  historia = {},

  -- Laukkulistan vahimmaislaatu: 2 vihrea, 3 sininen, 4 violetti.
  -- Ilman rajaa listassa olisi jokainen juomapullo ja kangaspala.
  laukkuLaatu = 3,

  -- Assignatut itemit jotka odottavat luovutusta. Lista rivia
  -- { itemId, nimi, itemNimi, linkki, aika, toimitettu }.
  kaupat = {},

  -- Taytetaanko kauppaikkuna itsestaan. Addon ei koskaan hyvaksy kauppaa,
  -- vain asettaa tavarat paikoilleen.
  taytaKauppa = true,

  -- Historian rivien juokseva tunniste. Tarvitaan jaon perumiseen:
  -- indeksi siirtyy kun rivi poistetaan, tunniste ei.
  historiaSeuraavaId = 1,

  -- Montako sekuntia vastauksia odotetaan ennen kuin niista muistutetaan.
  -- Ei pakota mitaan: lootmaster paattaa milloin riittaa.
  vastausAika = 90,

  -- Hahmon muut kirjoitusasut: [alias pienella] = profiilin nimi. Peli ja
  -- sivusto eivat valttamatta kayta samaa muotoa.
  aliakset = {},

  -- Minimap-napin kulma asteina. Sijainti sailyy istuntojen yli.
  minimapKulma = 200,
}

local function taydenna(kohde, oletus)
  for avain, arvo in pairs(oletus) do
    if kohde[avain] == nil then
      if type(arvo) == "table" then
        kohde[avain] = {}
        taydenna(kohde[avain], arvo)
      else
        kohde[avain] = arvo
      end
    end
  end
end

function NS.Tulosta(...)
  print(NS.VARI .. "LootPrio" .. NS.LOPPU .. ":", ...)
end

--- Pelaajan nimi profiilien muodossa.
---
--- Muunnos tehdaan tassa eika kutsupaikoissa: jos oma nimi olisi valilla
--- pelin ja valilla sivuston muodossa, vertailut osuisivat satunnaisesti.
--- NS.Nimi tulee Data.lua:sta, joka latautuu taman jalkeen - siksi
--- tarkistus.
function NS.OmaNimi()
  local nimi = UnitName("player")
  if NS.Nimi then return NS.Nimi(nimi) end
  return nimi
end

--- Pelin antama nimi sellaisenaan, ilman muunnosta.
---
--- Tarvitaan niissa harvoissa paikoissa joissa nimea kaytetaan pelille
--- puhumiseen eika profiilien vertailuun.
function NS.OmaPeliNimi()
  return UnitName("player")
end

--- Onko pelaaja raidin johtaja tai apulainen.
---
--- Officer-oikeus luetaan raidin arvosta eika killan arvosta: raidissa
--- loottia jakaa se jolla on raidin oikeudet, ei se jolla on kiltatunnus.
function NS.OnOfficer(nimi)
  nimi = nimi or NS.OmaNimi()

  if not IsInRaid() then
    -- Ryhmassa ilman raidia johtaja riittaa.
    return UnitIsGroupLeader("player") and nimi == NS.OmaNimi()
  end

  for i = 1, GetNumGroupMembers() do
    local rNimi, rank = GetRaidRosterInfo(i)
    -- Roosterin nimi on pelin muodossa, vertailtava nimi profiilien.
    if rNimi and NS.Nimi(rNimi) == nimi then
      return (rank or 0) >= 1
    end
  end
  return false
end

--- Onko pelaaja master looter.
function NS.OnLootMaster()
  local metodi, mlPartyID, mlRaidID = GetLootMethod()
  if metodi ~= "master" then return false end

  if IsInRaid() then
    if not mlRaidID then return false end
    local nimi = GetRaidRosterInfo(mlRaidID)
    return nimi == NS.OmaPeliNimi()
  end

  -- Ryhmassa 0 tarkoittaa pelaajaa itseaan.
  return mlPartyID == 0
end

--- Itemin numero linkista. Linkki on muotoa |cff...|Hitem:19019:...
function NS.ItemIdLinkista(linkki)
  if not linkki then return nil end
  local id = linkki:match("item:(%d+)")
  return id and tonumber(id) or nil
end

--- Raidissa paikalla olevat profiilien nimilla joukkona.
---
--- Nimet muunnetaan heti profiilien muotoon: tama on se paikka josta pelin
--- nimet valuvat koko addonin lapi, ja yksi muunnos tassa riittaa.
function NS.RaidinJasenet()
  local joukko = {}

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local nimi, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
      if nimi then joukko[NS.Nimi(nimi)] = online ~= false end
    end
  elseif IsInGroup() then
    joukko[NS.OmaNimi()] = true
    for i = 1, GetNumSubgroupMembers() do
      local nimi = UnitName("party" .. i)
      if nimi then joukko[NS.Nimi(nimi)] = true end
    end
  else
    joukko[NS.OmaNimi()] = true
  end

  return joukko
end

-- Latauksen kasittely ------------------------------------------------------

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("ADDON_LOADED")
kehys:SetScript("OnEvent", function(_, tapahtuma, nimi)
  if tapahtuma ~= "ADDON_LOADED" or nimi ~= ADDON then return end

  LootPrioDB = LootPrioDB or {}
  taydenna(LootPrioDB, OLETUKSET)
  NS.db = LootPrioDB

  local kpl = 0
  for _ in pairs(NS.db.profiilit) do kpl = kpl + 1 end

  NS.Tulosta(("ladattu. Profiileja %d. Avaa ikkuna minimapin napista tai /lp"):format(kpl))

  if NS.LuoMinimapNappi then NS.LuoMinimapNappi() end
end)

-- Komennot -----------------------------------------------------------------

SLASH_LOOTPRIO1 = "/lootprio"
SLASH_LOOTPRIO2 = "/lp"

SlashCmdList.LOOTPRIO = function(syote)
  local komento, loput = syote:match("^(%S*)%s*(.-)$")
  komento = (komento or ""):lower()

  -- Komennot ovat oikotie, eivat ainoa tie: kaikki loytyy ikkunan napeista.
  if komento == "" then
    NS.Avaa()
  elseif komento == "loot" then
    NS.Avaa("loot")
  elseif komento == "tuo" or komento == "import" then
    NS.Avaa("tuonti")
  elseif komento == "jasenet" then
    NS.Avaa("jasenet")
  elseif komento == "historia" then
    NS.Avaa("historia")
  elseif komento == "kauppa" then
    NS.Avaa("kauppa")
  else
    NS.Tulosta("kayta: /lp  (avaa ikkunan)")
  end
end
