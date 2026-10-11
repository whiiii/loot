/**
 * The raid's items and a raider's picks.
 */

/**
 * The character sheet's slots in the order they appear on screen.
 *
 * A slot position and an item slot are different things: there are two
 * ring positions but only one ring slot. The picker is therefore opened
 * by position and the items filtered by slot.
 *
 * Shirt and tabard are missing on purpose — they do not drop in raids.
 *
 * The position names are in English deliberately. Players talk about
 * slots by the game's own names, and a translation ("Sivukäsi") is
 * confusing even when it is correct.
 */
export const SLOTS = [
  { key: "head",     slot: "head",     name: "Head",      side: "left" },
  { key: "neck",     slot: "neck",     name: "Neck",      side: "left" },
  { key: "shoulder", slot: "shoulder", name: "Shoulder",  side: "left" },
  { key: "back",     slot: "back",     name: "Back",      side: "left" },
  { key: "chest",    slot: "chest",    name: "Chest",     side: "left" },
  { key: "wrist",    slot: "wrist",    name: "Wrist",     side: "left" },

  { key: "hands",    slot: "hands",    name: "Hands",     side: "right" },
  { key: "waist",    slot: "waist",    name: "Waist",     side: "right" },
  { key: "legs",     slot: "legs",     name: "Legs",      side: "right" },
  { key: "feet",     slot: "feet",     name: "Feet",      side: "right" },
  { key: "finger1",  slot: "finger",   name: "Ring",      side: "right" },
  { key: "finger2",  slot: "finger",   name: "Ring",      side: "right" },
  { key: "trinket1", slot: "trinket",  name: "Trinket",   side: "right" },
  { key: "trinket2", slot: "trinket",  name: "Trinket",   side: "right" },

  { key: "mainhand", slot: "mainhand", name: "Main Hand", side: "bottom" },
  { key: "offhand",  slot: "offhand",  name: "Off Hand",  side: "bottom" },
  { key: "ranged",   slot: "ranged",   name: "Ranged",    side: "bottom" },
];

const SLOT_BY_KEY = new Map(SLOTS.map((s) => [s.key, s.slot]));

export async function getActiveRaid(env) {
  return await env.DB.prepare(
    "SELECT id, name FROM raids WHERE is_active = 1 ORDER BY id DESC LIMIT 1"
  ).first();
}

/**
 * The member list for the profile page's sidebar.
 *
 * For every logged-in user. Only what the profile page shows anyway:
 * name, class, raid role and pick count. Locks, guild rank and login
 * times belong to the admin pages — this list is for comparison, not
 * supervision.
 */
export async function getRoster(env) {
  const raid = await getActiveRaid(env);
  const raidId = raid ? raid.id : 0;

  const rows = await env.DB.prepare(
    `SELECT u.username, u.character_name, u.first_name, u.last_name,
            u.class, u.raid_role,
            (SELECT COUNT(*) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?) AS picks
       FROM users u
      WHERE u.protected = 0
      ORDER BY
        COALESCE(NULLIF(u.first_name, ''), NULLIF(u.character_name, ''),
                 u.username) COLLATE NOCASE`
  )
    .bind(raidId)
    .all();

  return { slotCount: SLOTS.length, members: rows.results ?? [] };
}

/**
 * The active raid, its items and the user's own picks in one call.
 *
 * All three are needed for the same view, so fetching them separately
 * would be three queries for what is drawn at once.
 */
export async function getView(env, userId) {
  const raid = await getActiveRaid(env);
  if (!raid) {
    return { raid: null, slots: SLOTS, items: [], picks: {} };
  }

  const items = await env.DB.prepare(
    `SELECT item_id, boss, slot, armor_type
       FROM items WHERE raid_id = ?
      ORDER BY slot, boss, item_id`
  )
    .bind(raid.id)
    .all();

  const pickRows = await env.DB.prepare(
    "SELECT slot_key, item_id FROM picks WHERE user_id = ? AND raid_id = ?"
  )
    .bind(userId, raid.id)
    .all();

  const picks = {};
  for (const row of pickRows.results ?? []) picks[row.slot_key] = row.item_id;

  // Which of the picked items have already been received.
  //
  // Matched both by user id and by character name: the addon records the
  // winner's character name, and it cannot always be tied to an account
  // at import time — for instance if the character was renamed.
  const receivedRows = await env.DB.prepare(
    `SELECT DISTINCT h.item_id
       FROM loot_history h
       LEFT JOIN users u ON u.id = ?
      WHERE h.user_id = ?
         OR LOWER(h.winner) = LOWER(COALESCE(u.character_name, ''))
         OR LOWER(h.winner) = LOWER(COALESCE(u.first_name, ''))
         OR LOWER(h.winner) = LOWER(COALESCE(u.username, ''))`
  )
    .bind(userId, userId)
    .all();

  const received = (receivedRows.results ?? []).map((r) => r.item_id);

  return {
    raid: { id: raid.id, name: raid.name },
    slots: SLOTS,
    items: items.results ?? [],
    picks,
    received,
  };
}

/**
 * Saves one slot's pick. An empty item clears the pick.
 *
 * The checks are on the server even though the browser pre-filters the
 * list: a limit in the browser is user interface, not a rule.
 */
export async function savePick(env, user, slotKey, itemId) {
  // The lock applies to a raider, not an officer. An officer has to be
  // able to fix mistakes without first opening the lock and forgetting
  // to close it.
  if (user.locked && user.role !== "officer") {
    return {
      error: "Profiilisi on lukittu. Pyydä officeria avaamaan se.",
      status: 403,
    };
  }

  const slot = SLOT_BY_KEY.get(slotKey);
  if (!slot) return { error: "Tuntematon paikka.", status: 400 };

  const raid = await getActiveRaid(env);
  if (!raid) return { error: "Aktiivista raidia ei ole.", status: 409 };

  if (itemId === null) {
    await env.DB.prepare(
      "DELETE FROM picks WHERE user_id = ? AND raid_id = ? AND slot_key = ?"
    )
      .bind(user.id, raid.id, slotKey)
      .run();
    return { ok: true, slot_key: slotKey, item_id: null };
  }

  // The item has to belong to this raid and fit this slot.
  const item = await env.DB.prepare(
    "SELECT item_id FROM items WHERE raid_id = ? AND item_id = ? AND slot = ?"
  )
    .bind(raid.id, itemId, slot)
    .first();

  if (!item) return { error: "Item ei sovi tähän paikkaan.", status: 400 };

  // The same item in two positions makes no sense: two rings means two
  // different rings, not the same one twice.
  await env.DB.prepare(
    "DELETE FROM picks WHERE user_id = ? AND raid_id = ? AND item_id = ? AND slot_key != ?"
  )
    .bind(user.id, raid.id, itemId, slotKey)
    .run();

  await env.DB.prepare(
    `INSERT INTO picks (user_id, raid_id, slot_key, item_id, updated_at)
     VALUES (?, ?, ?, ?, datetime('now'))
     ON CONFLICT(user_id, raid_id, slot_key)
       DO UPDATE SET item_id = excluded.item_id, updated_at = excluded.updated_at`
  )
    .bind(user.id, raid.id, slotKey, itemId)
    .run();

  return { ok: true, slot_key: slotKey, item_id: itemId };
}
