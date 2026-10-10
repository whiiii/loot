/**
 * Hahmon luokat ja raidiroolit.
 *
 * Varit ovat pelin omat. Niita ei keksita itse: pelaajat tunnistavat
 * luokan varista ilman etta lukevat nimea, ja vaara savy on sekava.
 */
export const LUOKAT = {
  warrior: { nimi: "Warrior", vari: "#C79C6E" },
  paladin: { nimi: "Paladin", vari: "#F58CBA" },
  hunter:  { nimi: "Hunter",  vari: "#ABD473" },
  rogue:   { nimi: "Rogue",   vari: "#FFF569" },
  priest:  { nimi: "Priest",  vari: "#FFFFFF" },
  shaman:  { nimi: "Shaman",  vari: "#0070DE" },
  mage:    { nimi: "Mage",    vari: "#69CCF0" },
  warlock: { nimi: "Warlock", vari: "#9482C9" },
  druid:   { nimi: "Druid",   vari: "#FF7D0A" },
};

export const RAIDIROOLIT = {
  tank:   "Tank",
  healer: "Healer",
  dps:    "DPS",
};

/**
 * Mihin rooleihin kukin luokka kelpaa.
 *
 * Tankkeja ovat vain Warrior, Paladin ja Druid. Parantajia Paladin,
 * Priest, Shaman ja Druid. Kaikki voivat olla DPS.
 *
 * Tarkistus on palvelimella eika vain valitsimessa: selaimen rajaus on
 * kayttoliittymaa, ei saanto, ja sen ohittaa avaamalla konsolin.
 */
export const LUOKAN_ROOLIT = {
  warrior: ["tank", "dps"],
  paladin: ["tank", "healer", "dps"],
  hunter:  ["dps"],
  rogue:   ["dps"],
  priest:  ["healer", "dps"],
  shaman:  ["healer", "dps"],
  mage:    ["dps"],
  warlock: ["dps"],
  druid:   ["tank", "healer", "dps"],
};

/**
 * Kelpaako rooli luokalle.
 *
 * Tyhja rooli kelpaa aina, ja ilman luokkaa ei voi paatella mitaan - ne
 * eivat ole virheita vaan keskenerainen profiili.
 */
export function rooliSopii(luokka, rooli) {
  if (!rooli || !luokka) return true;
  const sallitut = LUOKAN_ROOLIT[luokka];
  return !sallitut || sallitut.includes(rooli);
}

export function onLuokka(arvo) {
  return arvo === null || arvo === "" || Object.hasOwn(LUOKAT, arvo);
}

export function onRaidirooli(arvo) {
  return arvo === null || arvo === "" || Object.hasOwn(RAIDIROOLIT, arvo);
}

/** Hahmon nakyva nimi. Etu- ja sukunimi, tai tunnus jos kumpaakaan ei ole. */
export function hahmonNimi(u) {
  const osat = [u.first_name, u.last_name].filter((s) => s && String(s).trim());
  return osat.length ? osat.join(" ") : u.character_name || u.username;
}
