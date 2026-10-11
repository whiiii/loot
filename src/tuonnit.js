/**
 * Tuontilokit: mita addonista on tuotu, milloin ja kenen toimesta.
 *
 * Kaksi tehtavaa. Ensinnakin se on loki: viikossa voi olla yksi 40-man ja
 * pari 20-man, eri lootmastereilla, ja jalkikateen kysytaan kuka toi mita
 * ja milloin. Toiseksi se on varmuuskopio: addonin alkuperainen teksti on
 * tallessa sellaisenaan, joten rivit voi tuoda uudelleen vaikka kannasta
 * katoaisi jotain.
 */

/** Lokit uusin ensin, ilman raakatekstia - se haetaan vain pyydettaessa. */
export async function haeTuonnit(env, raja = 50) {
  const rivit = await env.DB.prepare(
    `SELECT i.id, i.label, i.zone, i.raid_size, i.source_raid, i.source_time,
            i.imported_by, i.imported_at,
            i.rows_total, i.rows_new, i.rows_skipped,
            LENGTH(i.raw_text) AS raw_koko,
            (SELECT COUNT(*) FROM loot_history h WHERE h.import_id = i.id)
              AS rivit_jaljella
       FROM loot_import i
      ORDER BY i.imported_at DESC, i.id DESC
      LIMIT ?`
  )
    .bind(Math.min(Math.max(parseInt(raja, 10) || 50, 1), 200))
    .all();

  return { tuonnit: rivit.results ?? [] };
}

/**
 * Yhden lokin tiedot: rivit ja alkuperainen teksti.
 *
 * Hahmonimi haetaan kayttajataulusta jos voittaja tunnistettiin. Jos ei,
 * nayttoon jaa pelin antama nimi - historia ei saa kadota siita etta
 * pelaaja on lahtenyt killasta.
 */
export async function haeTuonti(env, id) {
  const loki = await env.DB.prepare(
    `SELECT id, label, zone, raid_size, source_raid, source_time,
            imported_by, imported_at, rows_total, rows_new, rows_skipped,
            raw_text
       FROM loot_import WHERE id = ?`
  )
    .bind(id)
    .first();

  if (!loki) return { error: "Tuontia ei löydy.", status: 404 };

  const rivit = await env.DB.prepare(
    `SELECT h.id, h.item_id, h.winner, h.user_id, h.response, h.roll,
            h.zone, h.awarded_at
       FROM loot_history h
      WHERE h.import_id = ?
      ORDER BY h.awarded_at, h.id`
  )
    .bind(id)
    .all();

  return { ok: true, tuonti: loki, rivit: rivit.results ?? [] };
}

/**
 * Poistaa tuonnin ja sen rivit.
 *
 * Rivit ensin ja loki vasta sen jalkeen: jos poisto katkeaa valiin, jaljelle
 * jaa loki ilman riveja eika rivit ilman lokia. Orpo rivi nakyisi lukuina
 * joiden alkuperaa ei voi jaljittaa.
 *
 * Huom: vain tasta tuonnista syntyneet rivit haviavat. Jos sama palkinto
 * tuotiin jo aiemmin, rivi kuuluu siihen aiempaan tuontiin ja jaa
 * paikalleen - niin kuuluukin.
 */
export async function poistaTuonti(env, actor, id) {
  const loki = await env.DB.prepare(
    "SELECT id, label, zone, imported_by, rows_new FROM loot_import WHERE id = ?"
  )
    .bind(id)
    .first();

  if (!loki) return { error: "Tuontia ei löydy.", status: 404 };

  const poistetut = await env.DB.prepare(
    "DELETE FROM loot_history WHERE import_id = ?"
  )
    .bind(id)
    .run();

  await env.DB.prepare("DELETE FROM loot_import WHERE id = ?").bind(id).run();

  return {
    ok: true,
    id,
    poistettuja: poistetut.meta?.changes ?? 0,
  };
}
