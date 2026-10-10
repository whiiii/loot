--[[
  LootPrio — jakosessio.

  Lootmaster avaa session, jolloin jokaisen raidilaisen ruudulle aukeaa
  ikkuna jossa itemiin vastataan yhdella napilla. Vastaukset palaavat
  lootmasterille, joka nakee kaikki yhdessa listassa ja jakaa sen
  perusteella.

  Nain myos item jota kukaan ei ole varannut saadaan jaettua: profiili on
  yksi vastausvaihtoehto neljasta, ei ainoa peruste.
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

-- Lootmasterin sessio. Vastaanottajan oma sessio on NS.omaSessio.
NS.sessio = nil
NS.omaSessio = nil

--------------------------------------------------------------------------
-- Lootmaster: session avaus
--------------------------------------------------------------------------

--- Avaa jakosession loottiruudun sisallosta.
function NS.AvaaSessio(lootit)
  if #lootit == 0 then
    NS.Tulosta("ei jaettavaa loottia.")
    return false
  end

  NS.sessio = {
    id = tostring(math.random(100000, 999999)),
    alkoi = GetTime(),
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
      testi = loot.testi,
      jaettu = false,
      vastaukset = {},   -- [pelaaja] = { koodi, luku, prioOk }
    }
  end

  NS.LahetaSessio()
  return true
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
      NS.Comm.Laheta("SESSIO", NS.sessio.id .. " " .. table.concat(osat, ","))
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

--- Paattaa session ja kertoo siita muille.
function NS.PaataSessio()
  if not NS.sessio then return end
  NS.Comm.Laheta("LOPPU", NS.sessio.id)
  NS.sessio = nil
  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--------------------------------------------------------------------------
-- Lootmaster: vastausten vastaanotto
--------------------------------------------------------------------------

--- Kirjaa yhden pelaajan vastauksen.
---
--- Arvonta tehdaan vasta tassa: vain vastanneet osallistuvat, eika
--- numeroita tarvitse arpoa niille joita item ei kiinnosta.
---
--- prioOk kertoo onko item oikeasti kyseisen pelaajan profiilissa.
--- Vastaus tulee pelaajan omalta koneelta, joten siihen ei voi luottaa -
--- mutta lootmasterilla on kaikkien profiilit, joten han voi tarkistaa.
function NS.KirjaaVastaus(sessioId, indeksi, pelaaja, koodi)
  if not NS.sessio or NS.sessio.id ~= sessioId then return end
  if not NS.VASTAUS[koodi] then return end

  local item = NS.sessio.itemit[indeksi]
  if not item or item.jaettu then return end

  local prioOk = false
  local valinnat = NS.db.profiilit[pelaaja]
  if valinnat then
    for _, id in pairs(valinnat) do
      if id == item.itemId then prioOk = true break end
    end
  end

  item.vastaukset[pelaaja] = {
    koodi = koodi,
    luku = (koodi ~= "pass") and math.random(1, 100) or nil,
    prioOk = prioOk,
  }

  if NS.PaivitaNakyma then NS.PaivitaNakyma("loot") end
end

--- Yhden itemin vastaukset listana, parhaasta alkaen.
---
--- Jarjestys: vastaustyyppi ensin, sitten arvonta. Lootmaster nakee
--- ylimpana sen jolla on vahvin peruste, ei suurin numero.
function NS.ItemienVastaukset(item)
  local lista = {}

  for pelaaja, v in pairs(item.vastaukset) do
    lista[#lista + 1] = {
      nimi = pelaaja,
      koodi = v.koodi,
      luku = v.luku,
      prioOk = v.prioOk,
      jarjestys = NS.VASTAUS[v.koodi].jarjestys,
    }
  end

  table.sort(lista, function(a, b)
    if a.jarjestys ~= b.jarjestys then return a.jarjestys < b.jarjestys end
    if (a.luku or 0) ~= (b.luku or 0) then return (a.luku or 0) > (b.luku or 0) end
    return a.nimi < b.nimi
  end)

  return lista
end

--- Ketka raidissa eivat ole vastanneet.
---
--- Tama on lootmasterille yhta tarkea tieto kuin vastaukset: odottaako
--- viela vai onko jaljella vain ne joilla ei ole addonia.
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

--------------------------------------------------------------------------
-- Raideri: session vastaanotto ja vastaaminen
--------------------------------------------------------------------------

--- Lootmaster avasi session. Avataan vastausikkuna.
function NS.SaapuvaSessio(sessioId, itemit, lahettaja)
  -- Sama sessio voi tulla useassa osassa, jolloin itemit lisataan.
  if not NS.omaSessio or NS.omaSessio.id ~= sessioId then
    NS.omaSessio = {
      id = sessioId,
      lootmaster = lahettaja,
      itemit = {},
      vastattu = {},
    }
  end

  for _, rivi in ipairs(itemit) do
    NS.omaSessio.itemit[rivi.indeksi] = {
      indeksi = rivi.indeksi,
      itemId = rivi.itemId,
    }
  end

  if NS.AvaaVastausIkkuna then NS.AvaaVastausIkkuna() end
end

--- Lahettaa oman vastauksen lootmasterille.
---
--- Kuiskauksena eika raidikanavalle: vastaus kuuluu vain lootmasterille,
--- eika kahdenkymmenen pelaajan vastauksia kannata lahettaa kaikille.
function NS.Vastaa(indeksi, koodi)
  local s = NS.omaSessio
  if not s then return end

  s.vastattu[indeksi] = koodi
  NS.Comm.LahetaKuiskaus(s.lootmaster, "VASTAUS",
    ("%s %d %s"):format(s.id, indeksi, koodi))

  if NS.PaivitaVastausIkkuna then NS.PaivitaVastausIkkuna() end
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

function NS.SessioPaattyi(sessioId)
  if NS.omaSessio and NS.omaSessio.id == sessioId then
    NS.omaSessio = nil
    if NS.SuljeVastausIkkuna then NS.SuljeVastausIkkuna() end
  end
end
