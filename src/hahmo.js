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
