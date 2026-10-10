--[[
  LootPrio — viestit raidin sisalla.

  Addonit puhuvat keskenaan omalla kanavallaan. Yksi viesti on enintaan
  255 tavua, joten pitkat listat pilkotaan osiin.

  Vastaanottajat eivat luota lahettajaan sokeasti: session avaa vain
  lootmaster. Muuten kuka tahansa voisi avata vastausikkunan koko raidille.
]]

local ADDON, NS = ...

local ETULIITE = "LOOTPRIO1"

NS.Comm = {}

local function kanava()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

function NS.Comm.Laheta(tyyppi, hyotykuorma)
  local kohde = kanava()
  if not kohde then return end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end

  C_ChatInfo.SendAddonMessage(ETULIITE, tyyppi .. " " .. (hyotykuorma or ""), kohde)
end

-- Vastaanotto --------------------------------------------------------------

function NS.Comm.Kasittele(tyyppi, sisalto, lahettaja)
  if tyyppi == "SESSIO" then
    -- Jaon avaa vain officer. Muuten kuka tahansa voisi avata
    -- vastausikkunan koko raidille.
    if not NS.OnOfficer(lahettaja) then return end

    local sessioId, nakyvyys, lista =
      sisalto:match("^(%S+)%s+(%S+)%s+(.*)$")
    if not sessioId then return end

    local itemit = {}
    for indeksi, itemId in lista:gmatch("(%d+):(%d+)") do
      itemit[#itemit + 1] = {
        indeksi = tonumber(indeksi),
        itemId = tonumber(itemId),
      }
    end

    NS.SaapuvaSessio(sessioId, nakyvyys, itemit, lahettaja)

  elseif tyyppi == "VASTAUS" then
    local sessioId, indeksi, koodi = sisalto:match("^(%S+)%s+(%d+)%s+(%S+)$")
    if not sessioId then return end

    -- Vastaus kirjataan aina lahettajan nimelle, ei viestin sisallon
    -- perusteella. Nain kukaan ei voi vastata toisen puolesta.
    NS.KirjaaVastaus(sessioId, tonumber(indeksi), lahettaja, koodi)

  elseif tyyppi == "ARPA" then
    -- Arvonnan tekee jaon avaaja, jotta kaikilla on sama numero.
    if not NS.OnOfficer(lahettaja) then return end

    local sessioId, indeksi, pelaaja, luku =
      sisalto:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%d+)$")
    if not sessioId then return end

    NS.KirjaaArpa(sessioId, tonumber(indeksi), pelaaja, tonumber(luku))

  elseif tyyppi == "JAETTU" then
    if not NS.OnOfficer(lahettaja) then return end

    local sessioId, indeksi, saaja, koodi, luku =
      sisalto:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+)$")
    if not sessioId then return end

    NS.KirjaaJako(sessioId, tonumber(indeksi), saaja, koodi, tonumber(luku))

  elseif tyyppi == "SULJE" then
    if not NS.OnOfficer(lahettaja) then return end
    NS.VastauksetSuljettu(sisalto:match("^(%S+)"))

  elseif tyyppi == "PERU" then
    if not NS.OnOfficer(lahettaja) then return end

    local sessioId, indeksi = sisalto:match("^(%S+)%s+(%d+)$")
    if not sessioId then return end
    if NS.sessio and NS.sessio.id == sessioId then
      NS.PeruJako(tonumber(indeksi), lahettaja)
    end

  elseif tyyppi == "LOPPU" then
    if not NS.OnOfficer(lahettaja) then return end
    NS.SessioPaattyi(sisalto:match("^(%S+)"))

  elseif tyyppi == "KYSY" then
    -- Kyselyn voi tehda kuka tahansa: vastaus kertoo vain version, eika
    -- sen salaaminen hyodyta ketaan.
    --
    -- Hajautettu viive: 40 samanaikaista vastausta tukkisi kanavan ja osa
    -- viesteista katoaisi, jolloin lista nayttaisi puuttuvia addoneita.
    C_Timer.After(math.random() * 3, NS.LahetaVersio)

  elseif tyyppi == "VERSIO" then
    local versio, profiileja, omaProfiili =
      sisalto:match("^(%S+)%s+(%d+)%s+(%d)$")
    if not versio then return end

    NS.KirjaaVersio(lahettaja, versio, tonumber(profiileja), omaProfiili == "1")
  end
end

--------------------------------------------------------------------------
-- Versiokattely
--------------------------------------------------------------------------

--- Kenella raidissa on addon ja mika versio.
---
--- Istuntokohtainen eika tallennettava: kysymys on siita mika tilanne on
--- juuri nyt, ja viime viikon tieto olisi vain harhaanjohtava.
NS.addonit = {}

--- Oma versio ja profiilitilanne raidille.
---
--- Profiilien maara kertoo onko vienti tuotu lainkaan, ja oman profiilin
--- olemassaolo sen miksi LootPrio-nappi on harmaa. Molemmat ovat syita
--- joiden takia jako nayttaa rikkinaiselta ilman etta mikaan on rikki.
function NS.LahetaVersio()
  -- Roster-tapahtuma voi osua ennen tallennuksen latautumista.
  if not NS.db then return end

  local kpl = 0
  for _ in pairs(NS.db.profiilit) do kpl = kpl + 1 end

  local oma = NS.db.profiilit[NS.OmaNimi()] and "1" or "0"

  NS.Comm.Laheta("VERSIO", ("%s %d %s"):format(NS.VERSIO, kpl, oma))
  NS.KirjaaVersio(NS.OmaNimi(), NS.VERSIO, kpl, oma == "1")
end

function NS.KirjaaVersio(nimi, versio, profiileja, omaProfiili)
  NS.addonit[nimi] = {
    versio = versio,
    profiileja = profiileja or 0,
    omaProfiili = omaProfiili and true or false,
    aika = GetTime(),
  }

  if NS.PaivitaNakyma then NS.PaivitaNakyma("jasenet") end
end

--- Pyytaa kaikkien version.
function NS.PyydaVersiot()
  wipe(NS.addonit)
  NS.Comm.Laheta("KYSY", "")
  NS.LahetaVersio()
end

--- Vertailee versionumeroita osa kerrallaan.
---
--- Merkkijonovertailu riittaisi vain siihen asti kun numerot ovat yhden
--- merkin mittaisia: "0.10" olisi silla pienempi kuin "0.9".
function NS.VersioVanhempi(a, b)
  local function osat(v)
    local lista = {}
    for n in tostring(v or ""):gmatch("%d+") do lista[#lista + 1] = tonumber(n) end
    return lista
  end

  local x, z = osat(a), osat(b)
  for i = 1, math.max(#x, #z) do
    local p, q = x[i] or 0, z[i] or 0
    if p ~= q then return p < q end
  end

  return false
end

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("CHAT_MSG_ADDON")
kehys:RegisterEvent("GROUP_ROSTER_UPDATE")

-- Oma versio kerrotaan raidiin liittyessa, mutta harvakseltaan: roster
-- muuttuu kymmenia kertoja raidin kokoontuessa, eika jokainen muutos ole
-- syy lahettaa mitaan.
local viimeksiKerrottu = 0

kehys:SetScript("OnEvent", function(_, tapahtuma, etuliite, viesti, _, lahettaja)
  if tapahtuma == "GROUP_ROSTER_UPDATE" then
    if not IsInGroup() then
      wipe(NS.addonit)
      return
    end

    if GetTime() - viimeksiKerrottu > 60 then
      viimeksiKerrottu = GetTime()
      C_Timer.After(2, NS.LahetaVersio)
    end
    return
  end

  if etuliite ~= ETULIITE then return end

  -- Lahettajan nimi profiilien muotoon: NS.Nimi pudottaa myos realmin.
  -- Nain vastaukset kirjautuvat samalla nimella kuin profiilit, eika
  -- samasta pelaajasta synny kahta eri riviä.
  local nimi = lahettaja and NS.Nimi(lahettaja) or ""
  if nimi == "" then return end

  local tyyppi, sisalto = viesti:match("^(%S+)%s*(.-)$")
  if not tyyppi then return end

  -- Omat viestit ohitetaan: ne on jo kasitelty lahetyksen yhteydessa.
  if nimi == NS.OmaNimi() then return end

  NS.Comm.Kasittele(tyyppi, sisalto, nimi)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(ETULIITE)
end

