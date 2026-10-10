/**
 * Loot — reititys.
 *
 * Staattiset sivut tulevat public-kansiosta eivätkä kulje tämän läpi
 * lainkaan; tähän päätyvät vain /api-polut. Niin kauan kuin sovellus on
 * pieni, yksi tiedosto riittää — jako tehdään vasta kun on jotain jaettavaa.
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/health") {
      return health(env);
    }

    if (url.pathname.startsWith("/api/")) {
      return json({ error: "Tuntematon polku." }, 404);
    }

    // Kaikki muu on staattista. assets-sidonta hoitaa myös 404-sivun.
    return env.ASSETS.fetch(request);
  },
};

/**
 * Kertoo toimiiko yhteys tietokantaan.
 *
 * Tämä on olemassa sitä varten, että julkaisuputki voidaan todistaa ennen
 * kuin sen päälle rakennetaan mitään: jos tämä vastaa, niin Worker ajaa,
 * D1 on kiinni ja migraatio on ajettu.
 */
async function health(env) {
  try {
    const row = await env.DB.prepare(
      "SELECT value FROM meta WHERE key = ?"
    )
      .bind("schema_version")
      .first();

    return json({
      ok: true,
      db: "yhteys ok",
      schema_version: row ? row.value : null,
    });
  } catch (err) {
    // Virheen teksti kerrotaan sellaisenaan. Tämä on kehitysvaiheen
    // työkalu, ja puuttuva taulu tai väärä sidonta pitää nähdä heti.
    return json({ ok: false, db: "virhe", error: String(err) }, 500);
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
