/**
 * Tunnistautuminen: salasanat, istunnot ja evästeet.
 */

/**
 * PBKDF2-kierrosten määrä.
 *
 * Workersin ilmaistasolla on tiukka suoritinaikaraja yhtä pyyntöä kohden,
 * ja salasanan tiivistäminen on tarkoituksella hidas operaatio — ne kaksi
 * ovat suoraan ristiriidassa. Luku on valittu niin että kirjautuminen mahtuu
 * rajaan selvästi.
 *
 * Kierrosmäärä tallennetaan tiivisteen sisään, joten sen voi nostaa
 * myöhemmin ilman että vanhat salasanat lakkaavat toimimasta: vanha tiiviste
 * tarkistetaan omalla luvullaan ja uudet kirjoitetaan uudella.
 */
export const PBKDF2_ITERATIONS = 25000;

const enc = new TextEncoder();

export async function hashPassword(password, iterations = PBKDF2_ITERATIONS) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const bits = await derive(password, salt, iterations);
  return `pbkdf2$${iterations}$${toB64(salt)}$${toB64(bits)}`;
}

export async function verifyPassword(password, stored) {
  if (typeof stored !== "string") return false;

  const osat = stored.split("$");
  if (osat.length !== 4 || osat[0] !== "pbkdf2") return false;

  const iterations = parseInt(osat[1], 10);
  if (!Number.isFinite(iterations) || iterations < 1) return false;

  const salt = fromB64(osat[2]);
  const odotettu = fromB64(osat[3]);
  if (!salt || !odotettu) return false;

  const saatu = await derive(password, salt, iterations);
  return samaAika(saatu, odotettu);
}

async function derive(password, salt, iterations) {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations, hash: "SHA-256" },
    key,
    256
  );
  return new Uint8Array(bits);
}

/**
 * Vertailu joka kestää yhtä kauan riippumatta siitä missä kohtaa ero on.
 *
 * Tavallinen vertailu keskeytyy ensimmäiseen eroavaan tavuun, ja siitä
 * kuluvasta ajasta voi päätellä kuinka monta tavua meni oikein.
 */
function samaAika(a, b) {
  if (a.length !== b.length) return false;
  let ero = 0;
  for (let i = 0; i < a.length; i++) ero |= a[i] ^ b[i];
  return ero === 0;
}

function toB64(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function fromB64(str) {
  try {
    const s = atob(str);
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export function uusiTunnus() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/* ---------- evästeet ---------- */

export const EVASTE_PORTTI = "loot_gate";
export const EVASTE_ISTUNTO = "loot_session";

export function lueEvasteet(request) {
  const raw = request.headers.get("cookie") || "";
  const out = {};
  for (const pala of raw.split(";")) {
    const i = pala.indexOf("=");
    if (i < 0) continue;
    out[pala.slice(0, i).trim()] = pala.slice(i + 1).trim();
  }
  return out;
}

/**
 * Eväste on aina httpOnly: sivun koodi ei pääse siihen käsiksi, joten
 * selaimessa ajettava vieras koodi ei voi lukea istuntoa.
 */
export function evaste(nimi, arvo, maxAge) {
  const osat = [
    `${nimi}=${arvo}`,
    "Path=/",
    "HttpOnly",
    "Secure",
    "SameSite=Lax",
    `Max-Age=${maxAge}`,
  ];
  return osat.join("; ");
}

export function poistaEvaste(nimi) {
  return `${nimi}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

/* ---------- istunto ---------- */

export const ISTUNTO_KESTO_S = 60 * 60 * 24 * 30;

/**
 * Hakee kirjautuneen käyttäjän istuntotunnuksen perusteella.
 *
 * Rooli luetaan tässä kannasta joka pyynnöllä. Se on tarkoituksellista:
 * jos rooli luettaisiin kirjautumishetkellä tallennetusta tiedosta, officeriksi
 * nostaminen vaatisi uloskirjautumisen - ja alentaminen ei tehoaisi ennen sitä.
 */
export async function haeKayttaja(env, request) {
  const token = lueEvasteet(request)[EVASTE_ISTUNTO];
  if (!token) return null;

  const rivi = await env.DB.prepare(
    `SELECT u.id, u.username, u.role, u.character_name, u.class, u.locked
       FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.token = ? AND s.expires_at > datetime('now')`
  )
    .bind(token)
    .first();

  return rivi || null;
}

export function onOfficer(kayttaja) {
  return !!kayttaja && kayttaja.role === "officer";
}
