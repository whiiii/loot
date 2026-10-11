/**
 * The action log: who did what, to whom and when.
 *
 * An officer can read the log but cannot change it — not edit, not
 * delete. A log its own subjects can tidy is not a log but a note, and
 * the rows someone wants gone are exactly the rows the log exists for.
 *
 * Deletion is only for the protected admin account. That is not a guild
 * rank but the site's emergency exit, and it cannot be granted to
 * oneself.
 */

/** Actions in plain language. The code lives in the database, the text here. */
export const ACTIONS = {
  LOCK: "Lukitsi profiilin",
  UNLOCK: "Avasi lukon",
  LOCK_OWN: "Lukitsi oman profiilinsa",
  CHANGE_ROLE: "Vaihtoi roolin",
  CHANGE_PASSWORD: "Vaihtoi salasanan",
  CREATE_USER: "Loi jäsenen",
  DELETE_USER: "Poisti jäsenen",
  UPDATE_CHARACTER: "Muokkasi hahmoa",
  IMPORT_HISTORY: "Toi loottihistorian",
  DELETE_IMPORT: "Poisti tuonnin",
  DELETE_LOG: "Poisti lokirivin",
};

/**
 * Log rows, newest first.
 *
 * Filtering by action and by name, because the log is usually searched
 * for one thing: "who opened this lock" or "what happened today".
 */
export async function getLog(env, options = {}) {
  const limit = Math.min(Math.max(parseInt(options.limit, 10) || 200, 1), 500);

  const conditions = [];
  const values = [];

  if (options.action && ACTIONS[options.action]) {
    conditions.push("action = ?");
    values.push(options.action);
  }

  if (options.name) {
    conditions.push("(LOWER(target) = LOWER(?) OR LOWER(actor) = LOWER(?))");
    values.push(options.name, options.name);
  }

  const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";

  const rows = await env.DB.prepare(
    `SELECT id, actor, action, target, details, created_at
       FROM audit_log
       ${where}
      ORDER BY created_at DESC, id DESC
      LIMIT ?`
  )
    .bind(...values, limit)
    .all();

  return { log: rows.results ?? [] };
}

/**
 * Deletes one log row.
 *
 * The deletion is itself written to the log. Otherwise one could remove
 * their tracks without leaving a track, and the whole log would be
 * worthless.
 */
export async function deleteLogRow(env, actor, id) {
  const row = await env.DB.prepare(
    "SELECT id, actor, action, target FROM audit_log WHERE id = ?"
  )
    .bind(id)
    .first();

  if (!row) return { error: "Lokiriviä ei löydy.", status: 404 };

  await env.DB.prepare("DELETE FROM audit_log WHERE id = ?").bind(id).run();

  await env.DB.prepare(
    `INSERT INTO audit_log (actor, action, target, details)
     VALUES (?, 'DELETE_LOG', ?, ?)`
  )
    .bind(actor, row.target, `#${row.id} ${row.action} (${row.actor})`)
    .run();

  return { ok: true, id };
}
