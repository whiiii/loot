/**
 * Officerin tyokalut: kayttajalista, lukot ja vienti addoniin.
 */
import { haeAktiiviRaidi, PAIKAT } from "./valinnat.js";
import { hashPassword } from "./auth.js";
import { haeItemTiedot } from "./itemit.js";
import {
  LUOKAN_ROOLIT,
  LUOKAT,
  RAIDIROOLIT,
  onLuokka,
  onRaidirooli,
  rooliSopii,
} from "./hahmo.js";

/**
 * Jaon perusteet eli addonin vastausnappien koodit.
 *
 * Tuonti hyvaksyy vain nama: muu arvo tulisi muokatusta addonista, eika
 * sellaista kannata paastaa kantaan nakymiin asti. "pass" ei ole mukana -
 * passannut ei voi voittaa itemia.
 */
const PERUSTEET = new Set(["prio", "main", "off", "muu"]);

/**
 * Hahmon nimi pelissa, SQL-lausekkeena.
 *
 * Addon vertaa tata UnitName("player")-nimeen, joten kyse on nimenomaan
 * hahmon nimesta eika tunnuksesta tai koko nimesta. first_name on se
 * sarake johon migraatio v4 siirsi vanhan character_name-arvon, ja uudet
 * jasenet saavat vain sen - character_name jai tyhjaksi.
 *
 * Yhdessa paikassa, koska kaksi erilaista totuutta samasta nimesta on
 * juuri se virhe jonka takia viennissa oli vaara nimi.
 */
const HAHMONIMI =
  "COALESCE(NULLIF(u.first_name, ''), NULLIF(u.character_name, ''), u.username)";

/** Selkokielinen virheilmoitus kelpaamattomasta luokka-rooli-parista. */
function rooliVirhe(luokka, rooli) {
  const luokanNimi = LUOKAT[luokka] ? LUOKAT[luokka].nimi : luokka;
  const sallitut = (LUOKAN_ROOLIT[luokka] || [])
    .map((r) => RAIDIROOLIT[r])
    .join(", ");

  return `${luokanNimi} ei voi olla ${RAIDIROOLIT[rooli] || rooli}. Sallitut: ${sallitut}.`;
}

/**
 * Loottihistorian ja kayttajan yhdistava ehto, SQL-lausekkeena.
 *
 * Voittaja on hahmon nimi pelista, ja se yhdistetaan tunnukseen jos
 * sellainen loytyi tuonnissa. Nimivertailu on mukana siksi, etta tuonti
 * saattoi tapahtua ennen kuin tunnus oli olemassa - historia ei saa kadota
 * siita etta rivi kirjattiin vaarassa jarjestyksessa.
 */
const HISTORIA_OSUU = `(
  h.user_id = u.id
  OR LOWER(h.winner) = LOWER(COALESCE(u.first_name, ''))
  OR LOWER(h.winner) = LOWER(COALESCE(u.character_name, ''))
  OR LOWER(h.winner) = LOWER(COALESCE(u.username, ''))
)`;

/**
 * Kayttajat seka valintojen ja saatujen maara aktiivisessa raidissa.
 *
 * Saatuja lasketaan vain profiilissa olevista itemeista: luku vastaa
 * kysymykseen "montako valitsemaansa han on jo saanut", ei sita montako
 * itemia han on kaikkiaan saanut. Jalkimmainen on addonin SAATU-sarake ja
 * eri asia.
 */
export async function haeKayttajat(env) {
  const raidi = await haeAktiiviRaidi(env);
  const raidId = raidi ? raidi.id : 0;

  const rivit = await env.DB.prepare(
    `SELECT u.id, u.username, u.character_name, u.first_name, u.last_name,
            u.class, u.raid_role, u.role, u.locked, u.avatar_key,
            u.created_at, u.last_login_at,
            (SELECT COUNT(*) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?) AS valintoja,
            (SELECT COUNT(DISTINCT p.item_id) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?
                AND EXISTS (SELECT 1 FROM loot_history h
                             WHERE h.item_id = p.item_id
                               AND ${HISTORIA_OSUU})) AS saatuja
       FROM users u
      ORDER BY
        CASE u.role WHEN 'officer' THEN 0 WHEN 'raider' THEN 1 ELSE 2 END,
        u.username COLLATE NOCASE`
  )
    .bind(raidId, raidId)
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

export const ROOLIT = ["social", "raider", "officer"];

/**
 * Vaihtaa kayttajan roolin.
 *
 * Viimeista officeria ei voi alentaa. Ilman tata kilta voi jaada ilman
 * yllapitoa yhdella klikkauksella, eika sita saa itse korjattua - lukkojen
 * avaus ja roolien vaihto vaativat juuri sen roolin joka juuri katosi.
 */
export async function vaihdaRooli(env, actor, username, rooli) {
  if (!ROOLIT.includes(rooli)) return { error: "Tuntematon rooli.", status: 400 };

  const kohde = await env.DB.prepare(
    "SELECT id, username, role FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!kohde) return { error: "Käyttäjää ei löydy.", status: 404 };
  if (kohde.role === rooli) return { ok: true, username: kohde.username, role: rooli };

  if (kohde.role === "officer" && rooli !== "officer") {
    const rivi = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM users WHERE role = 'officer'"
    ).first();

    if ((rivi?.n ?? 0) <= 1) {
      return {
        error: "Tämä on viimeinen officer. Nimeä ensin toinen officer.",
        status: 409,
      };
    }
  }

  await env.DB.prepare("UPDATE users SET role = ? WHERE id = ?")
    .bind(rooli, kohde.id)
    .run();

  await kirjaa(env, actor, "VAIHDA_ROOLI", kohde.username, `${kohde.role} -> ${rooli}`);
  return { ok: true, username: kohde.username, role: rooli };
}

export const SALASANA_MIN = 6;

/** Tunnuksessa vain kirjaimia, numeroita, alaviiva ja valiviiva. */
const TUNNUS_SAANTO = /^[A-Za-z0-9_-]{3,20}$/;

/**
 * Luo uuden kayttajan.
 *
 * Hahmon nimi saa olla tyhja, jolloin se on sama kuin tunnus. Useimmissa
 * killoissa ne ovat sama asia, eika turhaa kenttaa kannata pakottaa.
 */
export async function luoKayttaja(env, actor, tiedot) {
  const tunnus = String(tiedot.username ?? "").trim();
  const etunimi = String(tiedot.first_name ?? "").trim();
  const sukunimi = String(tiedot.last_name ?? "").trim();
  const luokka = String(tiedot.class ?? "").trim();
  const raidirooli = String(tiedot.raid_role ?? "").trim();
  const rooli = String(tiedot.role ?? "raider");
  const salasana = String(tiedot.password ?? "");

  if (!onLuokka(luokka)) return { error: "Tuntematon luokka.", status: 400 };
  if (!onRaidirooli(raidirooli)) return { error: "Tuntematon rooli.", status: 400 };
  if (!rooliSopii(luokka, raidirooli)) {
    return { error: rooliVirhe(luokka, raidirooli), status: 400 };
  }

  if (!TUNNUS_SAANTO.test(tunnus)) {
    return {
      error:
        "Tunnus: 3–20 merkkiä, vain kirjaimia, numeroita, alaviiva tai väliviiva.",
      status: 400,
    };
  }
  if (!ROOLIT.includes(rooli)) return { error: "Tuntematon rooli.", status: 400 };
  if (salasana.length < SALASANA_MIN) {
    return {
      error: `Salasanan on oltava vähintään ${SALASANA_MIN} merkkiä.`,
      status: 400,
    };
  }

  const varattu = await env.DB.prepare(
    "SELECT id FROM users WHERE username = ?"
  )
    .bind(tunnus)
    .first();

  if (varattu) return { error: "Tunnus on jo käytössä.", status: 409 };

  const tiiviste = await hashPassword(salasana);

  await env.DB.prepare(
    `INSERT INTO users
       (username, password_hash, role, first_name, last_name, class, raid_role)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  )
    .bind(
      tunnus,
      tiiviste,
      rooli,
      etunimi || tunnus,
      sukunimi || null,
      luokka || null,
      raidirooli || null
    )
    .run();

  await kirjaa(env, actor, "LUO_KAYTTAJA", tunnus, `rooli=${rooli}`);
  return { ok: true, username: tunnus };
}

/**
 * Poistaa kayttajan.
 *
 * Valinnat ja istunnot katoavat mukana, mutta loottihistoria ei: siina
 * viite kayttajaan tyhjenee ja hahmon nimi jaa. Historian kuuluu kertoa
 * mita raidissa tapahtui, ei sita ketka ovat yha killassa.
 *
 * Viimeista officeria ei voi poistaa, eika itseaan - kumpikin jattaisi
 * tilanteen jota ei saa itse korjattua.
 */
export async function poistaKayttaja(env, actor, username) {
  const kohde = await env.DB.prepare(
    "SELECT id, username, role FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!kohde) return { error: "Käyttäjää ei löydy.", status: 404 };

  if (kohde.username.toLowerCase() === String(actor).toLowerCase()) {
    return { error: "Et voi poistaa omaa tunnustasi.", status: 409 };
  }

  if (kohde.role === "officer") {
    const rivi = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM users WHERE role = 'officer'"
    ).first();

    if ((rivi?.n ?? 0) <= 1) {
      return {
        error: "Tämä on viimeinen officer. Nimeä ensin toinen officer.",
        status: 409,
      };
    }
  }

  await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(kohde.id).run();

  await kirjaa(env, actor, "POISTA_KAYTTAJA", kohde.username, `rooli=${kohde.role}`);
  return { ok: true, username: kohde.username };
}

/**
 * Officer asettaa kayttajalle uuden salasanan.
 *
 * Vanhoja istuntoja ei jateta voimaan. Salasanan vaihto on usein juuri se
 * hetki jolloin halutaan katkaista paasy - jos istunnot jaisivat elamaan,
 * vaihto ei tekisi sita mita siita odotetaan.
 */
export async function asetaSalasana(env, actor, username, salasana) {
  if (String(salasana).length < SALASANA_MIN) {
    return {
      error: `Salasanan on oltava vähintään ${SALASANA_MIN} merkkiä.`,
      status: 400,
    };
  }

  const kohde = await env.DB.prepare(
    "SELECT id, username FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!kohde) return { error: "Käyttäjää ei löydy.", status: 404 };

  const tiiviste = await hashPassword(salasana);

  await env.DB.batch([
    env.DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?").bind(
      tiiviste,
      kohde.id
    ),
    env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(kohde.id),
  ]);

  // Salasanaa ei kirjata lokiin missaan muodossa.
  await kirjaa(env, actor, "VAIHDA_SALASANA", kohde.username, null);
  return { ok: true, username: kohde.username };
}

/**
 * Officer paivittaa hahmon tiedot.
 *
 * Vain lahetetyt kentat muutetaan. Sama saanto kuin Roihutreffeissa opittiin
 * kantapaan kautta: puuttuva kentta ei tarkoita "tyhjenna tama", vaan etta
 * kutsuja ei puhunut siita mitaan.
 */
export async function paivitaHahmo(env, actor, username, muutokset) {
  const kohde = await env.DB.prepare(
    "SELECT id, username, class, raid_role FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  if (!kohde) return { error: "Käyttäjää ei löydy.", status: 404 };

  const sallitut = {
    first_name: (v) => String(v).trim().slice(0, 40),
    last_name: (v) => String(v).trim().slice(0, 40),
    class: (v) => String(v).trim(),
    raid_role: (v) => String(v).trim(),
  };

  const kentat = [];
  const arvot = [];

  for (const [nimi, siivoa] of Object.entries(sallitut)) {
    if (!Object.hasOwn(muutokset, nimi)) continue;

    const arvo = siivoa(muutokset[nimi] ?? "");

    if (nimi === "class" && !onLuokka(arvo)) {
      return { error: "Tuntematon luokka.", status: 400 };
    }
    if (nimi === "raid_role" && !onRaidirooli(arvo)) {
      return { error: "Tuntematon rooli.", status: 400 };
    }

    kentat.push(`${nimi} = ?`);
    arvot.push(arvo === "" ? null : arvo);
  }

  if (kentat.length === 0) return { ok: true, username: kohde.username };

  // Luokan ja roolin on sovittava yhteen myos muutoksen jalkeen.
  //
  // Kaksi eri tilannetta. Jos roolia ollaan asettamassa, kelpaamaton valinta
  // torjutaan - kayttaja yritti jotain mika ei kay. Jos taas luokkaa
  // vaihdetaan ja vanha rooli jaa sen myota kelvottomaksi, rooli
  // tyhjennetaan: officer vaihtoi luokan, ei roolia, eika muutoksen kuulu
  // kaatua siihen.
  const uusiLuokka = Object.hasOwn(muutokset, "class")
    ? String(muutokset.class ?? "").trim()
    : kohde.class;
  const uusiRooli = Object.hasOwn(muutokset, "raid_role")
    ? String(muutokset.raid_role ?? "").trim()
    : kohde.raid_role;

  let roolinTyhjennys = null;

  if (!rooliSopii(uusiLuokka, uusiRooli)) {
    if (Object.hasOwn(muutokset, "raid_role")) {
      return { error: rooliVirhe(uusiLuokka, uusiRooli), status: 400 };
    }

    roolinTyhjennys = uusiRooli;
    if (!kentat.includes("raid_role = ?")) {
      kentat.push("raid_role = ?");
      arvot.push(null);
    }
  }

  await env.DB.prepare(`UPDATE users SET ${kentat.join(", ")} WHERE id = ?`)
    .bind(...arvot, kohde.id)
    .run();

  await kirjaa(env, actor, "PAIVITA_HAHMO", kohde.username, kentat.join(", "));

  return {
    ok: true,
    username: kohde.username,
    // Kerrotaan selaimelle jos rooli tyhjennettiin, jottei muutos jaa
    // kayttajalta huomaamatta.
    roolinTyhjennys: roolinTyhjennys
      ? rooliVirhe(uusiLuokka, roolinTyhjennys)
      : null,
  };
}

/**
 * Tuo addonin loottihistorian.
 *
 * Muoto on addonin vienti sellaisenaan:
 *
 *   LOOTHIST1
 *   RAID=Molten Core
 *   TIME=2026-10-10 20:05:00
 *   L=<itemId>|<voittaja>|<aika>|<roll tai ->|<peruste tai ->
 *
 * Kaksi viimeista kenttaa ovat vapaaehtoisia: addonin vanhempi versio ei
 * lahettanyt niita, ja vanha vienti pitaa silti voida tuoda.
 *
 * Tuonti on idempotentti: taulun UNIQUE estaa saman rivin kahdentumisen,
 * joten saman viennin voi tuoda uudelleen. Se on olennaista, koska tuonti
 * on kasityota eika kasityon toistumista voi estaa.
 */
export async function tuoHistoria(env, actor, teksti) {
  if (typeof teksti !== "string" || !teksti.trim()) {
    return { error: "Teksti puuttuu.", status: 400 };
  }

  const siisti = teksti.replace(/\r/g, "");
  if (!/^\s*LOOTHIST1\b/.test(siisti)) {
    return { error: "Tuntematon muoto. Odotettiin LOOTHIST1.", status: 400 };
  }

  const raidi = await haeAktiiviRaidi(env);
  const raidId = raidi ? raidi.id : null;

  // Kayttajat kerran muistiin, jottei jokaista rivia kohden tehda kyselya.
  const kayttajat = await env.DB.prepare(
    `SELECT id, username, character_name, first_name FROM users`
  ).all();

  const nimella = new Map();
  for (const u of kayttajat.results ?? []) {
    for (const nimi of [u.username, u.character_name, u.first_name]) {
      if (nimi) nimella.set(String(nimi).toLowerCase(), u.id);
    }
  }

  const rivit = [];
  let ohitettu = 0;

  for (const rivi of siisti.matchAll(/^L=([^\n]*)$/gm)) {
    const osat = rivi[1].split("|");
    const itemId = parseInt(osat[0], 10);
    const voittaja = (osat[1] || "").trim();
    const aika = (osat[2] || "").trim();

    if (!Number.isFinite(itemId) || !voittaja || !aika) {
      ohitettu++;
      continue;
    }

    // Addon merkitsee puuttuvan kentan viivalla. Tuntematon peruste
    // hylataan: tunnetut koodit tulevat addonin napeista, eika muuta
    // kannata paastaa kantaan talletettavaksi.
    const luku = parseInt((osat[3] || "").trim(), 10);
    const koodi = (osat[4] || "").trim().toLowerCase();

    rivit.push({
      itemId,
      voittaja,
      aika,
      luku: Number.isFinite(luku) ? luku : null,
      koodi: PERUSTEET.has(koodi) ? koodi : null,
      userId: nimella.get(voittaja.toLowerCase()) ?? null,
    });
  }

  if (rivit.length === 0) {
    return { error: "Yhtään riviä ei löytynyt.", status: 400 };
  }

  // Erissa, koska batch ottaa rajallisen maaran kerralla.
  let kirjattu = 0;
  for (let i = 0; i < rivit.length; i += 50) {
    const era = rivit.slice(i, i + 50).map((r) =>
      env.DB.prepare(
        `INSERT INTO loot_history
           (raid_id, item_id, winner, user_id, response, roll,
            awarded_at, awarded_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(item_id, winner, awarded_at) DO NOTHING`
      ).bind(raidId, r.itemId, r.voittaja, r.userId, r.koodi, r.luku,
        r.aika, actor)
    );

    const tulokset = await env.DB.batch(era);
    for (const t of tulokset) kirjattu += t.meta?.changes ?? 0;
  }

  await kirjaa(env, actor, "TUO_HISTORIA", null,
    `${rivit.length} riviä, ${kirjattu} uutta`);

  return {
    ok: true,
    rivit: rivit.length,
    uusia: kirjattu,
    ohitettu,
    tunnistamattomia: rivit.filter((r) => !r.userId).length,
  };
}

/** Hakee kayttajan nimella nakymaa varten. */
export async function haeKayttajaNimella(env, username) {
  return await env.DB.prepare(
    `SELECT id, username, role, character_name, first_name, last_name,
            class, raid_role, avatar_key, locked
       FROM users WHERE username = ?`
  )
    .bind(username)
    .first();
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
 *   S=<hahmo>|<saatuja itemeita yhteensa>
 *   A=<hahmo>|<muu kirjoitusasu>,<muu kirjoitusasu>
 *
 * Pystyviiva ja pilkku eivat esiinny hahmonimissa eivatka numeroissa,
 * joten erottimia ei tarvitse suojata.
 *
 * S-rivit ovat mukana siksi, etta addonin oma historia on vain yhden
 * koneen tieto ja se tyhjennetaan kasin. Ilman naita lootmasterin
 * toiseksi tarkein luku - montako kukin on jo saanut - on nolla heti kun
 * lootmaster vaihtuu tai addon asennetaan uudelleen.
 *
 * A-rivit ovat hahmon muut kirjoitusasut: "etunimi sukunimi" ja tunnus.
 * Addon vertaa profiileja siihen nimeen jonka peli antaa, eika sivusto voi
 * tietaa kumpaa muotoa peli kayttaa. Vaihtoehtojen lahettaminen on
 * varmempaa kuin arvaaminen: vaara arvaus nakyisi vain siina, etta
 * kenenkaan profiili ei osu keneenkaan - ja se on juuri se virhe joka
 * viennissa oli.
 */
export async function teeVienti(env) {
  const raidi = await haeAktiiviRaidi(env);
  if (!raidi) return { error: "Aktiivista raidia ei ole.", status: 409 };

  const rivit = await env.DB.prepare(
    `SELECT ${HAHMONIMI} AS hahmo, p.slot_key, p.item_id
       FROM picks p
       JOIN users u ON u.id = p.user_id
      WHERE p.raid_id = ?
      ORDER BY hahmo COLLATE NOCASE, p.slot_key`
  )
    .bind(raidi.id)
    .all();

  // Saadut itemit koko historiasta, ei vain tasta raidista: jaon
  // oikeudenmukaisuutta katsotaan tierin yli eika yhden illan sisalla.
  //
  // Mukana myos ne rivit joiden voittajaa ei tunnistettu tunnukseksi -
  // nimi riittaa addonille, ja sen pudottaminen vaarentaisi lukua.
  const saadut = await env.DB.prepare(
    `SELECT hahmo, SUM(n) AS n FROM (
       SELECT ${HAHMONIMI} AS hahmo, COUNT(*) AS n
         FROM loot_history h
         JOIN users u ON u.id = h.user_id
        GROUP BY hahmo
       UNION ALL
       SELECT h.winner AS hahmo, COUNT(*) AS n
         FROM loot_history h
        WHERE h.user_id IS NULL
        GROUP BY h.winner
     )
     GROUP BY hahmo
     ORDER BY hahmo COLLATE NOCASE`
  ).all();

  const kayttajat = await env.DB.prepare(
    `SELECT ${HAHMONIMI} AS hahmo, u.username, u.first_name, u.last_name
       FROM users u
      ORDER BY hahmo COLLATE NOCASE`
  ).all();

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
  for (const r of saadut.results ?? []) {
    if (r.hahmo && r.n > 0) out.push(`S=${r.hahmo}|${r.n}`);
  }

  for (const u of kayttajat.results ?? []) {
    const etu = (u.first_name ?? "").trim();
    const suku = (u.last_name ?? "").trim();

    // Pilkku ja pystyviiva rikkoisivat rivin, joten sellaiset nimet
    // jatetaan pois sen sijaan etta erottimet suojattaisiin.
    const muut = [etu && suku ? `${etu} ${suku}` : null, u.username]
      .filter((n) => n && n !== u.hahmo && !/[|,]/.test(n));

    if (muut.length) out.push(`A=${u.hahmo}|${[...new Set(muut)].join(",")}`);
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
