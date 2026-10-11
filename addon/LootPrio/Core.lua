--[[
  LootPrio — perusta.

  Addon ei paase verkkoon: WoW ei anna Lua-koodille mitaan yhteytta
  ulospain. Siksi profiilit tuodaan liittamalla sivustolta kopioitu teksti,
  ja ne sailotaan SavedVariables-tiedostoon.
]]

local ADDON, NS = ...

NS.NIMI = ADDON
NS.VERSIO = "0.10"
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

  -- Killan officerit sivustolta: [hahmo] = true. Tyhja tarkoittaa "ei
  -- tietoa", jolloin pelkka raidin arvo riittaa.
  officerit = {},

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

--- Oman .toc-tiedoston ilmoittama Interface-numero.
---
--- Rajapinta siirtyi C_AddOns-nimiavaruuteen kesken Classicin elinkaaren.
--- Molemmat tuetaan, koska juuri taman addonin ongelma on se ettei
--- clientin versiosta ole varmuutta.
function NS.TocInterface()
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, "Interface")
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(ADDON, "Interface")
  end
  return nil
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

--- Onko pelaajalla killan officer-oikeudet sivustolla.
---
--- Lista tulee viennin O-rivilla. Tyhja lista tarkoittaa "ei tietoa":
--- vanha vienti ei sisalla sita, eika tuomaton addon tieda mitaan. Silloin
--- ei rajoiteta - addon joka lukitsee itsensa puuttuvan datan takia on
--- hyodyttomampi kuin addon joka luottaa raidin arvoon.
function NS.SivustonOfficer(nimi)
  local lista = NS.db and NS.db.officerit
  if not lista then return true end

  local kpl = 0
  for _ in pairs(lista) do kpl = kpl + 1 end
  if kpl == 0 then return true end

  return lista[nimi] == true
end

--- Pelkka raidin arvo, ilman killan officer-tarkistusta.
---
--- Tarvitaan vain sen selittamiseen miksi jakonappi puuttuu: assist joka
--- ei ole killan officer ansaitsee syyn, ei tyhjaa ruutua.
function NS.OnJohtajaTaiApulainen(nimi)
  nimi = nimi or NS.OmaNimi()

  if not IsInRaid() then
    return UnitIsGroupLeader("player") and nimi == NS.OmaNimi()
  end

  for i = 1, GetNumGroupMembers() do
    local rNimi, rank = GetRaidRosterInfo(i)
    if rNimi and NS.Nimi(rNimi) == nimi then
      return (rank or 0) >= 1
    end
  end
  return false
end

--- Onko pelaajalla oikeus avata jako ja nahda kaikkien vastaukset.
---
--- Vaatii seka raidin arvon etta killan officer-oikeuden. Raidin arvo
--- yksin ei riita: assist annetaan usein markkereita varten eika loottia.
--- Killan arvo yksin ei riita myoskaan: raidissa jakaa se jolla on raidin
--- oikeudet, ei officer joka on paikalla vain katsomassa.
---
--- Kumpikaan ei tule viestin sisallosta - raidin arvo luetaan pelilta ja
--- officer-lista tuodusta viennista - joten muokattu addon ei voi vaittaa
--- olevansa kumpikaan.
function NS.OnOfficer(nimi)
  nimi = nimi or NS.OmaNimi()

  if not NS.SivustonOfficer(nimi) then return false end

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

--- Onko pelaaja raidin johtaja.
---
--- Eri asia kuin officer: apulaisia voi olla monta, johtaja on yksi. Vain
--- johtaja voi ottaa kesken jaaneen jaon haltuunsa, koska muuten kaksi
--- apulaista voisi riidella siita kumpi jakaa.
---
--- Vaatii myos killan officer-oikeuden: haltuunotto antaa oikeuden jakaa,
--- eika sita voi saada helpommin kuin jaon avaamisen.
function NS.OnJohtaja(nimi)
  nimi = nimi or NS.OmaNimi()

  if not NS.SivustonOfficer(nimi) then return false end

  if not IsInRaid() then
    return UnitIsGroupLeader("player") and nimi == NS.OmaNimi()
  end

  for i = 1, GetNumGroupMembers() do
    local rNimi, rank = GetRaidRosterInfo(i)
    if rNimi and NS.Nimi(rNimi) == nimi then
      return (rank or 0) >= 2
    end
  end
  return false
end

--- Onko nimetty pelaaja paikalla ja yhteydessa.
function NS.Paikalla(nimi)
  if not nimi then return false end
  return NS.RaidinJasenet()[nimi] == true
end

--- Raidissa olevien luokat: [profiilinimi] = "WARRIOR".
---
--- Luokkavari on nopein tapa erottaa nimet toisistaan listassa, eika sita
--- varten kannata kysya sivustolta mitaan - peli tietaa sen jo.
function NS.RaidinLuokat()
  local luokat = {}

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local nimi, _, _, _, _, tiedosto = GetRaidRosterInfo(i)
      if nimi then luokat[NS.Nimi(nimi)] = tiedosto end
    end
  else
    luokat[NS.OmaNimi()] = select(2, UnitClass("player"))
    for i = 1, GetNumSubgroupMembers() do
      local yksikko = "party" .. i
      local nimi = UnitName(yksikko)
      if nimi then luokat[NS.Nimi(nimi)] = select(2, UnitClass(yksikko)) end
    end
  end

  return luokat
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

--- Missa ollaan ja kuinka suuri raidi on.
---
--- Sivusto erottaa illat toisistaan naiden perusteella: samalla viikolla
--- voi olla yksi 40-man ja pari 20-man, eri lootmastereilla. Ilman
--- instanssia ja kokoa lokit nayttaisivat jalkikateen samanlaisilta.
function NS.Instanssi()
  local nimi, tyyppi, _, _, maxKoko, _, _, _, ryhmanKoko = GetInstanceInfo()

  -- Instanssin ulkopuolella nimi on maailmankartan alue, joka ei kerro
  -- raidista mitaan.
  if tyyppi ~= "raid" and tyyppi ~= "party" then nimi = nil end

  local koko = 0
  if maxKoko and maxKoko > 0 then
    koko = maxKoko
  elseif ryhmanKoko and ryhmanKoko > 0 then
    koko = ryhmanKoko
  else
    koko = GetNumGroupMembers() or 0
  end

  return nimi, koko
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

  NS.Tulosta(("v%s ladattu. Profiileja %d. Avaa ikkuna minimapin napista tai /lp"):format(
    NS.VERSIO, kpl))

  -- Clientin Interface-numero nakyviin heti. Vaara numero .toc-tiedostossa
  -- nakyy vain merkintana "Incompatible" addonilistassa, eika mikaan kerro
  -- mika oikea numero olisi - paitsi tama rivi, kun addon kerran latautuu.
  local tocNumero = NS.TocInterface()
  local clientNumero = select(4, GetBuildInfo())

  if tocNumero and clientNumero and tostring(tocNumero) ~= tostring(clientNumero) then
    NS.Tulosta(("HUOM: .toc sanoo %s, client on %s. Korjaa .toc-tiedoston "
      .. "ensimmainen rivi muotoon '## Interface: %s'."):format(
      tocNumero, clientNumero, clientNumero))
  end

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
