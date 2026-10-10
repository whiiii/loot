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
  poistaEvaste,
  uusiTunnus,
  verifyPassword,
} from "./auth.js";
import { haeNakyma, tallennaValinta } from "./valinnat.js";

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
  if (!porttiAuki) {
    if (polku === "/" || polku.startsWith("/staattinen/")) {
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
    return tiedosto(request, env, "/profiili.html");
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

  if (polku === "/api/nakyma") {
    return json({ ok: true, ...(await haeNakyma(env, kayttaja.id)) });
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
