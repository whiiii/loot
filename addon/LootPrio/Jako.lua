--[[
  LootPrio — jakosessio.

  Sessio on sama kaikilla: lootmaster avaa sen, ja jokaisen raidilaisen
  addon rakentaa siita saman nakyman. Vastaukset lahetetaan raidille,
  joten jokainen nakee mita muut vastasivat.

  Avoimuus on tarkoituksellista. Kun kaikki nakevat samat perusteet ja
  samat numerot, lootmasterin paatosta voi seurata - eika kenenkaan
  tarvitse uskoa sanaan.
]]

local ADDON, NS = ...

--- Vastausvaihtoehdot. Jarjestysluku ratkaisee listauksen: pienin ylos.
NS.VASTAUKSET = {
  { koodi = "prio", nimi = "LootPrio",  jarjestys = 1, vari = "|cffc9a227" },
  { koodi = "main", nimi = "Main spec", jarjestys = 2, vari = "|cff8fd17a" },
  { koodi = "off",  nimi = "Off spec",  jarjestys = 3, vari = "|cff7fb3cc" },
  { koodi = "muu",  nimi = "Muu",       jarjestys = 4, vari = "|cffb0a99a" },
  { koodi = "pass", nimi = "Pass",      jarjestys = 5, vari = "|cff6b7278" },
}

NS.VASTAUS = {}
for _, v in ipairs(NS.VASTAUKSET) do NS.VASTAUS[v.koodi] = v end

--- Sessio. Sama rakenne kaikilla, vain slot on pelkastaan lootmasterilla
--- (sita tarvitaan lootin antamiseen, eika sita laheteta muille).
NS.sessio = nil

--------------------------------------------------------------------------
-- Session avaus
--------------------------------------------------------------------------

local function uusiSessio(id, lootmaster, nakyvyys)
  return {
    id = id,
    lootmaster = lootmaster,
    -- "raid" tai "officers". Lootmasterin asetus matkaa session mukana,
    -- jottei jokainen paata itse mita nakee.
    nakyvyys = nakyvyys or "raid",
    alkoi = GetTime(),
    itemit = {},
    omaVastaus = {},
    valittu = 1,
  }
end

--- Naytetaanko muiden vastaukset talle pelaajalle.
---
--- Tama on nakyvyysasetus, ei salaisuus: tiedot kulkevat raidikanavalla
--- ja ovat jokaisen koneella joka tapauksessa. Asetus ratkaisee vain
--- naytetaanko ne - muokattu addon nakisi ne silti.
function NS.NaytaKaikkiVastaukset()
  local s = NS.sessio
  if not s then return true end
  if s.nakyvyys == "raid" then return true end
  return NS.OnOfficer()
end

--- Onko nimetty pelaaja taman jaon lootmaster.
---
--- Tata vasten tarkistetaan jokainen jakoon vaikuttava teko: arvonta,
--- antaminen, peruminen ja lopetus. Officer-oikeus riittaa jaon
--- avaamiseen, mutta ei enaa sen jalkeen - muuten toinen apulainen voisi
--- antaa itemin kesken toisen jakoa, ja nappien piilottaminen hanelta
--- olisi vain nakyma eika saanto.
function NS.OnJakaja(nimi)
  local s = NS.sessio
  if not s then return false end
  return s.lootmaster == (nimi or NS.OmaNimi())
end

--- Onko jako kaynnissa ja jollakin toisella.
---
--- Lootmaster on se joka avasi jaon. Mitaan erillista asetusta ei ole,
--- koska se olisi yksi asia lisaa jonka voi unohtaa paivittaa - ja se
--- paattyisi riitaan siita kenen nimi siella lukee. Avaaminen on teko, ja
--- teko riittaa.
function NS.JakoVarattu()
  local s = NS.sessio
  if not s or s.testi then return nil end
  if s.lootmaster == NS.OmaNimi() then return nil end

  -- Jaettu jako ei varaa mitaan: jaljella ei ole paatettavaa.
  if #NS.AvoimetItemit() == 0 then return nil end

  -- Linjoilta pudonnut lootmaster ei varaa jakoa. Muuten yksi katkennut
  -- yhteys lukitsisi koko illan jaon, eika sita saisi auki muuten kuin
  -- haltuunotolla - ja haltuunotto vaatii johtajan, joka ei valttamatta
  -- ole paikalla juuri silloin.
  if not NS.Paikalla(s.lootmaster) then return nil end

  return s.lootmaster
end

--- Ottaa kesken jaaneen jaon haltuun.
---
--- Vain raidin johtaja. Lootmaster voi pudota linjoilta kesken jaon, ja
--- ilman tata koko raidi jaisi odottamaan hanen paluutaan. Apulaisille
--- tata ei anneta: kaksi apulaista voisi ottaa jaon vuorotellen toisiltaan.
function NS.OtaHaltuun()
  local s = NS.sessio
  if not s then return false end

  if not NS.OnJohtaja() then
    NS.Tulosta("vain raidin johtaja voi ottaa jaon haltuunsa.")
    return false
  end

  if s.lootmaster == NS.OmaNimi() then return false end

  local vanha = s.lootmaster
  s.lootmaster = NS.OmaNimi()
  NS.Comm.Laheta("HALTUUN", s.id)
  NS.Tulosta(("jako otettu haltuun: %s -> sina."):format(vanha or "?"))

  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
  return true
end

function NS.JakoSiirtyi(sessioId, uusi)
  local s = NS.sessio
  if not s or s.id ~= sessioId then return end

  s.lootmaster = uusi
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Lootmaster avaa session valituista itemeista.
function NS.AvaaSessio(valitut, testi)
  if #valitut == 0 then
    NS.Tulosta("ei valittuja itemeita.")
    return false
  end

  -- Kaksi samanaikaista jakoa tarkoittaisi kahta eri vastauslistaa samoille
  -- ihmisille, ja jalkimmainen pyyhkisi ensimmaisen.
  local varaaja = not testi and NS.JakoVarattu()
  if varaaja then
    NS.Tulosta(("%s on jo jakamassa. Odota etta jako paattyy."):format(varaaja))
    return false
  end

  NS.sessio = uusiSessio(tostring(math.random(100000, 999999)),
    NS.OmaNimi(), NS.db.rollienNakyvyys)
  NS.sessio.testi = testi

  for i, loot in ipairs(valitut) do
    NS.sessio.itemit[i] = {
      indeksi = i,
      itemId = loot.itemId,
      linkki = loot.linkki,
      nimi = loot.nimi,
      laatu = loot.laatu,
      testi = loot.testi or testi,
      jaettu = false,
      saaja = nil,
      vastaukset = {},
    }
  end

  NS.sessio.valittu = 1

  if not testi then NS.LahetaSessio() end

  -- Jakajalle koko nakyma, ja aanestysikkuna sen rinnalle: lootmaster
  -- vastaa itsekin.
  NS.Avaa("loot")
  if NS.AvaaAanestys then NS.AvaaAanestys() end
  return true
end

--- Jakamatta olevat itemit. Jaetut katoavat valilehdista ja jaavat
--- historiaan, joten lista lyhenee sita mukaa kun jako etenee.
function NS.AvoimetItemit()
  local lista = {}
  for _, item in pairs(NS.sessio and NS.sessio.itemit or {}) do
    if not item.jaettu then lista[#lista + 1] = item end
  end
  table.sort(lista, function(a, b) return a.indeksi < b.indeksi end)
  return lista
end

--- Lahettaa session raidille.
---
--- Item-id:t yhdessa viestissa niin pitkalle kuin ne mahtuvat. Viestin
--- raja on 255 tavua, joten pitka lista pilkotaan osiin.
function NS.LahetaSessio()
  if not NS.sessio then return end

  local osat, pituus = {}, 0
  local function tyhjenna()
    if #osat > 0 then
      NS.Comm.Laheta("SESSIO", ("%s %s %s"):format(
        NS.sessio.id, NS.sessio.nakyvyys, table.concat(osat, ",")))
      osat, pituus = {}, 0
    end
  end

  for _, item in ipairs(NS.sessio.itemit) do
    local pala = item.indeksi .. ":" .. item.itemId
    if pituus + #pala + 1 > 200 then tyhjenna() end
    osat[#osat + 1] = pala
    pituus = pituus + #pala + 1
  end
  tyhjenna()
end

--- Lootmaster avasi session: rakennetaan sama nakyma tanne.
function NS.SaapuvaSessio(sessioId, nakyvyys, itemit, lahettaja)
  -- Sama sessio voi tulla useassa osassa, jolloin itemit lisataan.
  if not NS.sessio or NS.sessio.id ~= sessioId then
    NS.sessio = uusiSessio(sessioId, lahettaja, nakyvyys)
  end

  for _, rivi in ipairs(itemit) do
    if not NS.sessio.itemit[rivi.indeksi] then
      NS.sessio.itemit[rivi.indeksi] = {
        indeksi = rivi.indeksi,
        itemId = rivi.itemId,
        jaettu = false,
        vastaukset = {},
      }
    end
  end

  -- Raidaajalle vain aanestysikkuna. Paaikkuna on lootmasterin tyokalu:
  -- sen valikot ja listat ovat bossin jalkeen pelkka hidaste sille jonka
  -- koko tehtava on painaa yhta nappia. Paaikkunan saa auki napista.
  if NS.AvaaAanestys then NS.AvaaAanestys() end
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Sulkee vastaukset. Itemit jaavat jaettaviksi, mutta uusia vastauksia
--- ei oteta vastaan - muuten lista muuttuu kesken paatoksen.
function NS.SuljeVastaukset()
  local s = NS.sessio
  if not s or s.suljettu then return false end
  if not s.testi and not NS.OnJakaja() then return false end

  s.suljettu = true
  if not s.testi then NS.Comm.Laheta("SULJE", s.id) end

  if NS.SuljeAanestys then NS.SuljeAanestys() end
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
  return true
end

function NS.VastauksetSuljettu(sessioId)
  local s = NS.sessio
  if not s or s.id ~= sessioId then return end

  s.suljettu = true

  -- Aanestysikkuna pois: nappi joka ei tee mitaan on huonompi kuin ei
  -- nappia lainkaan.
  if NS.SuljeAanestys then NS.SuljeAanestys() end
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Montako sekuntia sessio on ollut auki.
function NS.SessionKesto()
  if not NS.sessio then return 0 end
  return math.floor(GetTime() - (NS.sessio.alkoi or GetTime()))
end

--- Session jaot pelaajittain, yhteenvetoa varten.
local function sessionJaot()
  local perPelaaja, jarjestys = {}, {}

  -- pairs eika ipairs: sessio voi saapua useassa osassa, joten indeksit
  -- eivat ole valttamatta jonossa.
  for _, item in pairs(NS.sessio and NS.sessio.itemit or {}) do
    if item.jaettu and item.saaja then
      if not perPelaaja[item.saaja] then
        perPelaaja[item.saaja] = {}
        jarjestys[#jarjestys + 1] = item.saaja
      end

      local nimi = item.nimi
      if not nimi and item.itemId then nimi = GetItemInfo(item.itemId) end

      local rivi = perPelaaja[item.saaja]
      rivi[#rivi + 1] = nimi or ("item " .. tostring(item.itemId))
    end
  end

  table.sort(jarjestys)
  return perPelaaja, jarjestys
end

--- Tiivis yhteenveto raidichattiin jaon paatteeksi.
---
--- Yksi rivi per pelaaja eika per item: viestin raja on 255 tavua, ja
--- lyhyt lista luetaan, pitka ei.
function NS.LahetaYhteenveto()
  if not NS.sessio or NS.sessio.testi then return end
  if not IsInGroup() then return end

  local perPelaaja, jarjestys = sessionJaot()
  if #jarjestys == 0 then return end

  local kanava = IsInRaid() and "RAID" or "PARTY"
  SendChatMessage("LootPrio - jaetut itemit:", kanava)

  for _, nimi in ipairs(jarjestys) do
    local viesti = nimi .. ": " .. table.concat(perPelaaja[nimi], ", ")

    -- Rajan ylittava rivi katkaistaan: pelin oma katkaisu jattaisi
    -- puolikkaan item-nimen eika kerro etta jotain jai pois.
    if #viesti > 230 then viesti = viesti:sub(1, 227) .. "..." end
    SendChatMessage(viesti, kanava)
  end
end

function NS.PaataSessio(yhteenveto)
  if not NS.sessio then return end

  -- Lopettaa se joka jakaa. Muuten toinen apulainen voisi sulkea jaon
  -- kesken, ja vastaamatta jaaneet itemit katoaisivat valilehdista.
  if not NS.sessio.testi and not NS.OnJakaja() then
    NS.Tulosta(("vain jaon avaaja voi paattaa jaon. Jakaa: %s"):format(
      NS.sessio.lootmaster or "?"))
    return
  end

  if yhteenveto then NS.LahetaYhteenveto() end

  NS.Comm.Laheta("LOPPU", NS.sessio.id)
  NS.sessio = nil

  if NS.SuljeAanestys then NS.SuljeAanestys() end
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

function NS.SessioPaattyi(sessioId)
  if NS.sessio and NS.sessio.id == sessioId then
    NS.sessio = nil

    if NS.SuljeAanestys then NS.SuljeAanestys() end
    if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
  end
end

--------------------------------------------------------------------------
-- Vastaukset
--------------------------------------------------------------------------

--- Lahettaa oman vastauksen raidille.
---
--- Raidikanavalle eika kuiskauksena: jokaisen on tarkoitus nahda mita
--- muut vastasivat, muuten lista olisi vain lootmasterin tiedossa.
function NS.Vastaa(indeksi, koodi)
  local s = NS.sessio
  if not s or s.suljettu then return end
  if not NS.VASTAUS[koodi] then return end

  local item = s.itemit[indeksi]
  if not item or item.jaettu then return end

  s.omaVastaus[indeksi] = koodi
  NS.Comm.Laheta("VASTAUS", ("%s %d %s"):format(s.id, indeksi, koodi))

  -- Oma vastaus kirjataan heti: omaa viestia ei saada takaisin.
  NS.KirjaaVastaus(s.id, indeksi, NS.OmaNimi(), koodi)
end

--- Kirjaa yhden pelaajan vastauksen.
---
--- Arvonnan tekee vain lootmaster ja lahettaa tuloksen muille. Jos
--- jokainen arpoisi itse, numerot eroaisivat koneesta toiseen eika
--- kukaan voisi tarkistaa mitaan.
function NS.KirjaaVastaus(sessioId, indeksi, pelaaja, koodi, luku)
  local s = NS.sessio
  if not s or s.id ~= sessioId then return end
  if s.suljettu then return end
  if not NS.VASTAUS[koodi] then return end

  local item = s.itemit[indeksi]
  if not item or item.jaettu then return end

  -- Onko item oikeasti kyseisen pelaajan profiilissa.
  --
  -- Vastaus tulee pelaajan omalta koneelta, joten siihen ei voi luottaa.
  -- Tarkistus tehdaan jokaisella koneella omia tuotuja profiileja vasten,
  -- joten vaite nakyy vaarana kaikille joilla data on.
  local prioOk = false
  local valinnat = NS.db.profiilit[pelaaja]
  if valinnat then
    for _, id in pairs(valinnat) do
      if id == item.itemId then prioOk = true break end
    end
  end

  item.vastaukset[pelaaja] = {
    koodi = koodi,
    luku = luku,
    prioOk = prioOk,
  }

  -- Lootmaster arpoo ja kertoo tuloksen, jotta kaikilla on sama numero.
  if NS.sessio.lootmaster == NS.OmaNimi() and koodi ~= "pass" and not luku then
    item.vastaukset[pelaaja].luku = math.random(1, 100)
    NS.Comm.Laheta("ARPA", ("%s %d %s %d"):format(
      sessioId, indeksi, pelaaja, item.vastaukset[pelaaja].luku))
  end

  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Lootmasterin lahettama arvonta yhdelle vastaukselle.
function NS.KirjaaArpa(sessioId, indeksi, pelaaja, luku)
  local s = NS.sessio
  if not s or s.id ~= sessioId then return end

  local item = s.itemit[indeksi]
  if not item then return end

  local v = item.vastaukset[pelaaja]
  if v then v.luku = luku end

  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Yhden itemin vastaukset listana, parhaasta alkaen.
---
--- Jarjestys: vastaustyyppi ensin, sitten arvonta. Ylimpana on se jolla
--- on vahvin peruste, ei se jolla on suurin numero.
function NS.ItemienVastaukset(item)
  local lista = {}

  for pelaaja, v in pairs(item.vastaukset) do
    lista[#lista + 1] = {
      nimi = pelaaja,
      koodi = v.koodi,
      luku = v.luku,
      prioOk = v.prioOk,
      saatu = NS.SaatuMaara(pelaaja),
      jarjestys = NS.VASTAUS[v.koodi].jarjestys,
    }
  end

  -- Oletusjarjestys on peruste ensin ja arvonta vasta sen jalkeen: rolli
  -- ratkaisee vain tasatilanteen. Lajittelu vaihdettavissa otsikoista.
  local kentta = NS.lajittelu or "jarjestys"
  local nouseva = NS.lajitteluNouseva
  if nouseva == nil then nouseva = true end

  table.sort(lista, function(a, b)
    local x, z = a[kentta], b[kentta]

    if x ~= z then
      if type(x) == "number" or type(z) == "number" then
        x, z = x or 0, z or 0
        if nouseva then return x < z else return x > z end
      end
      if nouseva then return tostring(x) < tostring(z) end
      return tostring(x) > tostring(z)
    end

    -- Tasatilanne ratkaistaan aina samalla tavalla, jotta jarjestys ei
    -- vaihtele piirrosta toiseen.
    if a.jarjestys ~= b.jarjestys then return a.jarjestys < b.jarjestys end
    if (a.luku or 0) ~= (b.luku or 0) then return (a.luku or 0) > (b.luku or 0) end
    return a.nimi < b.nimi
  end)

  return lista
end

--- Ketka raidissa eivat ole vastanneet.
function NS.Vastaamatta(item)
  local puuttuu = {}
  for nimi, online in pairs(NS.RaidinJasenet()) do
    if online and not item.vastaukset[nimi] then
      puuttuu[#puuttuu + 1] = nimi
    end
  end
  table.sort(puuttuu)
  return puuttuu
end

--- Onko item omassa profiilissa. Ratkaisee onko LootPrio-nappi kaytossa.
function NS.OmassaProfiilissa(itemId)
  local omat = NS.db.profiilit[NS.OmaNimi()]
  if not omat then return false end

  for _, id in pairs(omat) do
    if id == itemId then return true end
  end
  return false
end

--------------------------------------------------------------------------
-- Jaetuksi merkitseminen
--------------------------------------------------------------------------

--- Kirjaa jaon kaikilla koneilla.
---
--- Lootmaster lahettaa tiedon, jotta jokaisen saatujen itemien laskuri
--- pysyy ajan tasalla - ei vain sen joka jakoi.
function NS.KirjaaJako(sessioId, indeksi, saaja, koodi, luku)
  local s = NS.sessio
  if not s or s.id ~= sessioId then return end

  local item = s.itemit[indeksi]
  if not item or item.jaettu then return end

  local v = item.vastaukset[saaja]
  koodi = koodi or (v and v.koodi)
  luku = luku or (v and v.luku)

  item.jaettu = true
  item.saaja = saaja
  item.saajanKoodi = koodi

  -- Peruste talletetaan numeron rinnalle: "kuka sai ja milla napilla" on
  -- se mita historiasta myohemmin kysytaan.
  item.historiaId = NS.LisaaHistoriaan(item.itemId, saaja, luku, koodi, item.nimi)

  -- Viimeisin jako muistiin perumista varten. Assign-napit ovat pienia ja
  -- lista tiheaa, joten harhaklikkaus ei saa olla pysyva.
  s.viimeisin = indeksi

  -- Valittuna oleva valilehti katoaa jaon myota, joten siirrytaan
  -- seuraavaan avoimeen.
  if s.valittu == indeksi then
    local avoimet = NS.AvoimetItemit()
    s.valittu = avoimet[1] and avoimet[1].indeksi or nil
  end

  -- Jaettu item katoaa myos aanestysikkunasta: siihen ei enaa vastata.
  if NS.PaivitaAanestys then NS.PaivitaAanestys() end
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Peruu yhden jaon: item palaa valilehtiin ja historiarivi haviaa.
---
--- Vain viimeisin jako. Pidempi peruuttaminen vaatisi tiedon siita mika
--- jarjestys oli, ja raidin keskella se olisi enemman sekaannuksen lahde
--- kuin apu.
function NS.PeruJako(indeksi, lahettaja)
  local s = NS.sessio
  if not s then return false end

  indeksi = indeksi or s.viimeisin
  if not indeksi then return false end

  local item = s.itemit[indeksi]
  if not item or not item.jaettu then return false end

  -- Paikallinen peruminen vaatii officer-oikeudet; verkosta tuleva on jo
  -- tarkistettu lahettajan arvosta.
  if not lahettaja and not item.testi and not NS.OnJakaja() then
    NS.Tulosta("vain jaon avaaja voi perua jaon.")
    return false
  end

  local saaja = item.saaja

  NS.PoistaHistoriasta(item.historiaId)
  if NS.PoistaKaupasta then NS.PoistaKaupasta(item.historiaId) end

  item.jaettu = false
  item.saaja = nil
  item.saajanKoodi = nil
  item.historiaId = nil

  if s.viimeisin == indeksi then s.viimeisin = nil end
  s.valittu = indeksi

  if not lahettaja and not item.testi then
    NS.Comm.Laheta("PERU", ("%s %d"):format(s.id, indeksi))
  end

  NS.Tulosta(("jako peruttu: %s -> %s"):format(
    item.nimi or ("item " .. tostring(item.itemId)), saaja or "?"))

  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
  return true
end
