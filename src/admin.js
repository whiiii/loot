/**
 * Officer tools: the member list, locks and the addon export/import.
 */
import { getActiveRaid, SLOTS } from "./picks.js";
import { hashPassword, isProtected } from "./auth.js";
import {
  CLASS_ROLES,
  CLASSES,
  RAID_ROLES,
  isClass,
  isRaidRole,
  roleFitsClass,
} from "./character.js";

/**
 * The grounds for an award, i.e. the addon's response button codes.
 *
 * The import accepts only these: any other value would come from a
 * modified addon, and such a thing has no business reaching the database
 * and then the views. "pass" is not here — someone who passed cannot win
 * the item.
 */
const RESPONSES = new Set(["prio", "main", "off", "muu"]);

/** The addon marks a missing field with a dash. That is not a value. */
function emptyDash(value) {
  return !value || value === "-" ? null : value;
}

/**
 * The character's in-game name, as a SQL expression.
 *
 * The addon compares this against UnitName("player"), so it really is
 * the character's name and not the username or the full name.
 * first_name is the column migration v4 moved the old character_name
 * into, and new members only get that one — character_name was left
 * empty.
 *
 * In one place, because two different truths about the same name is
 * exactly the bug that put the wrong name in the export.
 */
const CHARACTER_NAME =
  "COALESCE(NULLIF(u.first_name, ''), NULLIF(u.character_name, ''), u.username)";

/**
 * Refuses an action when the target is the protected admin account.
 *
 * The protected account is the site's emergency exit: it gets you in
 * when officer rights have gone missing. That does not help if someone
 * deletes, locks or demotes it first — so no action touches it, not even
 * one by another officer.
 *
 * The check is repeated in every function rather than in one routing
 * place: a new action is easy to add to the routes and forget here.
 */
function refuseProtected(target, what) {
  if (!isProtected(target)) return null;
  return {
    error: `Ylläpitotunnusta ei voi ${what}. Se on varauloskäynti.`,
    status: 403,
  };
}

/** A plain-language error for an invalid class/role pair. */
function roleError(className, role) {
  const classLabel = CLASSES[className] ? CLASSES[className].name : className;
  const allowed = (CLASS_ROLES[className] || [])
    .map((r) => RAID_ROLES[r])
    .join(", ");

  return `${classLabel} ei voi olla ${RAID_ROLES[role] || role}. Sallitut: ${allowed}.`;
}

/**
 * The condition that ties loot history to a user, as a SQL expression.
 *
 * The winner is a character name from the game, matched to an account if
 * one was found at import time. The name comparison is there because the
 * import may have happened before the account existed — the history must
 * not disappear because rows were written in the wrong order.
 */
const HISTORY_MATCHES = `(
  h.user_id = u.id
  OR LOWER(h.winner) = LOWER(COALESCE(u.first_name, ''))
  OR LOWER(h.winner) = LOWER(COALESCE(u.character_name, ''))
  OR LOWER(h.winner) = LOWER(COALESCE(u.username, ''))
)`;

/**
 * Users with their pick and received counts for the active raid.
 *
 * Received counts only items that are in the profile: the number answers
 * "how many of their own picks have they got", not how many items they
 * have received in total. The latter is the addon's SAATU column and a
 * different thing.
 */
export async function getUsers(env) {
  const raid = await getActiveRaid(env);
  const raidId = raid ? raid.id : 0;

  const rows = await env.DB.prepare(
    `SELECT u.id, u.username, u.character_name, u.first_name, u.last_name,
            u.class, u.raid_role, u.role, u.locked, u.protected, u.avatar_key,
            u.created_at, u.last_login_at,
            (SELECT COUNT(*) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?) AS picks,
            (SELECT COUNT(DISTINCT p.item_id) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?
                AND EXISTS (SELECT 1 FROM loot_history h
                             WHERE h.item_id = p.item_id
                               AND ${HISTORY_MATCHES})) AS received
       FROM users u
      ORDER BY
        u.protected DESC,
        CASE u.role WHEN 'officer' THEN 0 WHEN 'raider' THEN 1 ELSE 2 END,
        u.username COLLATE NOCASE`
  )
    .bind(raidId, raidId)
    .all();

  return {
    raid: raid ? { id: raid.id, name: raid.name } : null,
    slotCount: SLOTS.length,
    users: rows.results ?? [],
  };
}

/** The shortest acceptable reason. Three characters stops slips, nothing more. */
export const REASON_MIN = 3;

/**
 * Opens or closes a profile's lock.
 *
 * An officer's own lock does not need touching, because the lock does not
 * restrict them — but it is allowed anyway so the state stays coherent.
 *
 * Opening requires a reason. The lock is what stops picks changing
 * mid-tier, so opening it is exactly the act that gets asked about later
 * — and whoever asks deserves more of an answer than a name and a
 * timestamp. Closing requires nothing: it restores the normal state.
 */
export async function setLock(env, actor, username, locked, reason) {
  const target = await env.DB.prepare(
    "SELECT id, username, locked, protected FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!target) return { error: "Käyttäjää ei löydy.", status: 404 };

  const refused = refuseProtected(target, "lukita");
  if (refused) return refused;

  const text = String(reason ?? "").trim().slice(0, 200);

  if (!locked && text.length < REASON_MIN) {
    return {
      error: `Lukon avaaminen vaatii syyn (vähintään ${REASON_MIN} merkkiä).`,
      status: 400,
    };
  }

  await env.DB.prepare("UPDATE users SET locked = ? WHERE id = ?")
    .bind(locked ? 1 : 0, target.id)
    .run();

  await writeLog(env, actor, locked ? "LOCK" : "UNLOCK", target.username,
    locked ? null : text);

  return { ok: true, username: target.username, locked: locked ? 1 : 0 };
}

export const ROLES = ["social", "raider", "officer"];

/**
 * Changes a user's guild rank.
 *
 * The last officer cannot be demoted. Without this the guild could be
 * left without administration in one click, and could not fix it itself:
 * opening locks and changing roles both need the very role that just
 * disappeared.
 */
export async function setRole(env, actor, username, role) {
  if (!ROLES.includes(role)) return { error: "Tuntematon rooli.", status: 400 };

  const target = await env.DB.prepare(
    "SELECT id, username, role, protected FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!target) return { error: "Käyttäjää ei löydy.", status: 404 };

  const refused = refuseProtected(target, "alentaa");
  if (refused) return refused;

  if (target.role === role) {
    return { ok: true, username: target.username, role };
  }

  if (target.role === "officer" && role !== "officer") {
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM users WHERE role = 'officer'"
    ).first();

    if ((row?.n ?? 0) <= 1) {
      return {
        error: "Tämä on viimeinen officer. Nimeä ensin toinen officer.",
        status: 409,
      };
    }
  }

  await env.DB.prepare("UPDATE users SET role = ? WHERE id = ?")
    .bind(role, target.id)
    .run();

  await writeLog(env, actor, "CHANGE_ROLE", target.username,
    `${target.role} -> ${role}`);
  return { ok: true, username: target.username, role };
}

export const PASSWORD_MIN = 6;

/** A username holds only letters, digits, underscore and hyphen. */
const USERNAME_RULE = /^[A-Za-z0-9_-]{3,20}$/;

/**
 * Creates a new user.
 *
 * The character name may be empty, in which case it is the username. In
 * most guilds they are the same thing, and there is no point forcing a
 * field that adds nothing.
 */
export async function createUser(env, actor, details) {
  const username = String(details.username ?? "").trim();
  const firstName = String(details.first_name ?? "").trim();
  const lastName = String(details.last_name ?? "").trim();
  const className = String(details.class ?? "").trim();
  const raidRole = String(details.raid_role ?? "").trim();
  const role = String(details.role ?? "raider");
  const password = String(details.password ?? "");

  if (!isClass(className)) return { error: "Tuntematon luokka.", status: 400 };
  if (!isRaidRole(raidRole)) return { error: "Tuntematon rooli.", status: 400 };
  if (!roleFitsClass(className, raidRole)) {
    return { error: roleError(className, raidRole), status: 400 };
  }

  if (!USERNAME_RULE.test(username)) {
    return {
      error:
        "Tunnuksessa saa olla 3–20 merkkiä: kirjaimia, numeroita, " +
        "alaviivoja tai väliviivoja.",
      status: 400,
    };
  }
  if (!ROLES.includes(role)) return { error: "Tuntematon rooli.", status: 400 };
  if (password.length < PASSWORD_MIN) {
    return {
      error: `Salasanan on oltava vähintään ${PASSWORD_MIN} merkkiä.`,
      status: 400,
    };
  }

  const taken = await env.DB.prepare("SELECT id FROM users WHERE username = ?")
    .bind(username)
    .first();

  if (taken) return { error: "Tunnus on jo käytössä.", status: 409 };

  const hash = await hashPassword(password);

  await env.DB.prepare(
    `INSERT INTO users
       (username, password_hash, role, first_name, last_name, class, raid_role)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      username,
      hash,
      role,
      firstName || username,
      lastName || null,
      className || null,
      raidRole || null
    )
    .run();

  await writeLog(env, actor, "CREATE_USER", username, `rooli=${role}`);
  return { ok: true, username };
}

/**
 * Deletes a user.
 *
 * Picks and sessions go with them, but the loot history does not: there
 * the reference to the account is cleared and the character name
 * remains. The history is supposed to tell what happened in the raid,
 * not who is still in the guild.
 *
 * The last officer cannot be deleted, nor can you delete yourself — both
 * would leave a situation you cannot fix yourself.
 */
export async function deleteUser(env, actor, username) {
  const target = await env.DB.prepare(
    "SELECT id, username, role, protected FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!target) return { error: "Käyttäjää ei löydy.", status: 404 };

  const refused = refuseProtected(target, "poistaa");
  if (refused) return refused;

  if (target.username.toLowerCase() === String(actor).toLowerCase()) {
    return { error: "Et voi poistaa omaa tunnustasi.", status: 409 };
  }

  if (target.role === "officer") {
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM users WHERE role = 'officer'"
    ).first();

    if ((row?.n ?? 0) <= 1) {
      return {
        error: "Tämä on viimeinen officer. Nimeä ensin toinen officer.",
        status: 409,
      };
    }
  }

  await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(target.id).run();

  await writeLog(env, actor, "DELETE_USER", target.username,
    `rooli=${target.role}`);
  return { ok: true, username: target.username };
}

/**
 * An officer sets a new password for a user.
 *
 * Old sessions are not left standing. A password change is often exactly
 * the moment access is meant to be cut — if the sessions lived on, the
 * change would not do what is expected of it.
 */
export async function setPassword(env, actor, username, password) {
  if (String(password).length < PASSWORD_MIN) {
    return {
      error: `Salasanan on oltava vähintään ${PASSWORD_MIN} merkkiä.`,
      status: 400,
    };
  }

  const target = await env.DB.prepare(
    "SELECT id, username, protected FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!target) return { error: "Käyttäjää ei löydy.", status: 404 };

  // The protected account may change its own password, nobody else may.
  // If someone else could, the emergency exit would be theirs, not yours.
  if (isProtected(target) &&
      target.username.toLowerCase() !== String(actor).toLowerCase()) {
    return {
      error: "Ylläpitotunnuksen salasanan voi vaihtaa vain se itse.",
      status: 403,
    };
  }

  const hash = await hashPassword(password);

  await env.DB.batch([
    env.DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?")
      .bind(hash, target.id),
    env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(target.id),
  ]);

  // The password is never written to the log in any form.
  await writeLog(env, actor, "CHANGE_PASSWORD", target.username, null);
  return { ok: true, username: target.username };
}

/**
 * An officer updates a character's details.
 *
 * Only the fields that were sent are changed. A missing field does not
 * mean "clear this" — it means the caller said nothing about it.
 */
export async function updateCharacter(env, actor, username, changes) {
  const target = await env.DB.prepare(
    "SELECT id, username, class, raid_role, protected FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!target) return { error: "Käyttäjää ei löydy.", status: 404 };

  // The protected account is not a character: no class, no raid role, no
  // name in the game.
  const refused = refuseProtected(target, "muokata hahmona");
  if (refused) return refused;

  const allowed = {
    first_name: (v) => String(v).trim().slice(0, 40),
    last_name: (v) => String(v).trim().slice(0, 40),
    class: (v) => String(v).trim(),
    raid_role: (v) => String(v).trim(),
  };

  const columns = [];
  const values = [];

  for (const [name, clean] of Object.entries(allowed)) {
    if (!Object.hasOwn(changes, name)) continue;

    const value = clean(changes[name] ?? "");

    if (name === "class" && !isClass(value)) {
      return { error: "Tuntematon luokka.", status: 400 };
    }
    if (name === "raid_role" && !isRaidRole(value)) {
      return { error: "Tuntematon rooli.", status: 400 };
    }

    columns.push(`${name} = ?`);
    values.push(value === "" ? null : value);
  }

  if (columns.length === 0) return { ok: true, username: target.username };

  // The class and the role have to fit together after the change too.
  //
  // Two different situations. If the role is being set, an invalid choice
  // is refused — the user tried something that does not work. If instead
  // the class is being changed and the old role becomes invalid with it,
  // the role is cleared: the officer changed the class, not the role, and
  // the change should not fall over because of it.
  const newClass = Object.hasOwn(changes, "class")
    ? String(changes.class ?? "").trim()
    : target.class;
  const newRole = Object.hasOwn(changes, "raid_role")
    ? String(changes.raid_role ?? "").trim()
    : target.raid_role;

  let clearedRole = null;

  if (!roleFitsClass(newClass, newRole)) {
    if (Object.hasOwn(changes, "raid_role")) {
      return { error: roleError(newClass, newRole), status: 400 };
    }

    clearedRole = newRole;
    if (!columns.includes("raid_role = ?")) {
      columns.push("raid_role = ?");
      values.push(null);
    }
  }

  await env.DB.prepare(`UPDATE users SET ${columns.join(", ")} WHERE id = ?`)
    .bind(...values, target.id)
    .run();

  // What changed and to what, not the SQL statement. This used to log
  // "class = ?, raid_role = ?", which looks broken and says nothing about
  // the values.
  const summary = columns
    .map((c, i) => `${c.replace(" = ?", "")}=${values[i] ?? "—"}`)
    .join(", ");

  await writeLog(env, actor, "UPDATE_CHARACTER", target.username, summary);

  return {
    ok: true,
    username: target.username,
    // Tell the browser if the role was cleared, so the change does not go
    // unnoticed.
    clearedRole: clearedRole ? roleError(newClass, clearedRole) : null,
  };
}

/**
 * Imports the addon's loot history.
 *
 * The format is the addon's export as-is:
 *
 *   LOOTHIST1
 *   RAID=Molten Core
 *   TIME=2026-10-10 20:05:00
 *   ZONE=Molten Core
 *   SIZE=40
 *   L=<itemId>|<winner>|<time>|<roll or ->|<response or ->|<zone>
 *
 * Everything after the RAID and TIME lines is optional: an older addon
 * version did not send them, and an old export must still import.
 *
 * Every import is its own log. One week can hold one 40-man and a couple
 * of 20-mans, run by different masters on different nights — merged into
 * one pile you could not tell afterwards which night was which.
 *
 * Importing rows is idempotent: the table's UNIQUE prevents the same row
 * being stored twice, so the same export can be imported again. That
 * matters because importing is manual work, and manual work gets
 * repeated. The log is created every time anyway, and shows that the
 * import was empty.
 */
export async function importHistory(env, actor, text, labelInput) {
  if (typeof text !== "string" || !text.trim()) {
    return { error: "Teksti puuttuu.", status: 400 };
  }

  const clean = text.replace(/\r/g, "");
  if (!/^\s*LOOTHIST1\b/.test(clean)) {
    return { error: "Tuntematon muoto. Odotettiin LOOTHIST1.", status: 400 };
  }

  const raid = await getActiveRaid(env);
  const raidId = raid ? raid.id : null;

  const header = {
    raid: (clean.match(/^RAID=(.*)$/m)?.[1] ?? "").trim() || null,
    time: (clean.match(/^TIME=(.*)$/m)?.[1] ?? "").trim() || null,
    zone: (clean.match(/^ZONE=(.*)$/m)?.[1] ?? "").trim() || null,
    size: parseInt((clean.match(/^SIZE=(.*)$/m)?.[1] ?? "").trim(), 10),
  };

  // The users in memory once, so there is no query per row.
  const users = await env.DB.prepare(
    `SELECT id, username, character_name, first_name FROM users`
  ).all();

  const byName = new Map();
  for (const u of users.results ?? []) {
    for (const name of [u.username, u.character_name, u.first_name]) {
      if (name) byName.set(String(name).toLowerCase(), u.id);
    }
  }

  const rows = [];
  let skipped = 0;

  for (const match of clean.matchAll(/^L=([^\n]*)$/gm)) {
    const parts = match[1].split("|");
    const itemId = parseInt(parts[0], 10);
    const winner = (parts[1] || "").trim();
    const time = (parts[2] || "").trim();

    if (!Number.isFinite(itemId) || !winner || !time) {
      skipped++;
      continue;
    }

    const roll = parseInt((parts[3] || "").trim(), 10);
    const response = (parts[4] || "").trim().toLowerCase();

    rows.push({
      itemId,
      winner,
      time,
      roll: Number.isFinite(roll) ? roll : null,
      response: RESPONSES.has(response) ? response : null,
      // The zone per row, if the addon sent it. A dash means empty in the
      // addon's language, so it is not a name. The header's value is the
      // fallback: one night's export is usually from one place.
      zone: emptyDash((parts[5] || "").trim()) || header.zone,
      userId: byName.get(winner.toLowerCase()) ?? null,
    });
  }

  if (rows.length === 0) {
    return { error: "Yhtään riviä ei löytynyt.", status: 400 };
  }

  // The log first, so the rows can be attached to it. The counts are
  // updated afterwards — they are not known until we know what got in.
  const logInsert = await env.DB.prepare(
    `INSERT INTO loot_import
       (label, zone, raid_size, source_raid, source_time, imported_by, raw_text)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      (typeof labelInput === "string" && labelInput.trim().slice(0, 60)) || null,
      header.zone,
      Number.isFinite(header.size) ? header.size : null,
      header.raid,
      header.time,
      actor,
      clean
    )
    .run();

  const importId = logInsert.meta?.last_row_id ?? null;

  // In batches, because batch takes a limited number at a time.
  let written = 0;
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50).map((r) =>
      env.DB.prepare(
        `INSERT INTO loot_history
           (raid_id, import_id, item_id, winner, user_id, response, roll,
            zone, awarded_at, awarded_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(item_id, winner, awarded_at) DO NOTHING`
      ).bind(raidId, importId, r.itemId, r.winner, r.userId, r.response, r.roll,
        r.zone, r.time, actor)
    );

    const results = await env.DB.batch(batch);
    for (const result of results) written += result.meta?.changes ?? 0;
  }

  await env.DB.prepare(
    `UPDATE loot_import
        SET rows_total = ?, rows_new = ?, rows_skipped = ?
      WHERE id = ?`
  )
    .bind(rows.length, written, skipped, importId)
    .run();

  await writeLog(env, actor, "IMPORT_HISTORY", String(importId),
    `${rows.length} riviä, ${written} uutta`);

  return {
    ok: true,
    id: importId,
    rows: rows.length,
    added: written,
    skipped,
    unmatched: rows.filter((r) => !r.userId).length,
  };
}

/** Looks up a user by name for the profile view. */
export async function getUserByName(env, username) {
  return await env.DB.prepare(
    `SELECT id, username, role, character_name, first_name, last_name,
            class, raid_role, avatar_key, locked, protected
       FROM users WHERE username = ?`
  )
    .bind(username)
    .first();
}

/** A user locks their own profile as finished. */
export async function lockOwn(env, user) {
  await env.DB.prepare("UPDATE users SET locked = 1 WHERE id = ?")
    .bind(user.id)
    .run();
  await writeLog(env, user.username, "LOCK_OWN", user.username, null);
  return { ok: true, locked: 1 };
}

/**
 * The export to the addon.
 *
 * The format is line-based rather than JSON, because the addon parses it
 * in Lua. A line-based format is read with a few gmatch calls; JSON would
 * need a parser or a library.
 *
 *   LOOTPRIO1
 *   RAID=<raid name>
 *   TIME=<export time, UTC>
 *   SLOTS=head,neck,shoulder,...
 *   P=<character>|<slot>:<itemId>,<slot>:<itemId>,...
 *   S=<character>|<items received in total>
 *   A=<character>|<other spelling>,<other spelling>
 *   O=<character>,<character>,...
 *
 * Pipe and comma do not occur in character names or numbers, so the
 * separators need no escaping.
 *
 * The S lines are there because the addon's own history is one machine's
 * view and is cleared by hand. Without them the master's second most
 * important number — how many each has already received — is zero as
 * soon as the master changes or the addon is reinstalled.
 *
 * The A lines are the character's other spellings: "first last" and the
 * username. The addon compares profiles against the name the game gives,
 * and the website cannot know which form the game uses. Sending the
 * alternatives is safer than guessing: a wrong guess would show up only
 * as nobody's profile matching anybody — which is exactly the bug the
 * export had.
 *
 * The O line is the guild's officers. The addon has no network access and
 * cannot ask who has rights, so without this it would have to trust raid
 * rank alone — and raid assist is often handed out for markers, not
 * loot. This way a spare assist does not open a distribution.
 */
export async function buildExport(env) {
  const raid = await getActiveRaid(env);
  if (!raid) return { error: "Aktiivista raidia ei ole.", status: 409 };

  // The protected admin account is left out everywhere: it is not a
  // character and does not belong in a raid, and in the addon's list it
  // would be a row nothing can be awarded to.
  const pickRows = await env.DB.prepare(
    `SELECT ${CHARACTER_NAME} AS character, p.slot_key, p.item_id
       FROM picks p
       JOIN users u ON u.id = p.user_id
      WHERE p.raid_id = ? AND u.protected = 0
      ORDER BY character COLLATE NOCASE, p.slot_key`
  )
    .bind(raid.id)
    .all();

  // Received items across the whole history, not just this raid: the
  // fairness of distribution is judged across a tier, not within one
  // night.
  //
  // Rows whose winner was never matched to an account are included too —
  // the name is enough for the addon, and dropping them would falsify
  // the number.
  const received = await env.DB.prepare(
    `SELECT character, SUM(n) AS n FROM (
       SELECT ${CHARACTER_NAME} AS character, COUNT(*) AS n
         FROM loot_history h
         JOIN users u ON u.id = h.user_id
        WHERE u.protected = 0
        GROUP BY character
       UNION ALL
       SELECT h.winner AS character, COUNT(*) AS n
         FROM loot_history h
        WHERE h.user_id IS NULL
        GROUP BY h.winner
     )
     GROUP BY character
     ORDER BY character COLLATE NOCASE`
  ).all();

  const members = await env.DB.prepare(
    `SELECT ${CHARACTER_NAME} AS character, u.username, u.first_name,
            u.last_name, u.role
       FROM users u
      WHERE u.protected = 0
      ORDER BY character COLLATE NOCASE`
  ).all();

  const byCharacter = new Map();
  for (const row of pickRows.results ?? []) {
    if (!byCharacter.has(row.character)) byCharacter.set(row.character, []);
    byCharacter.get(row.character).push(`${row.slot_key}:${row.item_id}`);
  }

  const out = [
    "LOOTPRIO1",
    `RAID=${raid.name}`,
    `TIME=${new Date().toISOString().slice(0, 19).replace("T", " ")}`,
    `SLOTS=${SLOTS.map((s) => s.key).join(",")}`,
  ];

  for (const [character, picks] of byCharacter) {
    out.push(`P=${character}|${picks.join(",")}`);
  }
  for (const row of received.results ?? []) {
    if (row.character && row.n > 0) out.push(`S=${row.character}|${row.n}`);
  }

  for (const u of members.results ?? []) {
    const first = (u.first_name ?? "").trim();
    const last = (u.last_name ?? "").trim();

    // A comma or a pipe would break the line, so such names are left out
    // rather than escaped.
    const others = [first && last ? `${first} ${last}` : null, u.username]
      .filter((n) => n && n !== u.character && !/[|,]/.test(n));

    if (others.length) {
      out.push(`A=${u.character}|${[...new Set(others)].join(",")}`);
    }
  }

  const officers = (members.results ?? [])
    .filter((u) => u.role === "officer" && u.character && !/[|,]/.test(u.character))
    .map((u) => u.character);

  if (officers.length) out.push(`O=${officers.join(",")}`);

  return {
    ok: true,
    raid: raid.name,
    characters: byCharacter.size,
    text: out.join("\n"),
  };
}

async function writeLog(env, actor, action, target, details) {
  try {
    await env.DB.prepare(
      "INSERT INTO audit_log (actor, action, target, details) VALUES (?, ?, ?, ?)"
    )
      .bind(actor, action, target, details)
      .run();
  } catch {
    // The log must not break the action it is recording. A failed write
    // is worth less than a failed role change.
  }
}
