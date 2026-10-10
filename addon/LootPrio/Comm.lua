--[[
  LootPrio — viestit raidin sisalla.

  Addonit puhuvat keskenaan omalla kanavallaan. Yksi viesti on enintaan
  255 tavua, joten pitkat arvontatulokset lahetetaan itemi kerrallaan.

  Vastaanottajat eivat luota lahettajaan sokeasti: arvonnat hyvaksytaan
  vain lootmasterilta. Muuten kuka tahansa voisi lahettaa omat numeronsa.
]]

local ADDON, NS = ...

local ETULIITE = "LOOTPRIO1"

NS.Comm = {}

local function kanava()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

--- Lahettaa viestin raidille. Tyyppi ja hyotykuorma erotetaan valilyonnilla.
function NS.Comm.Laheta(tyyppi, hyotykuorma)
  local kohde = kanava()
  if not kohde then return end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end

  C_ChatInfo.SendAddonMessage(ETULIITE, tyyppi .. " " .. (hyotykuorma or ""), kohde)
end

--- Lahettaa yhden itemin arvontatulokset.
---
--- Muoto: ROLL <itemId> <nimi>:<luku>,<nimi>:<luku>,...
--- Jos rivi uhkaa ylittaa viestin pituusrajan, se katkaistaan ja loput
--- lahetetaan omana viestinaan.
function NS.Comm.LahetaRollit(itemId, rollit)
  local osat = {}
  local pituus = 0

  local function tyhjenna()
    if #osat > 0 then
      NS.Comm.Laheta("ROLL", itemId .. " " .. table.concat(osat, ","))
      osat, pituus = {}, 0
    end
  end

  for _, r in ipairs(rollit) do
    local pala = r.nimi .. ":" .. r.luku
    -- 200 on varmuusvara: etuliite, tyyppi ja itemId vievat omansa.
    if pituus + #pala + 1 > 200 then tyhjenna() end
    osat[#osat + 1] = pala
    pituus = pituus + #pala + 1
  end

  tyhjenna()
end

-- Vastaanotto --------------------------------------------------------------

local kehys = CreateFrame("Frame")
kehys:RegisterEvent("CHAT_MSG_ADDON")

kehys:SetScript("OnEvent", function(_, _, etuliite, viesti, _, lahettaja)
  if etuliite ~= ETULIITE then return end

  -- Lahettajan nimessa voi olla realm perassa.
  local nimi = lahettaja and lahettaja:match("^[^-]+") or ""
  if nimi == NS.OmaNimi() then return end

  local tyyppi, sisalto = viesti:match("^(%S+)%s*(.-)$")
  if not tyyppi then return end

  if tyyppi == "ROLL" then
    -- Vain lootmasterin arvonnat kelpaavat. Ilman tata kuka tahansa voisi
    -- lahettaa omat numeronsa ja ne nayttaisivat virallisilta.
    if not NS.OnLootMasterNimi(nimi) then return end

    local itemId, lista = sisalto:match("^(%d+)%s+(.*)$")
    if not itemId then return end

    local rivit = {}
    for hahmo, luku in lista:gmatch("([^,:]+):(%d+)") do
      rivit[#rivit + 1] = { nimi = hahmo, luku = tonumber(luku) }
    end

    if NS.NaytaSaadutRollit then
      NS.NaytaSaadutRollit(tonumber(itemId), rivit, nimi)
    end
  end
end)

-- Etuliite on rekisteroitava, muuten viestit eivat tule perille lainkaan.
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
