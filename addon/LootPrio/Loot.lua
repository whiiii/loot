--[[
  LootPrio — lootin kasittely.

  Kun loottiruutu aukeaa, jokaisesta itemista katsotaan ketka ovat
  varanneet sen profiilissaan. Jos halukkaita on, addon arpoo jokaiselle
  luvun 1-100 ja lootmaster nakee listan suurimmasta pienimpaan.

  Arvonta tehdaan lootmasterin koneella ja lahetetaan muille sellaisenaan.
  Jos jokainen arpoisi itse, numerot eivat tasmaisi kenenkaan kesken.
]]

local ADDON, NS = ...

-- Nykyinen istunto: kaikki avoinna olevat lootit kerralla.
NS.istunto = { lootit = {}, avoin = false }

--- Arpoo luvut halukkaille.
local function arvoRollit(halukkaat)
  local tulos = {}

  for _, h in ipairs(halukkaat) do
    tulos[#tulos + 1] = {
      nimi = h.nimi,
      paikka = h.paikka,
      luku = math.random(1, 100),
    }
  end

  -- Suurin ensin. Tasapelissa nimi ratkaisee, jotta jarjestys on vakaa
  -- eika vaihtele piirrosta toiseen.
  table.sort(tulos, function(a, b)
    if a.luku == b.luku then return a.nimi < b.nimi end
    return a.luku > b.luku
  end)

  return tulos
end

--- Lukee loottiruudun sisallon ja rakentaa istunnon.
function NS.LueLootit()
  local lootit = {}
  local maara = GetNumLootItems() or 0

  for slot = 1, maara do
    local linkki = GetLootSlotLink(slot)
    local itemId = NS.ItemIdLinkista(linkki)

    if itemId then
      local _, nimi, maaraKpl, _, laatu = GetLootSlotInfo(slot)
      local halukkaat = NS.KukaHaluaaPaikalla(itemId)

      lootit[#lootit + 1] = {
        slot = slot,
        itemId = itemId,
        linkki = linkki,
        nimi = nimi,
        laatu = laatu,
        maara = maaraKpl,
        halukkaat = halukkaat,
        rollit = (#halukkaat > 0) and arvoRollit(halukkaat) or {},
        jaettu = false,
      }
    end
  end

  NS.istunto.lootit = lootit
  NS.istunto.avoin = true
  return lootit
end

--- Lahettaa arvonnat raidille asetuksen mukaan.
---
--- "officers" tarkoittaa etta numeroita ei lahetetä lainkaan: raidikanava
--- menee kaikille, eika addonviestia voi rajata osalle. Officerit nakevat
--- numerot omasta ikkunastaan, koska he ajavat samaa addonia.
function NS.JaaRollit()
  if NS.db.rollienNakyvyys ~= "raid" then return end
  if not NS.OnLootMaster() then return end

  for _, loot in ipairs(NS.istunto.lootit) do
    if #loot.rollit > 0 then
      NS.Comm.LahetaRollit(loot.itemId, loot.rollit)
    end
  end
end

--- Etsii master loot -ehdokkaan indeksin nimen perusteella.
---
--- GiveMasterLoot ei ota nimea vaan indeksin, ja indeksit ovat
--- slottikohtaisia - sama pelaaja voi olla eri numerolla eri itemilla.
local function ehdokkaanIndeksi(slot, nimi)
  for i = 1, 40 do
    local ehdokas = GetMasterLootCandidate(slot, i)
    if ehdokas then
      local pelkkaNimi = ehdokas:match("^[^-]+")
      if pelkkaNimi == nimi then return i end
    end
  end
  return nil
end

--- Antaa lootin pelaajalle.
---
--- Kutsu on tehtava napin painalluksesta. Peli vaatii monelta lootin
--- jakoon liittyvalta toiminnolta laitteistotapahtuman, eika ajastimesta
--- tai viestista laukaistu kutsu mene lapi.
function NS.Jaa(loot, nimi)
  local luku
  for _, r in ipairs(loot.rollit) do
    if r.nimi == nimi then luku = r.luku break end
  end

  -- Testitilassa peliin ei koskettu lainkaan: kirjataan vain historia,
  -- jotta koko ketjun voi kayda lapi ilman raidia.
  if loot.testi then
    loot.jaettu = true
    NS.LisaaHistoriaan(loot.itemId, nimi, luku)
    NS.Tulosta(("TESTI: %s -> %s"):format(loot.nimi or loot.itemId, nimi))
    return true
  end

  if not NS.OnLootMaster() then
    NS.Tulosta("vain master looter voi jakaa lootin.")
    return false
  end

  local indeksi = ehdokkaanIndeksi(loot.slot, nimi)
  if not indeksi then
    NS.Tulosta(("%s ei ole ehdokkaana talle itemille (liian kaukana tai eri instanssissa?)"):format(nimi))
    return false
  end

  GiveMasterLoot(loot.slot, indeksi)
  loot.jaettu = true

  -- Historia kirjataan vasta kun jako on oikeasti tehty, jottei siihen
  -- paady itemeita joita kukaan ei saanut.
  NS.LisaaHistoriaan(loot.itemId, nimi, luku)

  if NS.db.ilmoitaVoittaja then
    local viesti = ("%s -> %s%s"):format(
      loot.linkki or loot.nimi or "?",
      nimi,
      luku and (" (roll " .. luku .. ")") or ""
    )

    SendChatMessage("LootPrio: " .. viesti, IsInRaid() and "RAID" or "PARTY")
  end

  return true
end

--- Rakentaa testi-istunnon tuoduista profiileista.
---
--- Itemit poimitaan oikeista valinnoista, jotta halukkaita loytyy ja koko
--- nakyma kayttaytyy kuten oikeassa raidissa. Mitaan ei anneta kenellekaan
--- eika pelin loottiin kosketa.
function NS.AloitaTesti()
  local kpl = 0
  for _ in pairs(NS.db.profiilit) do kpl = kpl + 1 end

  if kpl == 0 then
    NS.Tulosta("tuo ensin profiilit, muuten testissa ei ole ketaan.")
    return false
  end

  -- Suosituimmat itemit ensin: niissa on eniten nahtavaa.
  local laskuri = {}
  for _, valinnat in pairs(NS.db.profiilit) do
    for _, itemId in pairs(valinnat) do
      laskuri[itemId] = (laskuri[itemId] or 0) + 1
    end
  end

  local jarjestys = {}
  for itemId, n in pairs(laskuri) do
    jarjestys[#jarjestys + 1] = { itemId = itemId, n = n }
  end
  table.sort(jarjestys, function(a, b)
    if a.n == b.n then return a.itemId < b.itemId end
    return a.n > b.n
  end)

  local lootit = {}
  for i = 1, math.min(3, #jarjestys) do
    local itemId = jarjestys[i].itemId

    -- Testissa kelpaavat kaikki varanneet, myos ne jotka eivat ole paikalla.
    local halukkaat = NS.KukaHaluaa(itemId)
    local nimi, linkki, laatu = GetItemInfo(itemId)

    lootit[#lootit + 1] = {
      slot = 0,
      itemId = itemId,
      linkki = linkki,
      nimi = (nimi or ("item " .. itemId)) .. " |cff8b9299[testi]|r",
      laatu = laatu or 4,
      maara = 1,
      halukkaat = halukkaat,
      rollit = arvoRollit(halukkaat),
      jaettu = false,
      testi = true,
    }
  end

  NS.istunto.lootit = lootit
  NS.istunto.avoin = true
  NS.istunto.testi = true

  NS.Tulosta(("testi-istunto: %d itemia."):format(#lootit))
  return true
end

-- Tapahtumat ---------------------------------------------------------------

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("LOOT_OPENED")
kehys:RegisterEvent("LOOT_CLOSED")
kehys:RegisterEvent("LOOT_SLOT_CLEARED")

kehys:SetScript("OnEvent", function(_, tapahtuma, arg1)
  if tapahtuma == "LOOT_OPENED" then
    -- Vain lootmasterille on mitaan naytettavaa: muut eivat voi jakaa.
    if not NS.OnLootMaster() then return end

    local lootit = NS.LueLootit()

    local kiinnostavia = 0
    for _, l in ipairs(lootit) do
      if #l.halukkaat > 0 then kiinnostavia = kiinnostavia + 1 end
    end

    if kiinnostavia > 0 then
      NS.JaaRollit()
      if NS.AvaaLootIkkuna then NS.AvaaLootIkkuna() end
    end

  elseif tapahtuma == "LOOT_SLOT_CLEARED" then
    for _, l in ipairs(NS.istunto.lootit) do
      if l.slot == arg1 then l.jaettu = true end
    end
    if NS.PaivitaLootIkkuna then NS.PaivitaLootIkkuna() end

  elseif tapahtuma == "LOOT_CLOSED" then
    NS.istunto.avoin = false
    -- Ikkuna jatetaan auki tarkoituksella: lootmaster haluaa usein katsoa
    -- numeroita viela sen jalkeen kun ruutu on sulkeutunut.
    if NS.PaivitaLootIkkuna then NS.PaivitaLootIkkuna() end
  end
end)
