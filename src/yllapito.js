/**
 * Officerin tyokalut: kayttajalista, lukot ja vienti addoniin.
 */
import { haeAktiiviRaidi, PAIKAT } from "./valinnat.js";

/** Kayttajat ja se montako valintaa kullakin on aktiivisessa raidissa. */
export async function haeKayttajat(env) {
  const raidi = await haeAktiiviRaidi(env);
  const raidId = raidi ? raidi.id : 0;

  const rivit = await env.DB.prepare(
    `SELECT u.id, u.username, u.character_name, u.role, u.locked,
            u.created_at, u.last_login_at,
            (SELECT COUNT(*) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?) AS valintoja
       FROM users u
      ORDER BY
        CASE u.role WHEN 'officer' THEN 0 WHEN 'raider' THEN 1 ELSE 2 END,
        u.username COLLATE NOCASE`
  )
    .bind(raidId)
    .all();

  return {
    raid: raidi ? { id: raidi.id, name: raidi.name } : null,
    paikkoja: PAIKAT.length,
    users: rivit.results ?? [],
  };
}

/**
 * Avaa tai sulkee profiilin lukon.
 *
 * Officerin omaa lukkoa ei tarvitse koskea, koska lukko ei rajoita hanta -
 * mutta se sallitaan silti, jotta tila on yhtenainen.
 */
export async function asetaLukko(env, actor, username, locked) {
  const kohde = await env.DB.prepare(
    "SELECT id, username, locked FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!kohde) return { error: "Käyttäjää ei löydy.", status: 404 };

  await env.DB.prepare("UPDATE users SET locked = ? WHERE id = ?")
    .bind(locked ? 1 : 0, kohde.id)
    .run();

  await kirjaa(env, actor, locked ? "LUKITSE" : "AVAA_LUKKO", kohde.username, null);
  return { ok: true, username: kohde.username, locked: locked ? 1 : 0 };
}

/** Kayttaja lukitsee oman profiilinsa valmiiksi. */
export async function lukitseOma(env, kayttaja) {
  await env.DB.prepare("UPDATE users SET locked = 1 WHERE id = ?")
    .bind(kayttaja.id)
    .run();
  await kirjaa(env, kayttaja.username, "LUKITSE_OMA", kayttaja.username, null);
  return { ok: true, locked: 1 };
}

/**
 * Vienti addoniin.
 *
 * Muoto on rivipohjainen eika JSON, koska addon jasentaa sen Luassa.
 * Rivipohjaisen muodon lukee muutamalla gmatch-kutsulla; JSON vaatisi
 * oman jasentimen tai kirjaston.
 *
 *   LOOTPRIO1
 *   RAID=<raidin nimi>
 *   TIME=<vientihetki UTC>
 *   SLOTS=head,neck,shoulder,...
 *   P=<hahmo>|<paikka>:<itemId>,<paikka>:<itemId>,...
 *
 * Pystyviiva ja pilkku eivat esiinny hahmonimissa eivatka numeroissa,
 * joten erottimia ei tarvitse suojata.
 */
export async function teeVienti(env) {
  const raidi = await haeAktiiviRaidi(env);
  if (!raidi) return { error: "Aktiivista raidia ei ole.", status: 409 };

  const rivit = await env.DB.prepare(
    `SELECT COALESCE(NULLIF(u.character_name, ''), u.username) AS hahmo,
            p.slot_key, p.item_id
       FROM picks p
       JOIN users u ON u.id = p.user_id
      WHERE p.raid_id = ?
      ORDER BY hahmo COLLATE NOCASE, p.slot_key`
  )
    .bind(raidi.id)
    .all();

  const perHahmo = new Map();
  for (const r of rivit.results ?? []) {
    if (!perHahmo.has(r.hahmo)) perHahmo.set(r.hahmo, []);
    perHahmo.get(r.hahmo).push(`${r.slot_key}:${r.item_id}`);
  }

  const out = [
    "LOOTPRIO1",
    `RAID=${raidi.name}`,
    `TIME=${new Date().toISOString().slice(0, 19).replace("T", " ")}`,
    `SLOTS=${PAIKAT.map((p) => p.key).join(",")}`,
  ];
  for (const [hahmo, valinnat] of perHahmo) {
    out.push(`P=${hahmo}|${valinnat.join(",")}`);
  }

  return {
    ok: true,
    raid: raidi.name,
    hahmoja: perHahmo.size,
    teksti: out.join("\n"),
  };
}

async function kirjaa(env, actor, action, target, details) {
  try {
    await env.DB.prepare(
      "INSERT INTO audit_log (actor, action, target, details) VALUES (?, ?, ?, ?)"
    )
      .bind(actor, action, target, details)
      .run();
  } catch {
    /* loki ei saa kaataa varsinaista toimintoa */
  }
}
