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

--- Kuiskaus yhdelle pelaajalle.
---
--- Vastaukset kulkevat nain: ne kuuluvat vain lootmasterille, eika
--- kahdenkymmenen pelaajan vastauksia kannata lahettaa koko raidille.
function NS.Comm.LahetaKuiskaus(kohde, tyyppi, hyotykuorma)
  if not kohde or kohde == "" then return end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end

  if kohde == NS.OmaNimi() then
    -- Peli ei valita kuiskausta itselle, joten se kasitellaan suoraan.
    NS.Comm.Kasittele(tyyppi, hyotykuorma or "", kohde)
    return
  end

  C_ChatInfo.SendAddonMessage(ETULIITE, tyyppi .. " " .. (hyotykuorma or ""),
    "WHISPER", kohde)
end

--- Lahettaa yhden itemin arvontatulokset koko raidille.
function NS.Comm.LahetaRollit(itemId, rollit)
  local osat, pituus = {}, 0

  local function tyhjenna()
    if #osat > 0 then
      NS.Comm.Laheta("ROLL", itemId .. " " .. table.concat(osat, ","))
      osat, pituus = {}, 0
    end
  end

  for _, r in ipairs(rollit) do
    local pala = r.nimi .. ":" .. (r.luku or 0)
    if pituus + #pala + 1 > 200 then tyhjenna() end
    osat[#osat + 1] = pala
    pituus = pituus + #pala + 1
  end

  tyhjenna()
end

-- Vastaanotto --------------------------------------------------------------

function NS.Comm.Kasittele(tyyppi, sisalto, lahettaja)
  if tyyppi == "SESSIO" then
    -- Session avaa vain lootmaster. Muuten kuka tahansa voisi avata
    -- vastausikkunan koko raidille.
    if not NS.OnLootMasterNimi(lahettaja) then return end

    local sessioId, lista = sisalto:match("^(%S+)%s+(.*)$")
    if not sessioId then return end

    local itemit = {}
    for indeksi, itemId in lista:gmatch("(%d+):(%d+)") do
      itemit[#itemit + 1] = {
        indeksi = tonumber(indeksi),
        itemId = tonumber(itemId),
      }
    end

    NS.SaapuvaSessio(sessioId, itemit, lahettaja)

  elseif tyyppi == "VASTAUS" then
    -- Vastaukset kiinnostavat vain lootmasteria.
    if not NS.OnLootMaster() then return end

    local sessioId, indeksi, koodi = sisalto:match("^(%S+)%s+(%d+)%s+(%S+)$")
    if not sessioId then return end

    NS.KirjaaVastaus(sessioId, tonumber(indeksi), lahettaja, koodi)

  elseif tyyppi == "LOPPU" then
    if not NS.OnLootMasterNimi(lahettaja) then return end
    NS.SessioPaattyi(sisalto:match("^(%S+)"))

  elseif tyyppi == "ROLL" then
    if not NS.OnLootMasterNimi(lahettaja) then return end

    local itemId, lista = sisalto:match("^(%d+)%s+(.*)$")
    if not itemId then return end

    local rivit = {}
    for hahmo, luku in lista:gmatch("([^,:]+):(%d+)") do
      rivit[#rivit + 1] = { nimi = hahmo, luku = tonumber(luku) }
    end

    if NS.NaytaSaadutRollit then
      NS.NaytaSaadutRollit(tonumber(itemId), rivit)
    end
  end
end

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("CHAT_MSG_ADDON")

kehys:SetScript("OnEvent", function(_, _, etuliite, viesti, _, lahettaja)
  if etuliite ~= ETULIITE then return end

  -- Lahettajan nimessa voi olla realm perassa.
  local nimi = lahettaja and lahettaja:match("^[^-]+") or ""
  if nimi == "" then return end

  local tyyppi, sisalto = viesti:match("^(%S+)%s*(.-)$")
  if not tyyppi then return end

  -- Omat viestit ohitetaan paitsi kuiskaus itselle, joka kasitellaan jo
  -- lahetyksessa.
  if nimi == NS.OmaNimi() then return end

  NS.Comm.Kasittele(tyyppi, sisalto, nimi)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(ETULIITE)
end

--- Onko annettu nimi talla hetkella master looter.
function NS.OnLootMasterNimi(nimi)
  local metodi, mlPartyID, mlRaidID = GetLootMethod()
  if metodi ~= "master" then return false end

  if IsInRaid() then
    if not mlRaidID then return false end
    local mlNimi = GetRaidRosterInfo(mlRaidID)
    return mlNimi == nimi
  end

  if mlPartyID == 0 then return nimi == NS.OmaNimi() end
  return UnitName("party" .. mlPartyID) == nimi
end
