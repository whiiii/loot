--[[
  LootPrio — loottiruutu ja jako.

  Kun loottiruutu aukeaa, lootmaster avaa jakosession kaikista itemeista.
  Raidilaisten ruudulle tulee vastausikkuna, ja vastaukset kertyvat
  lootmasterin listaan.

  Kaikki itemit menevat jakoon, eivat vain profiileissa olevat: profiili
  on yksi peruste nelijasta, ei paasyvaatimus.
]]

local ADDON, NS = ...

NS.istunto = { lootit = {} }

--- Lukee loottiruudun sisallon.
function NS.LueLootit()
  local lootit = {}
  local maara = GetNumLootItems() or 0

  for slot = 1, maara do
    local linkki = GetLootSlotLink(slot)
    local itemId = NS.ItemIdLinkista(linkki)

    if itemId then
      local _, nimi, _, _, laatu = GetLootSlotInfo(slot)
      lootit[#lootit + 1] = {
        slot = slot,
        itemId = itemId,
        linkki = linkki,
        nimi = nimi,
        laatu = laatu,
      }
    end
  end

  NS.istunto.lootit = lootit
  return lootit
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
--- Kutsu on tehtava napin painalluksesta: peli vaatii monelta lootin
--- jakoon liittyvalta toiminnolta laitteistotapahtuman, eika ajastimesta
--- tai viestista laukaistu kutsu mene lapi.
function NS.Jaa(item, nimi)
  local vastaus = item.vastaukset and item.vastaukset[nimi]
  local luku = vastaus and vastaus.luku
  local koodi = vastaus and vastaus.koodi

  if item.testi then
    NS.KirjaaJako(NS.sessio.id, item.indeksi, nimi)
    NS.Tulosta(("TESTI: %s -> %s"):format(item.nimi or item.itemId, nimi))
    return true
  end

  if not NS.OnLootMaster() then
    NS.Tulosta("vain master looter voi jakaa lootin.")
    return false
  end

  local indeksi = ehdokkaanIndeksi(item.slot, nimi)
  if not indeksi then
    NS.Tulosta(("%s ei ole ehdokkaana talle itemille (liian kaukana tai eri instanssissa?)"):format(nimi))
    return false
  end

  GiveMasterLoot(item.slot, indeksi)

  -- Jako kirjataan kaikilla koneilla, jotta saatujen laskuri pysyy ajan
  -- tasalla muillakin kuin jakajalla.
  NS.KirjaaJako(NS.sessio.id, item.indeksi, nimi)
  NS.Comm.Laheta("JAETTU", ("%s %d %s"):format(NS.sessio.id, item.indeksi, nimi))

  if NS.db.ilmoitaVoittaja then
    local peruste = koodi and NS.VASTAUS[koodi] and NS.VASTAUS[koodi].nimi
    local viesti = ("%s -> %s%s%s"):format(
      item.linkki or item.nimi or "?",
      nimi,
      peruste and (" (" .. peruste) or "",
      peruste and (luku and (", roll " .. luku .. ")") or ")") or ""
    )
    SendChatMessage("LootPrio: " .. viesti, IsInRaid() and "RAID" or "PARTY")
  end

  return true
end

--------------------------------------------------------------------------
-- Testitila
--------------------------------------------------------------------------

--- Rakentaa testisession tuoduista profiileista.
---
--- Itemit poimitaan oikeista valinnoista ja vastaukset arvotaan, jotta
--- koko nakyma kayttaytyy kuten oikeassa raidissa. Mitaan ei anneta
--- kenellekaan eika pelin loottiin kosketa.
function NS.AloitaTesti()
  local jasenet = NS.Jasenet()
  if #jasenet == 0 then
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
    local nimi, linkki, laatu = GetItemInfo(itemId)

    lootit[#lootit + 1] = {
      slot = 0,
      itemId = itemId,
      linkki = linkki,
      nimi = (nimi or ("item " .. itemId)) .. " |cff8b9299[testi]|r",
      laatu = laatu or 4,
      testi = true,
    }
  end

  if #lootit == 0 then
    NS.Tulosta("tuoduissa profiileissa ei ole yhtaan itemia.")
    return false
  end

  -- Sessio avataan ilman lahetysta: testissa ei ole ketaan jolle lahettaa.
  NS.sessio = {
    id = "TESTI",
    alkoi = GetTime(),
    testi = true,
    itemit = {},
  }

  for i, loot in ipairs(lootit) do
    NS.sessio.itemit[i] = {
      indeksi = i,
      slot = loot.slot,
      itemId = loot.itemId,
      linkki = loot.linkki,
      nimi = loot.nimi,
      laatu = loot.laatu,
      testi = true,
      jaettu = false,
      vastaukset = {},
    }
  end

  -- Arvotaan vastauksia: varanneet vastaavat LootPrio, muutama muu
  -- jollakin toisella perusteella.
  local koodit = { "main", "off", "muu", "pass" }

  for _, item in ipairs(NS.sessio.itemit) do
    for _, j in ipairs(jasenet) do
      local valinnat = NS.db.profiilit[j.nimi]
      local haluaa = false
      if valinnat then
        for _, id in pairs(valinnat) do
          if id == item.itemId then haluaa = true break end
        end
      end

      if haluaa then
        item.vastaukset[j.nimi] = { koodi = "prio", luku = math.random(1, 100), prioOk = true }
      elseif math.random(1, 3) == 1 then
        local koodi = koodit[math.random(1, #koodit)]
        item.vastaukset[j.nimi] = {
          koodi = koodi,
          luku = (koodi ~= "pass") and math.random(1, 100) or nil,
          prioOk = false,
        }
      end
    end
  end

  NS.Tulosta(("testisessio: %d itemia, vastaukset arvottu."):format(#NS.sessio.itemit))
  return true
end

--------------------------------------------------------------------------
-- Tapahtumat
--------------------------------------------------------------------------

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("LOOT_OPENED")
kehys:RegisterEvent("LOOT_SLOT_CLEARED")

kehys:SetScript("OnEvent", function(_, tapahtuma, arg1)
  if tapahtuma == "LOOT_OPENED" then
    -- Vain lootmasterille on mitaan tehtavaa: muut eivat voi jakaa.
    if not NS.OnLootMaster() then return end

    local lootit = NS.LueLootit()
    if #lootit == 0 then return end

    if NS.AvaaSessio(lootit) then
      NS.Avaa("loot")
    end

  elseif tapahtuma == "LOOT_SLOT_CLEARED" then
    if NS.sessio then
      for _, item in ipairs(NS.sessio.itemit) do
        if item.slot == arg1 then item.jaettu = true end
      end
      if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
    end
  end
end)
