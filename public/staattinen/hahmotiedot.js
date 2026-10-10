/**
 * Luokat, varit ja roolit selaimen puolelle.
 *
 * Sama lista on palvelimella src/hahmo.js:ssa. Ne on pidettava samana;
 * jos nimet erkaantuvat, palvelin torjuu valinnan jota kayttoliittyma
 * tarjosi.
 */
window.LUOKAT = {
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

window.RAIDIROOLIT = { tank: "Tank", healer: "Healer", dps: "DPS" };

window.RANGIT = { social: "Social", raider: "Raider", officer: "Officer" };

/** Hahmon nakyva nimi: etu- ja sukunimi, tai tunnus jos niita ei ole. */
window.hahmonNimi = function (u) {
  const osat = [u.first_name, u.last_name].filter((s) => s && String(s).trim());
  return osat.length ? osat.join(" ") : u.character_name || u.username;
};

window.luokanVari = function (luokka) {
  return window.LUOKAT[luokka] ? window.LUOKAT[luokka].vari : "inherit";
};
