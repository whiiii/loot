/**
 * Raidin itemit ja raiderin valinnat.
 */

/**
 * Hahmoikkunan paikat siina jarjestyksessa kuin ne ruudulla ovat.
 *
 * Paikka ja slotti ovat eri asioita: sormuksia on kaksi paikkaa mutta vain
 * yksi slotti. Siksi valinta avataan paikan mukaan ja itemit suodatetaan
 * slotin mukaan.
 *
 * Paita ja tabard puuttuvat tarkoituksella - niita ei tipu raideista.
 */
/*
 * Paikkojen nimet ovat englanniksi tarkoituksella. Pelaajat puhuvat
 * sloteista pelin omilla nimilla, ja suomennos ("Sivukasi") on sekava
 * vaikka olisi oikein.
 */
export const PAIKAT = [
  { key: "head",     slot: "head",     nimi: "Head",      puoli: "vasen" },
  { key: "neck",     slot: "neck",     nimi: "Neck",      puoli: "vasen" },
  { key: "shoulder", slot: "shoulder", nimi: "Shoulder",  puoli: "vasen" },
  { key: "back",     slot: "back",     nimi: "Back",      puoli: "vasen" },
  { key: "chest",    slot: "chest",    nimi: "Chest",     puoli: "vasen" },
  { key: "wrist",    slot: "wrist",    nimi: "Wrist",     puoli: "vasen" },

  { key: "hands",    slot: "hands",    nimi: "Hands",     puoli: "oikea" },
  { key: "waist",    slot: "waist",    nimi: "Waist",     puoli: "oikea" },
  { key: "legs",     slot: "legs",     nimi: "Legs",      puoli: "oikea" },
  { key: "feet",     slot: "feet",     nimi: "Feet",      puoli: "oikea" },
  { key: "finger1",  slot: "finger",   nimi: "Ring",      puoli: "oikea" },
  { key: "finger2",  slot: "finger",   nimi: "Ring",      puoli: "oikea" },
  { key: "trinket1", slot: "trinket",  nimi: "Trinket",   puoli: "oikea" },
  { key: "trinket2", slot: "trinket",  nimi: "Trinket",   puoli: "oikea" },

  { key: "mainhand", slot: "mainhand", nimi: "Main Hand", puoli: "ala" },
  { key: "offhand",  slot: "offhand",  nimi: "Off Hand",  puoli: "ala" },
  { key: "ranged",   slot: "ranged",   nimi: "Ranged",    puoli: "ala" },
];

const PAIKKA_SLOTIT = new Map(PAIKAT.map((p) => [p.key, p.slot]));

export async function haeAktiiviRaidi(env) {
  return await env.DB.prepare(
    "SELECT id, name FROM raids WHERE is_active = 1 ORDER BY id DESC LIMIT 1"
  ).first();
}

/**
 * Jasenlista profiilisivun sivupalkkiin.
 *
 * Kaikille kirjautuneille. Mukana vain se mita profiilisivu muutenkin
 * nayttaa: nimi, luokka, raidirooli ja valintojen maara. Lukko, killan
 * arvo ja kirjautumisajat kuuluvat yllapitoon - tama lista on vertailua
 * varten, ei valvontaa.
 */
export async function haeRoster(env) {
  const raidi = await haeAktiiviRaidi(env);
  const raidId = raidi ? raidi.id : 0;

  const rivit = await env.DB.prepare(
    `SELECT u.username, u.character_name, u.first_name, u.last_name,
            u.class, u.raid_role,
            (SELECT COUNT(*) FROM picks p
              WHERE p.user_id = u.id AND p.raid_id = ?) AS valintoja
       FROM users u
      WHERE u.protected = 0
      ORDER BY
        COALESCE(NULLIF(u.first_name, ''), NULLIF(u.character_name, ''),
                 u.username) COLLATE NOCASE`
  )
    .bind(raidId)
    .all();

  return { paikkoja: PAIKAT.length, jasenet: rivit.results ?? [] };
}

/**
 * Aktiivinen raidi, sen itemit ja kayttajan omat valinnat yhdella kutsulla.
 *
 * Kaikki kolme tarvitaan samaan nakymaan, joten niiden hakeminen erikseen
 * olisi kolme kyselya siihen mita piirretaan kerralla.
 */
export async function haeNakyma(env, kayttajaId) {
  const raidi = await haeAktiiviRaidi(env);
  if (!raidi) {
    return { raid: null, paikat: PAIKAT, items: [], picks: {} };
  }

  const itemit = await env.DB.prepare(
    `SELECT item_id, boss, slot, armor_type
       FROM items WHERE raid_id = ?
      ORDER BY slot, boss, item_id`
  )
    .bind(raidi.id)
    .all();

  const valinnat = await env.DB.prepare(
    "SELECT slot_key, item_id FROM picks WHERE user_id = ? AND raid_id = ?"
  )
    .bind(kayttajaId, raidi.id)
    .all();

  const picks = {};
  for (const r of valinnat.results ?? []) picks[r.slot_key] = r.item_id;

  // Mitka valituista itemeista on jo saatu.
  //
  // Haku tehdaan seka kayttajatunnuksella etta hahmonimella: addon kirjaa
  // voittajaksi hahmon nimen, eika sita aina saada yhdistettya tunnukseen
  // tuontihetkella - esimerkiksi jos hahmo on nimetty uudelleen.
  const saadutRivit = await env.DB.prepare(
    `SELECT DISTINCT h.item_id
       FROM loot_history h
       LEFT JOIN users u ON u.id = ?
      WHERE h.user_id = ?
         OR LOWER(h.winner) = LOWER(COALESCE(u.character_name, ''))
         OR LOWER(h.winner) = LOWER(COALESCE(u.first_name, ''))
         OR LOWER(h.winner) = LOWER(COALESCE(u.username, ''))`
  )
    .bind(kayttajaId, kayttajaId)
    .all();

  const saadut = (saadutRivit.results ?? []).map((r) => r.item_id);

  return {
    raid: { id: raidi.id, name: raidi.name },
    paikat: PAIKAT,
    items: itemit.results ?? [],
    picks,
    saadut,
  };
}

/**
 * Tallentaa yhden paikan valinnan. Tyhja item poistaa valinnan.
 *
 * Tarkistukset tehdaan palvelimella vaikka selain rajaa listan valmiiksi:
 * selaimen rajaus on kayttoliittymaa, ei saanto.
 */
export async function tallennaValinta(env, kayttaja, slotKey, itemId) {
  // Lukko koskee raideria, ei officeria. Officerin on paastava korjaamaan
  // virheita ilman etta han ensin avaa lukon ja unohtaa sulkea sen.
  if (kayttaja.locked && kayttaja.role !== "officer") {
    return { error: "Profiilisi on lukittu. Pyydä officeria avaamaan se.", status: 403 };
  }

  const slot = PAIKKA_SLOTIT.get(slotKey);
  if (!slot) return { error: "Tuntematon paikka.", status: 400 };

  const raidi = await haeAktiiviRaidi(env);
  if (!raidi) return { error: "Aktiivista raidia ei ole.", status: 409 };

  if (itemId === null) {
    await env.DB.prepare(
      "DELETE FROM picks WHERE user_id = ? AND raid_id = ? AND slot_key = ?"
    )
      .bind(kayttaja.id, raidi.id, slotKey)
      .run();
    return { ok: true, slot_key: slotKey, item_id: null };
  }

  // Itemin on kuuluttava tahan raidiin ja sopittava tahan paikkaan.
  const item = await env.DB.prepare(
    "SELECT item_id FROM items WHERE raid_id = ? AND item_id = ? AND slot = ?"
  )
    .bind(raidi.id, itemId, slot)
    .first();

  if (!item) return { error: "Item ei sovi tähän paikkaan.", status: 400 };

  // Sama item kahteen paikkaan ei ole jarkevaa: kaksi sormusta tarkoittaa
  // kahta eri sormusta, ei samaa kahdesti.
  await env.DB.prepare(
    "DELETE FROM picks WHERE user_id = ? AND raid_id = ? AND item_id = ? AND slot_key != ?"
  )
    .bind(kayttaja.id, raidi.id, itemId, slotKey)
    .run();

  await env.DB.prepare(
    `INSERT INTO picks (user_id, raid_id, slot_key, item_id, updated_at)
     VALUES (?, ?, ?, ?, datetime('now'))
     ON CONFLICT(user_id, raid_id, slot_key)
       DO UPDATE SET item_id = excluded.item_id, updated_at = excluded.updated_at`
  )
    .bind(kayttaja.id, raidi.id, slotKey, itemId)
    .run();

  return { ok: true, slot_key: slotKey, item_id: itemId };
}
