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

  if NS.db.ilmoitaVoittaja then
    local luku
    for _, r in ipairs(loot.rollit) do
      if r.nimi == nimi then luku = r.luku break end
    end

    local viesti = ("%s -> %s%s"):format(
      loot.linkki or loot.nimi or "?",
      nimi,
      luku and (" (roll " .. luku .. ")") or ""
    )

    SendChatMessage("LootPrio: " .. viesti, IsInRaid() and "RAID" or "PARTY")
  end

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
