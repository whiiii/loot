--[[
  LootPrio — profiilien tuonti ja haku.

  Muoto tulee sivustolta sellaisenaan:

    LOOTPRIO1
    RAID=Molten Core
    TIME=2026-10-10 07:05:32
    SLOTS=head,neck,shoulder,...
    P=Betonimylly|head:18817,neck:18814,...

  Rivipohjainen muoto on tassa JSONia parempi siita yksinkertaisesta
  syysta, etta Luassa sen lukee kolmella gmatch-kutsulla. JSON vaatisi
  oman jasentimen tai kirjaston, eika se toisi mitaan lisaa.
]]

local ADDON, NS = ...

--- Jasentaa viennin. Palauttaa taulukon tai nil ja virheen.
function NS.Jasenna(teksti)
  if type(teksti) ~= "string" or teksti == "" then
    return nil, "Teksti puuttuu."
  end

  -- Windowsin rivinvaihdot pois, jotta vertailut osuvat.
  teksti = teksti:gsub("\r", "")

  local eka = teksti:match("^%s*(%S+)")
  if eka ~= "LOOTPRIO1" then
    return nil, "Tuntematon muoto. Odotettiin LOOTPRIO1."
  end

  local tulos = {
    raidinNimi = teksti:match("\nRAID=([^\n]*)") or "?",
    aika = teksti:match("\nTIME=([^\n]*)") or "?",
    profiilit = {},
    hahmoja = 0,
  }

  for rivi in teksti:gmatch("P=([^\n]+)") do
    local hahmo, valinnat = rivi:match("^([^|]+)|(.*)$")

    if hahmo and hahmo ~= "" then
      hahmo = hahmo:match("^%s*(.-)%s*$")
      local omat = {}

      for paikka, itemId in (valinnat or ""):gmatch("([%w_]+):(%d+)") do
        omat[paikka] = tonumber(itemId)
      end

      tulos.profiilit[hahmo] = omat
      tulos.hahmoja = tulos.hahmoja + 1
    end
  end

  if tulos.hahmoja == 0 then
    return nil, "Yhtaan profiilia ei loytynyt."
  end

  return tulos
end

--- Tuo tekstin tietokantaan. Korvaa vanhan kokonaan.
---
--- Korvaa eika yhdista: vienti on sivuston koko totuus kyseisesta
--- raidista, ja yhdistaminen jattaisi poistetut valinnat voimaan.
function NS.Tuo(teksti)
  local data, virhe = NS.Jasenna(teksti)
  if not data then return nil, virhe end

  NS.db.profiilit = data.profiilit
  NS.db.raidinNimi = data.raidinNimi
  NS.db.tuotu = date("%Y-%m-%d %H:%M")

  return data
end

--- Ketka ovat varanneet taman itemin.
---
--- Palauttaa listan { nimi = , paikka = }. Jarjestys on nimen mukaan,
--- jotta sama tilanne nayttaa aina samalta.
function NS.KukaHaluaa(itemId)
  local tulos = {}
  if not itemId then return tulos end

  for hahmo, valinnat in pairs(NS.db.profiilit) do
    for paikka, id in pairs(valinnat) do
      if id == itemId then
        tulos[#tulos + 1] = { nimi = hahmo, paikka = paikka }
        break
      end
    end
  end

  table.sort(tulos, function(a, b) return a.nimi < b.nimi end)
  return tulos
end

--- Sama kuin KukaHaluaa, mutta vain raidissa paikalla olevat.
---
--- Lootmasteria ei kiinnosta se, etta itemin on varannut joku joka ei ole
--- paikalla - lista olisi vain pidempi ilman etta siita on apua.
function NS.KukaHaluaaPaikalla(itemId)
  local kaikki = NS.KukaHaluaa(itemId)
  local raidissa = NS.RaidinJasenet()
  local tulos = {}

  for _, rivi in ipairs(kaikki) do
    if raidissa[rivi.nimi] then
      tulos[#tulos + 1] = rivi
    end
  end

  return tulos
end

function NS.TulostaProfiilit()
  local kpl = 0
  for _ in pairs(NS.db.profiilit) do kpl = kpl + 1 end

  if kpl == 0 then
    NS.Tulosta("ei tuotuja profiileja. /lp tuo")
    return
  end

  NS.Tulosta(("%s — %d hahmoa, tuotu %s"):format(
    NS.db.raidinNimi or "?", kpl, NS.db.tuotu or "?"))

  local nimet = {}
  for hahmo in pairs(NS.db.profiilit) do nimet[#nimet + 1] = hahmo end
  table.sort(nimet)

  for _, hahmo in ipairs(nimet) do
    local n = 0
    for _ in pairs(NS.db.profiilit[hahmo]) do n = n + 1 end
    print(("  %s — %d valintaa"):format(hahmo, n))
  end
end
