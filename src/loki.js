/**
 * Toimintoloki: kuka teki, mita, kenelle ja milloin.
 *
 * Officer nakee lokin mutta ei voi muuttaa sita miksikaan - ei muokata
 * eika poistaa. Loki jonka kohde voi siivota ei ole loki vaan muistiinpano,
 * ja juuri ne rivit jotka halutaan pois ovat ne joiden takia loki on
 * olemassa.
 *
 * Poistaminen on vain suojatulla yllapitotunnuksella. Se ei ole killan
 * arvo vaan sivuston varauloskaynti, eika sita voi antaa itselleen.
 */

/** Toiminnot selkokielella. Tunnus kannassa, teksti tassa. */
export const TOIMINNOT = {
  LUKITSE: "Lukitsi profiilin",
  AVAA_LUKKO: "Avasi lukon",
  LUKITSE_OMA: "Lukitsi oman profiilinsa",
  VAIHDA_ROOLI: "Vaihtoi roolin",
  VAIHDA_SALASANA: "Vaihtoi salasanan",
  LUO_KAYTTAJA: "Loi jäsenen",
  POISTA_KAYTTAJA: "Poisti jäsenen",
  PAIVITA_HAHMO: "Muokkasi hahmoa",
  TUO_HISTORIA: "Toi loottihistorian",
  POISTA_TUONTI: "Poisti tuonnin",
  POISTA_LOKI: "Poisti lokirivin",
};

/**
 * Lokirivit uusin ensin.
 *
 * Suodatus toiminnon ja kohteen mukaan, koska lokista haetaan yleensa
 * yhta asiaa: "kuka avasi taman lukon" tai "mita tanaan tapahtui".
 */
export async function haeLoki(env, asetukset = {}) {
  const raja = Math.min(Math.max(parseInt(asetukset.raja, 10) || 200, 1), 500);

  const ehdot = [];
  const arvot = [];

  if (asetukset.toiminto && TOIMINNOT[asetukset.toiminto]) {
    ehdot.push("action = ?");
    arvot.push(asetukset.toiminto);
  }

  if (asetukset.kohde) {
    ehdot.push("(LOWER(target) = LOWER(?) OR LOWER(actor) = LOWER(?))");
    arvot.push(asetukset.kohde, asetukset.kohde);
  }

  const missa = ehdot.length ? `WHERE ${ehdot.join(" AND ")}` : "";

  const rivit = await env.DB.prepare(
    `SELECT id, actor, action, target, details, created_at
       FROM audit_log
       ${missa}
      ORDER BY created_at DESC, id DESC
      LIMIT ?`
  )
    .bind(...arvot, raja)
    .all();

  return { loki: rivit.results ?? [] };
}

/**
 * Poistaa yhden lokirivin.
 *
 * Poisto kirjataan itse lokiin. Muuten lokista voisi poistaa jalkensa
 * jattamatta jalkea, ja silloin koko loki olisi arvoton.
 */
export async function poistaLokirivi(env, actor, id) {
  const rivi = await env.DB.prepare(
    "SELECT id, actor, action, target FROM audit_log WHERE id = ?"
  )
    .bind(id)
    .first();

  if (!rivi) return { error: "Lokiriviä ei löydy.", status: 404 };

  await env.DB.prepare("DELETE FROM audit_log WHERE id = ?").bind(id).run();

  await env.DB.prepare(
    `INSERT INTO audit_log (actor, action, target, details)
     VALUES (?, 'POISTA_LOKI', ?, ?)`
  )
    .bind(actor, rivi.target,
      `#${rivi.id} ${rivi.action} (${rivi.actor})`)
    .run();

  return { ok: true, id };
}
