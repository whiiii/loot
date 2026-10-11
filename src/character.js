/**
 * Character classes and raid roles.
 *
 * The colours are the game's own. They are not invented here: players
 * recognise a class from its colour without reading the name, and a
 * wrong shade is confusing.
 */
export const CLASSES = {
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

export const RAID_ROLES = {
  tank:   "Tank",
  healer: "Healer",
  dps:    "DPS",
};

/**
 * Which roles each class is eligible for.
 *
 * Only Warrior, Paladin and Druid tank. Paladin, Priest, Shaman and
 * Druid heal. Everyone can be DPS.
 *
 * The check is on the server rather than only in the dropdown: a limit
 * in the browser is user interface, not a rule, and it is bypassed by
 * opening the console.
 */
export const CLASS_ROLES = {
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
 * Is the role valid for the class.
 *
 * An empty role is always valid, and without a class nothing can be
 * concluded — neither is an error, just an unfinished profile.
 */
export function roleFitsClass(className, role) {
  if (!role || !className) return true;
  const allowed = CLASS_ROLES[className];
  return !allowed || allowed.includes(role);
}

export function isClass(value) {
  return value === null || value === "" || Object.hasOwn(CLASSES, value);
}

export function isRaidRole(value) {
  return value === null || value === "" || Object.hasOwn(RAID_ROLES, value);
}

/** The character's display name. First and last name, or the username. */
export function characterName(u) {
  const parts = [u.first_name, u.last_name].filter((s) => s && String(s).trim());
  return parts.length ? parts.join(" ") : u.character_name || u.username;
}
