--[[
  LootPrio — laukut ja jako.

  Lootmaster kerää lootit ensin omiin laukkuihinsa ja laittaa ne sitten
  jakoon. Addon ei siis lue loottiruutua vaan laukkuja.

  Siksi addon ei myöskään anna itemia kenellekaan: se kirjaa paatoksen ja
  kertoo sen raidille, mutta itse tavara vaihtaa omistajaa kaupassa.
  Pelin oma lootin jako toimii vain avoimen loottiruudun kautta, eika
  laukussa olevaa itemia voi antaa koodista kasin.
]]

local ADDON, NS = ...

--------------------------------------------------------------------------
-- Laukut
--------------------------------------------------------------------------

-- Laukkurajapinta vaihtoi paikkaa kesken Classicin elinkaaren. Molemmat
-- tuetaan, jottei addon ole sidottu yhteen asiakasversioon. Nimiavaruudessa,
-- koska myos Kauppa.lua etsii itemeita laukuista.
function NS.LaukunKoko(laukku)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(laukku) or 0
  end
  return (GetContainerNumSlots and GetContainerNumSlots(laukku)) or 0
end

function NS.LaukunLinkki(laukku, paikka)
  if C_Container and C_Container.GetContainerItemLink then
    return C_Container.GetContainerItemLink(laukku, paikka)
  end
  return GetContainerItemLink and GetContainerItemLink(laukku, paikka)
end

local laukunKoko, laukunLinkki = NS.LaukunKoko, NS.LaukunLinkki

--- Itemi linkista jaettavaksi riviksi.
---
--- Tata kautta tulevat ne itemit jotka officer linkkaa kasin: kaikki ei ole
--- aina lootmasterin laukussa, eika jako saa olla siita kiinni.
function NS.LinkistaItem(linkki)
  if type(linkki) ~= "string" then return nil end

  local itemId = NS.ItemIdLinkista(linkki)
  if not itemId then return nil end

  -- Linkin voi liittaa myos pelkkana tekstina, joten varmistetaan etta
  -- peli tuntee itemin. GetItemInfo palauttaa nil jos tietoa ei ole vielä
  -- ladattu - silloin kaytetaan itemId:ta ja nimi taydentyy myohemmin.
  local nimi, kokoLinkki, laatu = GetItemInfo(itemId)

  return {
    itemId = itemId,
    linkki = kokoLinkki or linkki,
    nimi = nimi or ("item " .. itemId),
    laatu = laatu or 4,
    manuaalinen = true,
  }
end

--- Jaettavaksi kelpaavat itemit laukuista.
---
--- Rajaus laatuun ja puettavuuteen on valttamaton: ilman sita listassa
--- olisi jokainen juomapullo ja kangaspala laukusta.
function NS.LaukkujenItemit(minLaatu)
  minLaatu = minLaatu or NS.db.laukkuLaatu or 3
  local tulos = {}

  for laukku = 0, 4 do
    for paikka = 1, laukunKoko(laukku) do
      local linkki = laukunLinkki(laukku, paikka)

      if linkki then
        local nimi, _, laatu, _, _, _, _, _, _, _ = GetItemInfo(linkki)
        local itemId = NS.ItemIdLinkista(linkki)

        if itemId and laatu and laatu >= minLaatu and IsEquippableItem(linkki) then
          tulos[#tulos + 1] = {
            laukku = laukku,
            paikka = paikka,
            itemId = itemId,
            linkki = linkki,
            nimi = nimi or ("item " .. itemId),
            laatu = laatu,
          }
        end
      end
    end
  end

  table.sort(tulos, function(a, b)
    if a.laatu ~= b.laatu then return a.laatu > b.laatu end
    return a.nimi < b.nimi
  end)

  return tulos
end

--------------------------------------------------------------------------
-- Jako
--------------------------------------------------------------------------

--- Merkitsee itemin jaetuksi ja kertoo siita raidille.
---
--- Tama ei siirra tavaraa. Lootmaster antaa itemin kaupassa; addon pitaa
--- kirjaa siita kuka sen sai ja milla perusteella.
function NS.Jaa(item, nimi)
  if not NS.sessio then return false end

  local vastaus = item.vastaukset and item.vastaukset[nimi]
  local koodi = vastaus and vastaus.koodi
  local luku = vastaus and vastaus.luku

  if not item.testi and not NS.OnOfficer() then
    NS.Tulosta("vain officer voi jakaa lootin.")
    return false
  end

  NS.KirjaaJako(NS.sessio.id, item.indeksi, nimi, koodi, luku)

  if not item.testi then
    -- Jono kauppaan vain jaon tehneelle: tavara on hanen laukussaan, ja
    -- vain han voi sen luovuttaa.
    if NS.LisaaKauppaan and NS.sessio.lootmaster == NS.OmaNimi() then
      NS.LisaaKauppaan(item.itemId, nimi, item.nimi, item.linkki, item.historiaId)
    end

    NS.Comm.Laheta("JAETTU", ("%s %d %s %s %d"):format(
      NS.sessio.id, item.indeksi, nimi, koodi or "muu", luku or 0))

    if NS.db.ilmoitaVoittaja and IsInGroup() then
      local peruste = koodi and NS.VASTAUS[koodi] and NS.VASTAUS[koodi].nimi or "?"
      local viesti = ("%s -> %s (%s%s)"):format(
        item.linkki or item.nimi or "?",
        nimi, peruste,
        luku and (", roll " .. luku) or "")
      SendChatMessage("LootPrio: " .. viesti, IsInRaid() and "RAID" or "PARTY")
    end
  else
    NS.Tulosta(("TESTI: %s -> %s"):format(item.nimi or item.itemId, nimi))
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
--- kenellekaan eika kenellekaan laheteta mitaan.
function NS.AloitaTesti()
  local jasenet = NS.Jasenet()
  if #jasenet == 0 then
    NS.Tulosta("tuo ensin profiilit, muuten testissa ei ole ketaan.")
    return false
  end

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

  if #jarjestys == 0 then
    NS.Tulosta("tuoduissa profiileissa ei ole yhtaan itemia.")
    return false
  end

  local valitut = {}
  for i = 1, math.min(4, #jarjestys) do
    local itemId = jarjestys[i].itemId
    local nimi, linkki, laatu = GetItemInfo(itemId)
    valitut[#valitut + 1] = {
      itemId = itemId,
      linkki = linkki,
      nimi = (nimi or ("item " .. itemId)) .. " |cff8b9299[testi]|r",
      laatu = laatu or 4,
      testi = true,
    }
  end

  NS.AvaaSessio(valitut, true)

  -- Arvotaan vastauksia: varanneet vastaavat LootPrio, osa muista
  -- jollakin toisella perusteella.
  local koodit = { "main", "off", "muu", "pass" }

  for _, item in pairs(NS.sessio.itemit) do
    for _, j in ipairs(jasenet) do
      local valinnat = NS.db.profiilit[j.nimi]
      local haluaa = false
      if valinnat then
        for _, id in pairs(valinnat) do
          if id == item.itemId then haluaa = true break end
        end
      end

      if haluaa then
        item.vastaukset[j.nimi] =
          { koodi = "prio", luku = math.random(1, 100), prioOk = true }
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

  NS.Tulosta(("testisessio: %d itemia, vastaukset arvottu."):format(#valitut))
  return true
end
