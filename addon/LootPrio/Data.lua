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
    saadut = {},
    aliakset = {},
    officerit = {},
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

  -- Saadut itemit sivuston koko historiasta. Vapaaehtoinen rivi: vanha
  -- vienti ei sisalla naita, eika se ole syy hylata tuontia.
  for rivi in teksti:gmatch("S=([^\n]+)") do
    local hahmo, maara = rivi:match("^([^|]+)|(%d+)$")
    if hahmo then
      tulos.saadut[hahmo:match("^%s*(.-)%s*$")] = tonumber(maara)
    end
  end

  -- Hahmon muut kirjoitusasut. Sivusto ei tieda missa muodossa peli antaa
  -- nimen, joten se lahettaa vaihtoehdot ja addon valitsee osuvan.
  for rivi in teksti:gmatch("A=([^\n]+)") do
    local hahmo, muut = rivi:match("^([^|]+)|(.*)$")

    if hahmo then
      hahmo = hahmo:match("^%s*(.-)%s*$")

      for alias in (muut or ""):gmatch("[^,]+") do
        alias = alias:match("^%s*(.-)%s*$")
        if alias ~= "" then
          tulos.aliakset[alias:lower()] = hahmo
        end
      end
    end
  end

  -- Killan officerit. Raidin arvo yksin ei riita jaon avaamiseen, koska
  -- assist annetaan usein markkereita varten eika loottia.
  local officerRivi = teksti:match("\nO=([^\n]*)")
  if officerRivi then
    for nimi in officerRivi:gmatch("[^,]+") do
      nimi = nimi:match("^%s*(.-)%s*$")
      if nimi ~= "" then tulos.officerit[nimi] = true end
    end
  end

  if tulos.hahmoja == 0 then
    return nil, "Yhtaan profiilia ei loytynyt."
  end

  return tulos
end

--- Pelin antama nimi profiilien nimeksi.
---
--- Kaikki sisainen vertailu tehdaan profiilin nimella. Muunnos tapahtuu
--- siella missa pelin nimi tulee addoniin - roosterista, viestin
--- lahettajasta tai kaupan vastapuolesta - jottei samasta pelaajasta ole
--- kahta eri nimea missaan muualla.
function NS.Nimi(peliNimi)
  if not peliNimi or peliNimi == "" then return peliNimi end

  -- Realm pois: raidikanavalta tuleva nimi voi olla "Nimi-Realm".
  peliNimi = peliNimi:match("^[^-]+") or peliNimi

  -- Tapahtuma voi osua ennen tallennuksen latautumista.
  if not NS.db then return peliNimi end

  if NS.db.profiilit[peliNimi] then return peliNimi end

  local kanoninen = NS.db.aliakset and NS.db.aliakset[peliNimi:lower()]
  return kanoninen or peliNimi
end

--- Tuo tekstin tietokantaan. Korvaa vanhan kokonaan.
---
--- Korvaa eika yhdista: vienti on sivuston koko totuus kyseisesta
--- raidista, ja yhdistaminen jattaisi poistetut valinnat voimaan.
function NS.Tuo(teksti)
  local data, virhe = NS.Jasenna(teksti)
  if not data then return nil, virhe end

  NS.db.profiilit = data.profiilit
  NS.db.saadut = data.saadut
  NS.db.aliakset = data.aliakset
  NS.db.officerit = data.officerit
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

--- Tuodut hahmot aakkosjarjestyksessa, valintojen maaran kanssa.
function NS.Jasenet()
  local lista = {}

  for hahmo, valinnat in pairs(NS.db.profiilit) do
    local n = 0
    for _ in pairs(valinnat) do n = n + 1 end
    lista[#lista + 1] = { nimi = hahmo, valintoja = n }
  end

  table.sort(lista, function(a, b) return a.nimi < b.nimi end)
  return lista
end

--- Montako itemia kyseinen hahmo on jo saanut.
---
--- Sivuston luku ja taman koneen kirjaamat jaot yhteen: sivusto tietaa
--- kaiken mika on sille viety, ja paikallinen historia sen mika on jaettu
--- viennin jalkeen. Kun historia viedaan sivustolle ja profiilit tuodaan
--- uudelleen, luku siirtyy S-riveille ja paikallinen historia tyhjennetaan -
--- siksi nama eivat kahdenna toisiaan.
function NS.SaatuMaara(hahmo)
  local n = NS.db.saadut[hahmo] or 0

  for _, rivi in ipairs(NS.db.historia) do
    if rivi.nimi == hahmo then n = n + 1 end
  end

  return n
end

--- Paljonko luvusta on sivuston tietoa. Nakymassa erotteluna, jotta
--- lootmaster nakee onko luku oikeasti killan historia vai vain taman illan.
function NS.SaatuSivustolta(hahmo)
  return NS.db.saadut[hahmo] or 0
end

--- Kirjaa jaetun lootin historiaan.
---
--- Aikaleima talletetaan tekstina samassa muodossa kuin sivusto kayttaa,
--- jotta tuonti ei joudu arvailemaan muotoa.
--- Palauttaa rivin tunnisteen, jolla jako voidaan perua.
function NS.LisaaHistoriaan(itemId, nimi, luku, koodi, itemNimi)
  -- Juokseva tunniste eika indeksi: indeksi siirtyy kun rivi poistetaan,
  -- ja peruminen osuisi silloin vaaraan riviin.
  local id = NS.db.historiaSeuraavaId or 1
  NS.db.historiaSeuraavaId = id + 1

  -- Instanssi ja koko kirjataan jaon hetkella eika viennissa: sama
  -- historia voi sisaltaa kaksi iltaa, jos vienti unohtui valilla.
  local alue, koko = NS.Instanssi()

  NS.db.historia[#NS.db.historia + 1] = {
    id = id,
    itemId = itemId,
    nimi = nimi,
    luku = luku,
    alue = alue,
    koko = koko,
    -- Peruste talletetaan numeron rinnalle: "kuka sai ja milla napilla"
    -- on se mita historiasta myohemmin kysytaan.
    koodi = koodi,
    itemNimi = itemNimi,
    aika = date("%Y-%m-%d %H:%M:%S"),
    raidi = NS.db.raidinNimi,
  }

  return id
end

--- Poistaa historiarivin tunnisteella. Kaytossa vain jaon perumisessa.
function NS.PoistaHistoriasta(id)
  if not id then return false end

  for i, r in ipairs(NS.db.historia) do
    if r.id == id then
      table.remove(NS.db.historia, i)
      return true
    end
  end

  return false
end

--- Historia tekstina sivustolle vietavaksi.
---
--- Sama rivipohjainen muoto kuin tuonnissa, vastakkaiseen suuntaan.
function NS.HistoriaTeksti()
  -- Otsikon instanssi ja koko: ensisijaisesti se missa ollaan nyt, muuten
  -- viimeisimman jaon paikka. Sivusto nimeaa lokin naiden perusteella.
  local alue, koko = NS.Instanssi()

  if not alue then
    for i = #NS.db.historia, 1, -1 do
      if NS.db.historia[i].alue then
        alue = NS.db.historia[i].alue
        koko = NS.db.historia[i].koko or koko
        break
      end
    end
  end

  local rivit = {
    "LOOTHIST1",
    "RAID=" .. (NS.db.raidinNimi or "?"),
    "TIME=" .. date("%Y-%m-%d %H:%M:%S"),
  }

  if alue then rivit[#rivit + 1] = "ZONE=" .. alue end
  if koko and koko > 0 then rivit[#rivit + 1] = "SIZE=" .. koko end

  for _, r in ipairs(NS.db.historia) do
    -- Instanssi myos rivikohtaisesti: jos sama vienti sisaltaa kaksi
    -- iltaa, otsikko voi kertoa vain toisen.
    rivit[#rivit + 1] = ("L=%d|%s|%s|%s|%s|%s"):format(
      r.itemId, r.nimi, r.aika,
      r.luku and tostring(r.luku) or "-",
      r.koodi or "-",
      r.alue or "-")
  end

  return table.concat(rivit, "\n")
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
