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

  elseif tyyppi == "LOPPU" then
    if not NS.OnOfficer(lahettaja) then return end
    NS.SessioPaattyi(sisalto:match("^(%S+)"))
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

  -- Omat viestit ohitetaan: ne on jo kasitelty lahetyksen yhteydessa.
  if nimi == NS.OmaNimi() then return end

  NS.Comm.Kasittele(tyyppi, sisalto, nimi)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(ETULIITE)
end

