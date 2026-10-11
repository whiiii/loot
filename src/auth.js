/**
 * Authentication: passwords, sessions and cookies.
 */

/**
 * The PBKDF2 iteration count.
 *
 * Workers' free tier has a tight CPU limit per request, and hashing a
 * password is deliberately slow — those two are in direct conflict. The
 * number is chosen so a login fits inside the limit with room to spare.
 *
 * The iteration count is stored inside the hash, so it can be raised
 * later without old passwords breaking: an old hash is verified with its
 * own number and new ones are written with the new one.
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

  const parts = stored.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2") return false;

  const iterations = parseInt(parts[1], 10);
  if (!Number.isFinite(iterations) || iterations < 1) return false;

  const salt = fromB64(parts[2]);
  const expected = fromB64(parts[3]);
  if (!salt || !expected) return false;

  const actual = await derive(password, salt, iterations);
  return constantTimeEqual(actual, expected);
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
 * A comparison that takes the same time regardless of where the
 * difference is.
 *
 * An ordinary comparison stops at the first differing byte, and the time
 * that takes reveals how many bytes were right.
 */
function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
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

export function newToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/* ---------- cookies ---------- */

export const COOKIE_GATE = "loot_gate";
export const COOKIE_SESSION = "loot_session";

export function readCookies(request) {
  const raw = request.headers.get("cookie") || "";
  const out = {};
  for (const piece of raw.split(";")) {
    const i = piece.indexOf("=");
    if (i < 0) continue;
    out[piece.slice(0, i).trim()] = piece.slice(i + 1).trim();
  }
  return out;
}

/**
 * The cookie is always httpOnly: page code cannot reach it, so foreign
 * code running in the browser cannot read the session.
 */
export function cookie(name, value, maxAge) {
  const parts = [
    `${name}=${value}`,
    "Path=/",
    "HttpOnly",
    "Secure",
    "SameSite=Lax",
    `Max-Age=${maxAge}`,
  ];
  return parts.join("; ");
}

export function clearCookie(name) {
  return `${name}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

/* ---------- session ---------- */

export const SESSION_MAX_AGE = 60 * 60 * 24 * 30;

/**
 * Looks up the logged-in user by their session token.
 *
 * The role is read from the database here on every request. That is
 * deliberate: if the role came from data stored at login, promoting
 * someone to officer would require a logout — and demoting them would
 * not take effect until then.
 */
export async function getUser(env, request) {
  const token = readCookies(request)[COOKIE_SESSION];
  if (!token) return null;

  const row = await env.DB.prepare(
    `SELECT u.id, u.username, u.role, u.character_name,
            u.first_name, u.last_name, u.class, u.raid_role,
            u.avatar_key, u.locked, u.protected
       FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.token = ? AND s.expires_at > datetime('now')`
  )
    .bind(token)
    .first();

  return row || null;
}

export function isOfficer(user) {
  return !!user && user.role === "officer";
}

/**
 * A protected account, i.e. the site's emergency exit.
 *
 * Its own flag rather than a role: the account needs officer rights, so
 * it cannot be built on top of the role. Protected means no action
 * touches it — no role change, no lock, no deletion and no character
 * edits. Otherwise it would not be an emergency exit: someone could
 * close it before it is needed.
 */
export function isProtected(user) {
  return !!user && !!user.protected;
}
