/**
 * Classes, colours and roles for the browser side.
 *
 * The same list lives on the server in src/character.js. They have to
 * stay identical; if the names drift apart, the server rejects a pick
 * the user interface offered.
 */
window.CLASSES = {
  warrior: { name: "Warrior", colour: "#C79C6E" },
  paladin: { name: "Paladin", colour: "#F58CBA" },
  hunter:  { name: "Hunter",  colour: "#ABD473" },
  rogue:   { name: "Rogue",   colour: "#FFF569" },
  priest:  { name: "Priest",  colour: "#FFFFFF" },
  shaman:  { name: "Shaman",  colour: "#0070DE" },
  mage:    { name: "Mage",    colour: "#69CCF0" },
  warlock: { name: "Warlock", colour: "#9482C9" },
  druid:   { name: "Druid",   colour: "#FF7D0A" },
};

window.RAID_ROLES = { tank: "Tank", healer: "Healer", dps: "DPS" };

/**
 * Which roles each class is eligible for.
 *
 * The same table lives on the server in src/character.js, which is the
 * one that decides. This is for the interface: there is no point
 * offering an invalid option, even though rejecting it is handled
 * elsewhere.
 */
window.CLASS_ROLES = {
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

/** Valid roles for a class as key/name pairs. Without a class, all. */
window.rolesForClass = function (className) {
  const allowed = window.CLASS_ROLES[className];
  return Object.entries(window.RAID_ROLES).filter(
    ([key]) => !allowed || allowed.includes(key)
  );
};

window.RANKS = { social: "Social", raider: "Raider", officer: "Officer" };

/** The character's display name: first and last, or the username. */
window.characterName = function (u) {
  const parts = [u.first_name, u.last_name].filter((s) => s && String(s).trim());
  return parts.length ? parts.join(" ") : u.character_name || u.username;
};

/** A class colour, or the inherited colour when the class is unknown. */
window.classColour = function (className) {
  return window.CLASSES[className] ? window.CLASSES[className].colour : "inherit";
};
