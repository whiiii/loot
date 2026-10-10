--[[
  LootPrio — kaupan apuri.

  Addon ei voi antaa laukussa olevaa itemia kenellekaan, mutta se voi
  tayttaa kauppaikkunan. Kun lootmaster avaa kaupan voittajan kanssa,
  assignatut itemit asettuvat vaihtopaikoille itsestaan.

  Addon ei koskaan hyvaksy kauppaa. Nappia painaa ihminen: vaarin mennyt
  automaattinen kauppa ei ole peruttavissa, ja silma ehtii aina katsoa
  kerran mita ruudulla on.
]]

local ADDON, NS = ...

-- Kaupan tavarapaikat. Seitsemas on "ei vaihdeta" -paikka eika siihen
-- kosketa missaan tilanteessa.
local PAIKKOJA = 6

--------------------------------------------------------------------------
-- Jono
--------------------------------------------------------------------------

--- Assignattu item odottamaan kauppaa.
---
--- Jono on tarpeen koska jako ja luovutus tapahtuvat eri aikaan: itemit
--- jaetaan bossin jalkeen ja kaupataan silloin kun kummallakin sattuu
--- olemaan hetki aikaa.
function NS.LisaaKauppaan(itemId, nimi, itemNimi, linkki)
  if not itemId or not nimi then return end
  if nimi == NS.OmaNimi() then return end  -- itselleen ei kaupata

  NS.db.kaupat[#NS.db.kaupat + 1] = {
    itemId = itemId,
    nimi = nimi,
    itemNimi = itemNimi,
    linkki = linkki,
    aika = date("%Y-%m-%d %H:%M:%S"),
  }
end

--- Toimittamatta olevat kaupat, halutessa yhdelle pelaajalle.
function NS.OdottavatKaupat(nimi)
  local tulos = {}

  for i, r in ipairs(NS.db.kaupat) do
    if not r.toimitettu and (not nimi or r.nimi == nimi) then
      r.indeksi = i
      tulos[#tulos + 1] = r
    end
  end

  return tulos
end

function NS.MerkitseToimitetuksi(indeksi)
  local r = NS.db.kaupat[indeksi]
  if not r then return end

  r.toimitettu = true
  r.toimitettuAika = date("%Y-%m-%d %H:%M:%S")

  if NS.PaivitaNakyma then NS.PaivitaNakyma("kauppa") end
end

--- Poistaa toimitetut jonosta.
function NS.SiivoaKaupat()
  local jaljelle = {}
  for _, r in ipairs(NS.db.kaupat) do
    if not r.toimitettu then jaljelle[#jaljelle + 1] = r end
  end

  local poistui = #NS.db.kaupat - #jaljelle
  NS.db.kaupat = jaljelle

  if NS.PaivitaNakyma then NS.PaivitaNakyma("kauppa") end
  return poistui
end

--------------------------------------------------------------------------
-- Laukkujen selaus
--------------------------------------------------------------------------

--- Etsii itemin laukuista. Ohittaa paikat jotka on jo kaytetty talla
--- kierroksella: kaupassa oleva item nakyy laukussa edelleen, joten ilman
--- tata sama kappale yritettaisiin asettaa kahdesti.
local function etsiLaukuista(itemId, kaytetyt)
  for laukku = 0, 4 do
    for paikka = 1, NS.LaukunKoko(laukku) do
      local avain = laukku .. ":" .. paikka

      if not kaytetyt[avain] then
        local linkki = NS.LaukunLinkki(laukku, paikka)
        if linkki and NS.ItemIdLinkista(linkki) == itemId then
          return laukku, paikka
        end
      end
    end
  end

  return nil
end

--- Montako kappaletta kyseista itemia on laukuissa.
local function montaLaukuissa(itemId)
  local n = 0

  for laukku = 0, 4 do
    for paikka = 1, NS.LaukunKoko(laukku) do
      local linkki = NS.LaukunLinkki(laukku, paikka)
      if linkki and NS.ItemIdLinkista(linkki) == itemId then n = n + 1 end
    end
  end

  return n
end

local function nosta(laukku, paikka)
  if C_Container and C_Container.PickupContainerItem then
    C_Container.PickupContainerItem(laukku, paikka)
  elseif PickupContainerItem then
    PickupContainerItem(laukku, paikka)
  end
end

--------------------------------------------------------------------------
-- Kauppaikkunan tayttaminen
--------------------------------------------------------------------------

--- Kaupan vastapuolen nimi ilman realmia.
local function vastapuoli()
  local nimi = UnitName("npc")

  -- Varalla ikkunan oma teksti: yksikko "npc" ei ole kaikissa
  -- asiakasversioissa kaytettavissa kaupan aikana.
  if not nimi and TradeFrameRecipientNameText then
    nimi = TradeFrameRecipientNameText:GetText()
  end

  return nimi and nimi:match("^[^-]+") or nil
end

local function vapaaPaikka()
  for i = 1, PAIKKOJA do
    if not GetTradePlayerItemLink(i) then return i end
  end
  return nil
end

-- Mita laukuissa oli kaupan alkaessa. Vertailu lopussa kertoo mika
-- oikeasti vaihtoi omistajaa - kaupan voi perua, joten avaaminen yksin ei
-- ole todiste mistaan.
local ennen = nil
local kohde = nil

local function tayta()
  kohde = vastapuoli()
  if not kohde then return end

  local jono = NS.OdottavatKaupat(kohde)
  if #jono == 0 then return end

  ennen = {}
  for _, r in ipairs(jono) do
    ennen[r.itemId] = montaLaukuissa(r.itemId)
  end

  local kaytetyt = {}
  local asetettu, puuttuu = 0, 0

  for _, r in ipairs(jono) do
    local paikka = vapaaPaikka()
    if not paikka then break end

    local laukku, slotti = etsiLaukuista(r.itemId, kaytetyt)

    if laukku then
      ClearCursor()
      nosta(laukku, slotti)

      -- Varmistetaan etta item on oikeasti kursorissa. Lukittu tai
      -- sidottu item ei nouse, ja ilman tarkistusta klikkaus osuisi
      -- tyhjaan kursoriin ja poistaisi paikalla jo olevan tavaran.
      if GetCursorInfo() then
        ClickTargetTradeButton(paikka)
        kaytetyt[laukku .. ":" .. slotti] = true
        asetettu = asetettu + 1
      end

      ClearCursor()
    else
      puuttuu = puuttuu + 1
    end
  end

  if asetettu > 0 then
    NS.Tulosta(("%d item%s kauppaan: %s"):format(
      asetettu, asetettu == 1 and "" or "ia", kohde))
  end

  if puuttuu > 0 then
    NS.Tulosta(("%d assignattua itemia ei loytynyt laukuista."):format(puuttuu))
  end
end

--- Merkitsee jonosta ne itemit jotka oikeasti lahtivat laukuista.
---
--- Kaupan sulkeminen ei kerro onnistuiko se, joten lasketaan kappaleet.
--- Nain peruttu kauppa ei merkitse mitaan toimitetuksi.
local function tarkistaTulos()
  if not kohde or not ennen then return end

  local nyt = kohde
  local vanha = ennen
  kohde, ennen = nil, nil

  local jono = NS.OdottavatKaupat(nyt)
  local toimitettu = 0

  for itemId, maara in pairs(vanha) do
    local vahennys = maara - montaLaukuissa(itemId)

    for _, r in ipairs(jono) do
      if vahennys <= 0 then break end
      if r.itemId == itemId and not r.toimitettu then
        r.toimitettu = true
        r.toimitettuAika = date("%Y-%m-%d %H:%M:%S")
        vahennys = vahennys - 1
        toimitettu = toimitettu + 1
      end
    end
  end

  if toimitettu > 0 then
    NS.Tulosta(("%s sai %d itemia. Jonossa %d."):format(
      nyt, toimitettu, #NS.OdottavatKaupat()))
    if NS.PaivitaNakyma then NS.PaivitaNakyma("kauppa") end
  end
end

--------------------------------------------------------------------------
-- Tapahtumat
--------------------------------------------------------------------------

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("TRADE_SHOW")
kehys:RegisterEvent("TRADE_CLOSED")

kehys:SetScript("OnEvent", function(_, tapahtuma)
  if tapahtuma == "TRADE_SHOW" then
    if NS.db.taytaKauppa == false then return end

    -- Pieni viive: kauppaikkuna ei ole heti valmis, eika vastapuolen nimi
    -- ole viela luettavissa samalla kehyksella.
    C_Timer.After(0.2, tayta)

  elseif tapahtuma == "TRADE_CLOSED" then
    -- Laukut paivittyvat vasta hetken kuluttua kaupan jalkeen.
    C_Timer.After(1, tarkistaTulos)
  end
end)
