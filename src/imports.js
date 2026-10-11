/**
 * Import logs: what has been imported from the addon, when and by whom.
 *
 * Two jobs. First it is a log: one week can hold one 40-man and a couple
 * of 20-mans, run by different masters, and afterwards someone asks who
 * imported what and when. Second it is a backup: the addon's original
 * text is kept as-is, so the rows can be imported again even if
 * something is lost from the database.
 */

/** Logs newest first, without the raw text — that is fetched on demand. */
export async function getImports(env, limit = 50) {
  const rows = await env.DB.prepare(
    `SELECT i.id, i.label, i.zone, i.raid_size, i.source_raid, i.source_time,
            i.imported_by, i.imported_at,
            i.rows_total, i.rows_new, i.rows_skipped,
            LENGTH(i.raw_text) AS raw_size,
            (SELECT COUNT(*) FROM loot_history h WHERE h.import_id = i.id)
              AS rows_remaining
       FROM loot_import i
      ORDER BY i.imported_at DESC, i.id DESC
      LIMIT ?`
  )
    .bind(Math.min(Math.max(parseInt(limit, 10) || 50, 1), 200))
    .all();

  return { imports: rows.results ?? [] };
}

/**
 * One log's details: its rows and the original text.
 *
 * The winner's name is shown as the game gave it. The history must not
 * disappear because a player has left the guild.
 */
export async function getImport(env, id) {
  const log = await env.DB.prepare(
    `SELECT id, label, zone, raid_size, source_raid, source_time,
            imported_by, imported_at, rows_total, rows_new, rows_skipped,
            raw_text
       FROM loot_import WHERE id = ?`
  )
    .bind(id)
    .first();

  if (!log) return { error: "Tuontia ei löydy.", status: 404 };

  const rows = await env.DB.prepare(
    `SELECT h.id, h.item_id, h.winner, h.user_id, h.response, h.roll,
            h.zone, h.awarded_at
       FROM loot_history h
      WHERE h.import_id = ?
      ORDER BY h.awarded_at, h.id`
  )
    .bind(id)
    .all();

  return { ok: true, import: log, rows: rows.results ?? [] };
}

/**
 * Deletes an import and its rows.
 *
 * The rows first and the log only after: if the deletion breaks halfway,
 * what remains is a log without rows rather than rows without a log. An
 * orphaned row would show up in counts whose origin cannot be traced.
 *
 * Note: only the rows created by this import disappear. If the same
 * award was imported earlier, that row belongs to the earlier import and
 * stays where it is — as it should.
 */
export async function deleteImport(env, actor, id) {
  const log = await env.DB.prepare(
    "SELECT id, label, zone, imported_by, rows_new FROM loot_import WHERE id = ?"
  )
    .bind(id)
    .first();

  if (!log) return { error: "Tuontia ei löydy.", status: 404 };

  const deleted = await env.DB.prepare(
    "DELETE FROM loot_history WHERE import_id = ?"
  )
    .bind(id)
    .run();

  await env.DB.prepare("DELETE FROM loot_import WHERE id = ?").bind(id).run();

  // Logged, because deleting an import also removes items from members'
  // profiles — exactly the kind of act that gets asked about later.
  await env.DB.prepare(
    `INSERT INTO audit_log (actor, action, target, details)
     VALUES (?, 'DELETE_IMPORT', ?, ?)`
  )
    .bind(actor, log.label || log.zone || String(id),
      `${deleted.meta?.changes ?? 0} riviä, toi ${log.imported_by}`)
    .run();

  return {
    ok: true,
    id,
    deleted: deleted.meta?.changes ?? 0,
  };
}
