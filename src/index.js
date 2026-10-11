/**
 * Loot — reititys.
 *
 * Kaikki pyynnöt kulkevat tämän läpi, myös staattiset sivut. Se on
 * tarkoituksellista: sivusto on yhteisen salasanan takana, eikä porttia voi
 * vartioida jos tiedostot tarjoillaan Workerin ohi.
 */
import {
  EVASTE_PORTTI,
  EVASTE_ISTUNTO,
  ISTUNTO_KESTO_S,
  evaste,
  haeKayttaja,
  hashPassword,
  lueEvasteet,
  onOfficer,
  onSuojattu,
  poistaEvaste,
  uusiTunnus,
  verifyPassword,
} from "./auth.js";
import { haeNakyma, haeRoster, tallennaValinta } from "./valinnat.js";
import { haeItemTiedot } from "./itemit.js";
import {
  asetaLukko,
  asetaSalasana,
  haeKayttajaNimella,
  haeKayttajat,
  luoKayttaja,
  lukitseOma,
  paivitaHahmo,
  poistaKayttaja,
  teeVienti,
  tuoHistoria,
  vaihdaRooli,
} from "./yllapito.js";
import { haeTuonnit, haeTuonti, poistaTuonti } from "./tuonnit.js";
import { haeLoki, poistaLokirivi } from "./loki.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const polku = url.pathname;

    try {
      if (polku.startsWith("/api/")) {
        return await rajapinta(request, env, polku);
      }
      return await sivu(request, env, polku);
    } catch (err) {
      return json({ ok: false, error: String(err) }, 500);
    }
  },
};

/* ---------- sivut ---------- */

async function sivu(request, env, polku) {
  const porttiAuki = await onPorttiAuki(env, request);

  // Portin takana ei näytetä mitään muuta kuin portti itse.
  //
  // Kuvake on poikkeus: se ei kerro mitään eikä sitä kannata piilottaa,
  // ja ilman sitä selaimen välilehti olisi tyhjä juuri sillä sivulla jolla
  // käyttäjä pisimpään viipyy — kirjautumisessa.
  if (!porttiAuki) {
    if (polku === "/" || polku === "/favicon.ico" || polku.startsWith("/staattinen/")) {
      return tiedosto(request, env, polku === "/" ? "/portti.html" : polku);
    }
    return Response.redirect(new URL("/", request.url).toString(), 302);
  }

  const kayttaja = await haeKayttaja(env, request);

  if (polku === "/") {
    return Response.redirect(
      new URL(kayttaja ? "/profiili" : "/kirjaudu", request.url).toString(),
      302
    );
  }

  if (polku === "/kirjaudu") {
    if (kayttaja) {
      return Response.redirect(new URL("/profiili", request.url).toString(), 302);
    }
    return tiedosto(request, env, "/kirjaudu.html");
  }

  if (polku === "/profiili") {
    if (!kayttaja) {
      return Response.redirect(new URL("/kirjaudu", request.url).toString(), 302);
    }
    // Yllapitotunnuksella ei ole hahmoa, joten hahmolomake olisi sille
    // tyhja sivu jolle ei voi tallentaa mitaan.
    if (onSuojattu(kayttaja)) {
      return Response.redirect(new URL("/yllapito", request.url).toString(), 302);
    }
    return tiedosto(request, env, "/profiili.html");
  }

  if (polku === "/yllapito") {
    if (!kayttaja) {
      return Response.redirect(new URL("/kirjaudu", request.url).toString(), 302);
    }
    // Sivun saa auki vain officer. Rajapinta tarkistaa saman erikseen,
    // joten sivun piilottaminen on mukavuutta eika suojaus.
    if (kayttaja.role !== "officer") {
      return Response.redirect(new URL("/profiili", request.url).toString(), 302);
    }
    return tiedosto(request, env, "/yllapito.html");
  }

  // Officerin sivut. Rajapinnat tarkistavat saman erikseen, joten sivun
  // piilottaminen on mukavuutta eika suojaus.
  const OFFICERIN_SIVUT = {
    "/historia": "/historia.html",
    "/siirto": "/siirto.html",
    "/loki": "/loki.html",
  };

  if (OFFICERIN_SIVUT[polku]) {
    if (!kayttaja) {
      return Response.redirect(new URL("/kirjaudu", request.url).toString(), 302);
    }
    if (kayttaja.role !== "officer") {
      return Response.redirect(new URL("/profiili", request.url).toString(), 302);
    }
    return tiedosto(request, env, OFFICERIN_SIVUT[polku]);
  }

  return tiedosto(request, env, polku);
}

function tiedosto(request, env, polku) {
  const osoite = new URL(polku, request.url);
  return env.ASSETS.fetch(new Request(osoite, request));
}

/* ---------- rajapinta ---------- */

async function rajapinta(request, env, polku) {
  if (polku === "/api/health") return health(env);

  if (polku === "/api/portti" && request.method === "POST") {
    return avaaPortti(request, env);
  }

  // Tästä eteenpäin portin on oltava auki.
  if (!(await onPorttiAuki(env, request))) {
    return json({ error: "Sivusto on suljettu." }, 403);
  }

  if (polku === "/api/kirjaudu" && request.method === "POST") {
    return kirjaudu(request, env);
  }
  if (polku === "/api/ulos" && request.method === "POST") {
    return ulos(request, env);
  }
  if (polku === "/api/mina") {
    return mina(request, env);
  }

  // Tästä eteenpäin on oltava kirjautunut.
  const kayttaja = await haeKayttaja(env, request);
  if (!kayttaja) return json({ error: "Ei kirjautunut." }, 401);

  // Jasenlista profiilisivun sivupalkkiin.
  //
  // Kaikille kirjautuneille, koska koko listan tarkoitus on etta raideri
  // nakee mita muut ovat valinneet. Vain se mita profiilisivu nayttaa -
  // ei lukkoja, rooleja eika kirjautumisaikoja, jotka kuuluvat
  // yllapitoon.
  if (polku === "/api/roster") {
    return json({ ok: true, ...(await haeRoster(env)) });
  }

  if (polku === "/api/nakyma") {
    // Oma profiili ja toisen katselu ovat sama ruutu, joten ne ovat sama
    // rajapintakin - kaksi erillista olisi kaksi paikkaa jotka voivat
    // ajautua erilleen.
    //
    // Toisen profiilin saa katsoa kuka tahansa kirjautunut: valinnat ovat
    // killan sisaista tietoa, ja niiden vertailu on koko sivuston
    // tarkoitus. Muokata saa vain omaansa, ja sen ratkaisee tallennus -
    // ei tama.
    const katso = new URL(request.url).searchParams.get("username") ?? "";
    let kohde = kayttaja;

    if (katso && katso.toLowerCase() !== kayttaja.username.toLowerCase()) {
      kohde = await haeKayttajaNimella(env, katso);
      if (!kohde) return json({ error: "Käyttäjää ei löydy." }, 404);
    }

    const nakyma = await haeNakyma(env, kohde.id);
    nakyma.user = kohde;
    nakyma.omaProfiili = kohde.id === kayttaja.id;

    // Itemien nimet haetaan samassa vastauksessa. Erillinen kutsu tarkoittaisi
    // etta lista valahtaa ensin numeroina ja tayttyy vasta sen jalkeen.
    const idt = [
      ...nakyma.items.map((i) => i.item_id),
      ...Object.values(nakyma.picks),
    ];
    nakyma.tiedot = await haeItemTiedot(env, idt);

    return json({ ok: true, ...nakyma });
  }

  if (polku === "/api/valinta" && request.method === "PUT") {
    const body = await lueJson(request);
    const slotKey = String(body.slot_key ?? "");
    const raaka = body.item_id;
    const itemId =
      raaka === null || raaka === "" || raaka === undefined
        ? null
        : parseInt(raaka, 10);

    if (itemId !== null && !Number.isFinite(itemId)) {
      return json({ error: "Virheellinen item." }, 400);
    }

    const tulos = await tallennaValinta(env, kayttaja, slotKey, itemId);
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/lukitse" && request.method === "POST") {
    return json(await lukitseOma(env, kayttaja));
  }

  /* ---------- officerin työkalut ---------- */

  if (!onOfficer(kayttaja)) {
    return json({ error: "Vain officerille." }, 403);
  }

  if (polku === "/api/kayttajat") {
    // Oma tunnus mukaan: lista tarvitsee sen tietaakseen mitka napit ovat
    // omalla rivilla. Nakyma ei ole suojaus - palvelin tarkistaa saman.
    return json({ ok: true, me: kayttaja.username, ...(await haeKayttajat(env)) });
  }

  if (polku === "/api/lukko" && request.method === "POST") {
    const body = await lueJson(request);
    const tulos = await asetaLukko(
      env,
      kayttaja.username,
      String(body.username ?? ""),
      !!body.locked,
      body.syy
    );
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  /* ---------- toimintoloki ---------- */

  if (polku === "/api/loki") {
    const p = new URL(request.url).searchParams;
    return json({
      ok: true,
      // Poisto on vain suojatulla tunnuksella. Selain tarvitsee tiedon
      // nappien piirtamiseen; palvelin tarkistaa saman uudelleen.
      saaPoistaa: onSuojattu(kayttaja),
      ...(await haeLoki(env, {
        raja: p.get("raja"),
        toiminto: p.get("toiminto"),
        kohde: p.get("kohde"),
      })),
    });
  }

  if (polku === "/api/loki-poista" && request.method === "POST") {
    // Loki jonka officer voi siivota ei ole loki vaan muistiinpano.
    if (!onSuojattu(kayttaja)) {
      return json(
        { error: "Lokia voi poistaa vain ylläpitotunnuksella." },
        403
      );
    }

    const body = await lueJson(request);
    const id = parseInt(body.id, 10);
    if (!Number.isFinite(id)) return json({ error: "Puuttuva id." }, 400);

    const tulos = await poistaLokirivi(env, kayttaja.username, id);
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/rooli" && request.method === "POST") {
    const body = await lueJson(request);
    const tulos = await vaihdaRooli(
      env,
      kayttaja.username,
      String(body.username ?? ""),
      String(body.role ?? "")
    );
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/salasana" && request.method === "POST") {
    const body = await lueJson(request);
    const tulos = await asetaSalasana(
      env,
      kayttaja.username,
      String(body.username ?? ""),
      String(body.password ?? "")
    );
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/kayttaja" && request.method === "POST") {
    const tulos = await luoKayttaja(env, kayttaja.username, await lueJson(request));
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/poista" && request.method === "POST") {
    const body = await lueJson(request);
    const tulos = await poistaKayttaja(
      env,
      kayttaja.username,
      String(body.username ?? "")
    );
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/hahmo" && request.method === "POST") {
    const body = await lueJson(request);
    const { username, ...muutokset } = body;
    const tulos = await paivitaHahmo(
      env,
      kayttaja.username,
      String(username ?? ""),
      muutokset
    );
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/historia" && request.method === "POST") {
    const body = await lueJson(request);
    const tulos = await tuoHistoria(
      env,
      kayttaja.username,
      String(body.teksti ?? ""),
      body.label
    );
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  /* ---------- tuontilokit ---------- */

  if (polku === "/api/tuonnit") {
    return json({ ok: true, ...(await haeTuonnit(env)) });
  }

  if (polku === "/api/tuonti") {
    const id = parseInt(new URL(request.url).searchParams.get("id") ?? "", 10);
    if (!Number.isFinite(id)) return json({ error: "Puuttuva id." }, 400);

    const tulos = await haeTuonti(env, id);
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/tuonti-poista" && request.method === "POST") {
    const body = await lueJson(request);
    const id = parseInt(body.id, 10);
    if (!Number.isFinite(id)) return json({ error: "Puuttuva id." }, 400);

    const tulos = await poistaTuonti(env, kayttaja.username, id);
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  if (polku === "/api/vienti") {
    const tulos = await teeVienti(env);
    return json(tulos, tulos.error ? tulos.status : 200);
  }

  return json({ error: "Tuntematon polku." }, 404);
}

async function health(env) {
  try {
    const row = await env.DB.prepare(
      "SELECT value FROM settings WHERE key = ?"
    )
      .bind("schema_version")
      .first();
    return json({ ok: true, db: "yhteys ok", schema_version: row?.value ?? null });
  } catch (err) {
    return json({ ok: false, db: "virhe", error: String(err) }, 500);
  }
}

/* ---------- yhteinen portti ---------- */

/**
 * Portin eväste sisältää satunnaisen tunnuksen, joka on myös kannassa.
 *
 * Pelkkä "olen käynyt portilla" -merkintä olisi kenen tahansa kirjoitettavissa
 * selaimen työkaluilla. Kun arvo tarkistetaan kantaa vasten, sitä ei voi
 * keksiä - ja yhteisen salasanan vaihtaminen sulkee kaikki vanhat evästeet
 * kerralla, koska tunnus vaihtuu samalla.
 */
async function onPorttiAuki(env, request) {
  const evasteet = lueEvasteet(request);
  const annettu = evasteet[EVASTE_PORTTI];
  if (!annettu) return false;

  const rivi = await env.DB.prepare(
    "SELECT value FROM settings WHERE key = 'gate_token'"
  ).first();

  return !!rivi && rivi.value === annettu;
}

async function avaaPortti(request, env) {
  const body = await lueJson(request);
  const tunnus = String(body.username ?? "").trim();
  const salasana = String(body.password ?? "");

  const rivit = await env.DB.prepare(
    "SELECT key, value FROM settings WHERE key IN ('gate_username','gate_password','gate_token')"
  ).all();

  const asetus = {};
  for (const r of rivit.results ?? []) asetus[r.key] = r.value;

  const tunnusOk = (asetus.gate_username ?? "").toLowerCase() === tunnus.toLowerCase();
  const salaOk = await verifyPassword(salasana, asetus.gate_password ?? "");

  // Sama vastaus kummassakin tapauksessa: väärä tunnus ja väärä salasana
  // eivät saa erottua toisistaan.
  if (!tunnusOk || !salaOk) {
    return json({ error: "Väärä tunnus tai salasana." }, 401);
  }

  return json(
    { ok: true },
    200,
    { "set-cookie": evaste(EVASTE_PORTTI, asetus.gate_token, ISTUNTO_KESTO_S) }
  );
}

/* ---------- henkilökohtainen kirjautuminen ---------- */

async function kirjaudu(request, env) {
  const body = await lueJson(request);
  const tunnus = String(body.username ?? "").trim();
  const salasana = String(body.password ?? "");

  if (!tunnus || !salasana) {
    return json({ error: "Anna tunnus ja salasana." }, 400);
  }

  const kayttaja = await env.DB.prepare(
    "SELECT id, username, password_hash FROM users WHERE username = ?"
  )
    .bind(tunnus)
    .first();

  // Tuntematon tunnus tarkistetaan silti salasanaa vasten, jotta vastaus
  // kestää yhtä kauan kummassakin tapauksessa eikä kerro onko tunnus olemassa.
  const tiiviste = kayttaja?.password_hash ?? "pbkdf2$25000$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  const ok = await verifyPassword(salasana, tiiviste);

  if (!kayttaja || !ok) {
    return json({ error: "Väärä tunnus tai salasana." }, 401);
  }

  const token = uusiTunnus();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO sessions (token, user_id, expires_at)
       VALUES (?, ?, datetime('now', '+30 days'))`
    ).bind(token, kayttaja.id),
    env.DB.prepare(
      "UPDATE users SET last_login_at = datetime('now') WHERE id = ?"
    ).bind(kayttaja.id),
  ]);

  return json(
    { ok: true },
    200,
    { "set-cookie": evaste(EVASTE_ISTUNTO, token, ISTUNTO_KESTO_S) }
  );
}

async function ulos(request, env) {
  const token = lueEvasteet(request)[EVASTE_ISTUNTO];
  if (token) {
    await env.DB.prepare("DELETE FROM sessions WHERE token = ?").bind(token).run();
  }
  return json({ ok: true }, 200, { "set-cookie": poistaEvaste(EVASTE_ISTUNTO) });
}

async function mina(request, env) {
  const kayttaja = await haeKayttaja(env, request);
  if (!kayttaja) return json({ error: "Ei kirjautunut." }, 401);
  return json({ ok: true, user: kayttaja });
}

/* ---------- apurit ---------- */

async function lueJson(request) {
  try {
    const data = await request.json();
    return data && typeof data === "object" ? data : {};
  } catch {
    return {};
  }
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...extraHeaders,
    },
  });
}

// hashPassword on käytössä vasta kun officerin työkalut lisätään; pidetään
// tuonti näkyvissä, jotta salasanan asetus kulkee samasta paikasta.
export { hashPassword };
