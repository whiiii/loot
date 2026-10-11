/**
 * Loot — routing.
 *
 * Every request goes through here, static pages included. That is
 * deliberate: the site sits behind a shared password, and a gate cannot
 * be guarded if files are served past the Worker.
 */
import {
  COOKIE_GATE,
  COOKIE_SESSION,
  SESSION_MAX_AGE,
  clearCookie,
  cookie,
  getUser,
  isOfficer,
  isProtected,
  newToken,
  readCookies,
  verifyPassword,
} from "./auth.js";
import { getRoster, getView, savePick } from "./picks.js";
import { getItemDetails } from "./items.js";
import {
  buildExport,
  createUser,
  deleteUser,
  getUserByName,
  getUsers,
  importHistory,
  lockOwn,
  setLock,
  setPassword,
  setRole,
  updateCharacter,
} from "./admin.js";
import { deleteImport, getImport, getImports } from "./imports.js";
import { deleteLogRow, getLog } from "./log.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path.startsWith("/api/")) {
        return await api(request, env, path);
      }
      return await page(request, env, path);
    } catch (err) {
      return json({ ok: false, error: String(err) }, 500);
    }
  },
};

/* ---------- pages ---------- */

/**
 * Officer-only pages. The APIs check the same thing separately, so
 * hiding a page is convenience rather than protection.
 */
const OFFICER_PAGES = {
  "/admin": "/admin.html",
  "/imports": "/imports.html",
  "/transfer": "/transfer.html",
  "/log": "/log.html",
};

async function page(request, env, path) {
  const gateOpen = await isGateOpen(env, request);

  // Behind the gate nothing is shown but the gate itself.
  //
  // The favicon is an exception: it tells nothing and is not worth
  // hiding, and without it the browser tab would be blank on exactly the
  // page a user lingers on longest — the login.
  if (!gateOpen) {
    if (path === "/" || path === "/favicon.ico" || path.startsWith("/static/")) {
      return file(request, env, path === "/" ? "/gate.html" : path);
    }
    return Response.redirect(new URL("/", request.url).toString(), 302);
  }

  const user = await getUser(env, request);

  if (path === "/") {
    return Response.redirect(
      new URL(user ? "/profile" : "/login", request.url).toString(),
      302
    );
  }

  if (path === "/login") {
    if (user) {
      return Response.redirect(new URL("/profile", request.url).toString(), 302);
    }
    return file(request, env, "/login.html");
  }

  if (path === "/profile") {
    if (!user) {
      return Response.redirect(new URL("/login", request.url).toString(), 302);
    }
    // The protected account has no character, so the character sheet
    // would be an empty page it cannot save anything to.
    if (isProtected(user)) {
      return Response.redirect(new URL("/admin", request.url).toString(), 302);
    }
    return file(request, env, "/profile.html");
  }

  if (OFFICER_PAGES[path]) {
    if (!user) {
      return Response.redirect(new URL("/login", request.url).toString(), 302);
    }
    if (user.role !== "officer") {
      return Response.redirect(new URL("/profile", request.url).toString(), 302);
    }
    return file(request, env, OFFICER_PAGES[path]);
  }

  return file(request, env, path);
}

function file(request, env, path) {
  const target = new URL(path, request.url);
  return env.ASSETS.fetch(new Request(target, request));
}

/* ---------- API ---------- */

async function api(request, env, path) {
  if (path === "/api/health") return health(env);

  if (path === "/api/gate" && request.method === "POST") {
    return openGate(request, env);
  }

  // From here on the gate has to be open.
  if (!(await isGateOpen(env, request))) {
    return json({ error: "Sivusto on suljettu." }, 403);
  }

  if (path === "/api/login" && request.method === "POST") {
    return login(request, env);
  }
  if (path === "/api/logout" && request.method === "POST") {
    return logout(request, env);
  }
  if (path === "/api/me") {
    return me(request, env);
  }

  // From here on you have to be logged in.
  const user = await getUser(env, request);
  if (!user) return json({ error: "Ei kirjautunut." }, 401);

  // The member list for the profile page's sidebar.
  //
  // For every logged-in user, because the whole point of the list is
  // that a raider can see what others picked. Only what the profile page
  // shows — no locks, ranks or login times, which belong to the admin
  // pages.
  if (path === "/api/roster") {
    return json({ ok: true, ...(await getRoster(env)) });
  }

  if (path === "/api/view") {
    // Your own profile and viewing someone else's are the same screen, so
    // they are the same endpoint — two separate ones would be two places
    // that can drift apart.
    //
    // Anyone logged in may view another profile: the picks are internal
    // guild information, and comparing them is the whole point of the
    // site. Editing is limited to your own, and the save decides that —
    // not this.
    const wanted = new URL(request.url).searchParams.get("username") ?? "";
    let target = user;

    if (wanted && wanted.toLowerCase() !== user.username.toLowerCase()) {
      target = await getUserByName(env, wanted);
      if (!target) return json({ error: "Käyttäjää ei löydy." }, 404);
    }

    const view = await getView(env, target.id);
    view.user = target;
    view.ownProfile = target.id === user.id;

    // The item names come in the same response. A separate call would
    // mean the list flashes as numbers first and fills in afterwards.
    const ids = [
      ...view.items.map((i) => i.item_id),
      ...Object.values(view.picks),
    ];
    view.details = await getItemDetails(env, ids);

    return json({ ok: true, ...view });
  }

  if (path === "/api/pick" && request.method === "PUT") {
    const body = await readJson(request);
    const slotKey = String(body.slot_key ?? "");
    const raw = body.item_id;
    const itemId =
      raw === null || raw === "" || raw === undefined ? null : parseInt(raw, 10);

    if (itemId !== null && !Number.isFinite(itemId)) {
      return json({ error: "Virheellinen item." }, 400);
    }

    const result = await savePick(env, user, slotKey, itemId);
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/lock-own" && request.method === "POST") {
    return json(await lockOwn(env, user));
  }

  /* ---------- officer tools ---------- */

  if (!isOfficer(user)) {
    return json({ error: "Vain officerille." }, 403);
  }

  if (path === "/api/users") {
    // Our own username too: the list needs it to know which buttons are
    // on our own row. The view is not protection — the server checks the
    // same thing.
    return json({ ok: true, me: user.username, ...(await getUsers(env)) });
  }

  if (path === "/api/lock" && request.method === "POST") {
    const body = await readJson(request);
    const result = await setLock(
      env,
      user.username,
      String(body.username ?? ""),
      !!body.locked,
      body.reason
    );
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/role" && request.method === "POST") {
    const body = await readJson(request);
    const result = await setRole(
      env,
      user.username,
      String(body.username ?? ""),
      String(body.role ?? "")
    );
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/password" && request.method === "POST") {
    const body = await readJson(request);
    const result = await setPassword(
      env,
      user.username,
      String(body.username ?? ""),
      String(body.password ?? "")
    );
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/user" && request.method === "POST") {
    const result = await createUser(env, user.username, await readJson(request));
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/user-delete" && request.method === "POST") {
    const body = await readJson(request);
    const result = await deleteUser(
      env,
      user.username,
      String(body.username ?? "")
    );
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/character" && request.method === "POST") {
    const body = await readJson(request);
    const { username, ...changes } = body;
    const result = await updateCharacter(
      env,
      user.username,
      String(username ?? ""),
      changes
    );
    return json(result, result.error ? result.status : 200);
  }

  /* ---------- action log ---------- */

  if (path === "/api/log") {
    const params = new URL(request.url).searchParams;
    return json({
      ok: true,
      // Deletion is only for the protected account. The browser needs to
      // know in order to draw the buttons; the server checks it again.
      mayDelete: isProtected(user),
      ...(await getLog(env, {
        limit: params.get("limit"),
        action: params.get("action"),
        name: params.get("name"),
      })),
    });
  }

  if (path === "/api/log-delete" && request.method === "POST") {
    // A log an officer can tidy is not a log but a note.
    if (!isProtected(user)) {
      return json({ error: "Lokia voi poistaa vain ylläpitotunnuksella." }, 403);
    }

    const body = await readJson(request);
    const id = parseInt(body.id, 10);
    if (!Number.isFinite(id)) return json({ error: "Puuttuva id." }, 400);

    const result = await deleteLogRow(env, user.username, id);
    return json(result, result.error ? result.status : 200);
  }

  /* ---------- addon transfer ---------- */

  if (path === "/api/export") {
    const result = await buildExport(env);
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/imports") {
    return json({ ok: true, ...(await getImports(env)) });
  }

  if (path === "/api/import") {
    if (request.method === "POST") {
      const body = await readJson(request);
      const result = await importHistory(
        env,
        user.username,
        String(body.text ?? ""),
        body.label
      );
      return json(result, result.error ? result.status : 200);
    }

    const id = parseInt(new URL(request.url).searchParams.get("id") ?? "", 10);
    if (!Number.isFinite(id)) return json({ error: "Puuttuva id." }, 400);

    const result = await getImport(env, id);
    return json(result, result.error ? result.status : 200);
  }

  if (path === "/api/import-delete" && request.method === "POST") {
    const body = await readJson(request);
    const id = parseInt(body.id, 10);
    if (!Number.isFinite(id)) return json({ error: "Puuttuva id." }, 400);

    const result = await deleteImport(env, user.username, id);
    return json(result, result.error ? result.status : 200);
  }

  return json({ error: "Tuntematon polku." }, 404);
}

async function health(env) {
  try {
    const row = await env.DB.prepare("SELECT value FROM settings WHERE key = ?")
      .bind("schema_version")
      .first();
    return json({ ok: true, db: "yhteys ok", schema_version: row?.value ?? null });
  } catch (err) {
    return json({ ok: false, db: "virhe", error: String(err) }, 500);
  }
}

/* ---------- the shared gate ---------- */

/**
 * The gate cookie holds a random token that is also in the database.
 *
 * A plain "I have been through the gate" marker would be writable by
 * anyone with browser tools. Checking the value against the database
 * means it cannot be invented — and changing the shared password closes
 * every old cookie at once, because the token changes with it.
 */
async function isGateOpen(env, request) {
  const given = readCookies(request)[COOKIE_GATE];
  if (!given) return false;

  const row = await env.DB.prepare(
    "SELECT value FROM settings WHERE key = 'gate_token'"
  ).first();

  return !!row && row.value === given;
}

async function openGate(request, env) {
  const body = await readJson(request);
  const username = String(body.username ?? "").trim();
  const password = String(body.password ?? "");

  const rows = await env.DB.prepare(
    "SELECT key, value FROM settings WHERE key IN ('gate_username','gate_password','gate_token')"
  ).all();

  const settings = {};
  for (const row of rows.results ?? []) settings[row.key] = row.value;

  const nameOk =
    (settings.gate_username ?? "").toLowerCase() === username.toLowerCase();
  const passwordOk = await verifyPassword(password, settings.gate_password ?? "");

  // The same answer either way: a wrong username and a wrong password
  // must not be distinguishable.
  if (!nameOk || !passwordOk) {
    return json({ error: "Väärä tunnus tai salasana." }, 401);
  }

  return json({ ok: true }, 200, {
    "set-cookie": cookie(COOKIE_GATE, settings.gate_token, SESSION_MAX_AGE),
  });
}

/* ---------- personal login ---------- */

async function login(request, env) {
  const body = await readJson(request);
  const username = String(body.username ?? "").trim();
  const password = String(body.password ?? "");

  if (!username || !password) {
    return json({ error: "Anna tunnus ja salasana." }, 400);
  }

  const user = await env.DB.prepare(
    "SELECT id, username, password_hash FROM users WHERE username = ?"
  )
    .bind(username)
    .first();

  // An unknown username is still checked against a password, so the
  // response takes the same time either way and does not reveal whether
  // the account exists.
  const hash =
    user?.password_hash ??
    "pbkdf2$25000$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  const ok = await verifyPassword(password, hash);

  if (!user || !ok) {
    return json({ error: "Väärä tunnus tai salasana." }, 401);
  }

  const token = newToken();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO sessions (token, user_id, expires_at)
       VALUES (?, ?, datetime('now', '+30 days'))`
    ).bind(token, user.id),
    env.DB.prepare(
      "UPDATE users SET last_login_at = datetime('now') WHERE id = ?"
    ).bind(user.id),
  ]);

  return json({ ok: true }, 200, {
    "set-cookie": cookie(COOKIE_SESSION, token, SESSION_MAX_AGE),
  });
}

async function logout(request, env) {
  const token = readCookies(request)[COOKIE_SESSION];
  if (token) {
    await env.DB.prepare("DELETE FROM sessions WHERE token = ?")
      .bind(token)
      .run();
  }
  return json({ ok: true }, 200, { "set-cookie": clearCookie(COOKIE_SESSION) });
}

async function me(request, env) {
  const user = await getUser(env, request);
  if (!user) return json({ error: "Ei kirjautunut." }, 401);
  return json({ ok: true, user });
}

/* ---------- helpers ---------- */

async function readJson(request) {
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
