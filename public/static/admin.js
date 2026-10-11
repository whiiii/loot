/**
 * The admin page: the member table, creating members and locks.
 */

const RANKS = window.RANKS;
const $ = (id) => document.getElementById(id);

let slotCount = 0;
let allUsers = [];
let myUsername = "";

/**
 * Icons as path data rather than ready-made elements.
 *
 * The SVG is written in code rather than fetched as files: there are a
 * couple of icons and they are tiny, so separate requests would cost
 * more than they save. The stroke inherits its colour from the button,
 * so one icon fits every shade.
 */
const ICON = {
  key:
    '<circle cx="7.5" cy="15.5" r="4.5"></circle><path d="M10.7 12.3 21 2"></path><path d="m17 6 3 3"></path>',
};

/** A button or link with an icon and a label. */
function iconButton({ text, icon, className, onClick, href }) {
  const el = document.createElement(href ? "a" : "button");
  if (href) el.href = href;
  else el.type = "button";

  el.className = className + " icon-button";
  el.innerHTML =
    `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" ` +
    `stroke="currentColor" stroke-width="2" stroke-linecap="round" ` +
    `stroke-linejoin="round">${icon}</svg><span></span>`;

  el.querySelector("span").textContent = text;
  if (onClick) el.addEventListener("click", onClick);
  return el;
}

/**
 * Sorting by column header.
 *
 * The sort value comes from a function rather than the field, because
 * the displayed value and the sortable value are not the same thing: the
 * class is stored as a key ("warrior") but the list shows a name, and
 * the pick count is a number even though the cell reads "16 / 17".
 */
const SORT_KEYS = {
  username:  (u) => (u.username || "").toLowerCase(),
  character: (u) => characterName(u).toLowerCase(),
  class:     (u) => (CLASSES[u.class] ? CLASSES[u.class].name : "ö").toLowerCase(),
  raid_role: (u) => (RAID_ROLES[u.raid_role] || "ö").toLowerCase(),
  // The protected account on top: it is the site's own row, not a guild
  // rank.
  role:      (u) =>
    u.protected ? -1 : ["officer", "raider", "social"].indexOf(u.role),
  picks:     (u) => u.picks,
  // A ratio rather than a count: 3/5 is further along than 3/17, and
  // that is exactly what the column is read for.
  received:  (u) => (u.picks ? (u.received ?? 0) / u.picks : -1),
  locked:    (u) => (u.locked ? 1 : 0),
};

let sortField = "role";
let sortAscending = true;

function sortUsers(users) {
  const key = SORT_KEYS[sortField] || SORT_KEYS.username;
  const direction = sortAscending ? 1 : -1;

  return [...users].sort((a, b) => {
    const x = key(a);
    const y = key(b);
    if (typeof x === "number" && typeof y === "number") return (x - y) * direction;
    return String(x).localeCompare(String(y), "fi") * direction;
  });
}

/**
 * Fills a dropdown from key/name pairs. Empty = "not chosen".
 *
 * In the class dropdown every option gets its own colour, not just the
 * selected one. Otherwise the whole list takes the colour of whichever
 * class happens to be selected, which is confusing exactly when the
 * class is being changed.
 */
function fillSelect(select, pairs, chosen, emptyText, colourFor) {
  select.innerHTML = "";

  const empty = document.createElement("option");
  empty.value = "";
  empty.textContent = emptyText;
  empty.style.color = "var(--dim)";
  select.appendChild(empty);

  for (const [key, name] of pairs) {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = name;
    if (colourFor) option.style.color = colourFor(key);
    if (chosen === key) option.selected = true;
    select.appendChild(option);
  }
  if (!chosen) empty.selected = true;
}

const CLASS_PAIRS = Object.entries(CLASSES).map(([k, v]) => [k, v.name]);
const ROLE_PAIRS = Object.entries(RAID_ROLES);

async function load() {
  try {
    const d = await fetch("/api/users").then((r) => r.json());
    if (!d.ok) {
      $("users").innerHTML =
        `<tr><td colspan="9" class="dim">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    slotCount = d.slotCount || 0;
    allUsers = d.users || [];
    myUsername = d.me || "";
    $("raid").textContent = d.raid ? d.raid.name : "Ei aktiivista raidia";
    render(sortUsers(allUsers));
    markSortedHeader();
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function render(users) {
  const tbody = $("users");
  tbody.innerHTML = "";

  renderProtected(users);

  if (users.length === 0) {
    tbody.innerHTML = '<tr><td colspan="9" class="dim">Ei käyttäjiä.</td></tr>';
    return;
  }

  for (const u of users) {
    // The protected account is not a profile: no class, no picks, no
    // actions. In the list it would be a row whose every column is
    // empty, and that looks broken however it is formatted. It sits
    // above the table on its own line instead.
    if (u.protected) continue;

    const tr = document.createElement("tr");

    tr.appendChild(cell(u.username));

    // The character's name in the class colour, as in the game — and a
    // link to the profile. The name is what an officer looks for in the
    // list, so it is also the natural place to open the profile from.
    const characterCell = document.createElement("td");
    const link = document.createElement("a");
    link.className = "character-link";
    link.href = "/profile?username=" + encodeURIComponent(u.username);
    link.textContent = characterName(u);
    link.style.color = classColour(u.class);
    link.title = "Avaa profiili";
    characterCell.appendChild(link);
    tr.appendChild(characterCell);

    tr.appendChild(fieldCell(u, "class", CLASS_PAIRS, "— luokka —"));

    // The role dropdown offers only the roles the class is eligible for.
    tr.appendChild(
      fieldCell(u, "raid_role", rolesForClass(u.class), "— rooli —")
    );

    const rankCell = document.createElement("td");
    rankCell.appendChild(rankSelect(u));
    tr.appendChild(rankCell);

    const picks = cell(`${u.picks} / ${slotCount}`);
    picks.className = "right";
    tr.appendChild(picks);

    // Received is relative to the picks rather than the slot count: the
    // question is how many of their own picks they have got. An empty
    // profile shows a dash, because 0 / 0 says nothing.
    const receivedCount = u.received ?? 0;
    const received = cell(u.picks ? `${receivedCount} / ${u.picks}` : "—");
    received.className = "right";
    if (!u.picks) received.classList.add("muted");
    else if (receivedCount >= u.picks) received.classList.add("complete");
    else if (receivedCount > 0) received.classList.add("partial");
    received.title = u.picks
      ? `${receivedCount} / ${u.picks} valitusta itemistä saatu`
      : "Ei valintoja";
    tr.appendChild(received);

    const state = document.createElement("td");
    state.appendChild(
      u.locked ? badge("Lukittu", "locked") : badge("Avoin", "open")
    );
    tr.appendChild(state);

    const actions = document.createElement("td");
    actions.appendChild(actionSelect(u));
    tr.appendChild(actions);

    tbody.appendChild(tr);
  }
}

/**
 * The guild rank dropdown.
 *
 * Changing a rank is immediate rather than a form with a save button: it
 * is one value, and a save button would only add a step that can be
 * forgotten.
 */
function rankSelect(u) {
  const select = document.createElement("select");
  select.className = "select";

  for (const [key, name] of Object.entries(RANKS)) {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = name;
    if (u.role === key) option.selected = true;
    select.appendChild(option);
  }

  select.addEventListener("change", async () => {
    const previous = u.role;
    const next = select.value;

    const ok = await confirmDialog({
      title: "Vaihda rooli",
      text: `${u.username}: ${RANKS[previous]} → ${RANKS[next]}`,
      confirm: "Vaihda",
      // Demoting an officer is the one direction that cannot be undone
      // by the person doing it, so it gets the warning colour.
      warning: previous === "officer" && next !== "officer",
    });

    if (!ok) {
      select.value = previous;
      return;
    }

    try {
      const d = await fetch("/api/role", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ username: u.username, role: next }),
      }).then((r) => r.json());

      if (!d.ok) {
        showMessage(d.error || "Roolin vaihto ei onnistunut.");
        select.value = previous;
        return;
      }
      showMessage(`${u.username}: ${RANKS[next]}`);
      load();
    } catch (err) {
      showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
      select.value = previous;
    }
  });

  return select;
}

/**
 * A single-field dropdown in the table.
 *
 * Sends only the field that changed. Sending the whole row would mean
 * overwriting fields nobody touched — and if two officers edit at the
 * same time, the second would wipe the first one's work.
 */
function fieldCell(u, field, pairs, emptyText) {
  const td = document.createElement("td");
  const select = document.createElement("select");
  select.className = "select";

  const colourFor = field === "class" ? classColour : null;
  fillSelect(select, pairs, u[field] || "", emptyText, colourFor);

  if (field === "class") select.style.color = classColour(u.class);

  select.addEventListener("change", async () => {
    const previous = u[field] || "";
    try {
      const d = await fetch("/api/character", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ username: u.username, [field]: select.value }),
      }).then((r) => r.json());

      if (!d.ok) {
        showMessage(d.error || "Muutos ei onnistunut.");
        select.value = previous;
        return;
      }

      // Changing the class can clear the role. That is reported, so the
      // change does not go unnoticed when the list is redrawn.
      showMessage(d.clearedRole || `${u.username} päivitetty.`);
      load();
    } catch (err) {
      showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
      select.value = previous;
    }
  });

  td.appendChild(select);
  return td;
}

function cell(text) {
  const td = document.createElement("td");
  td.textContent = text;
  return td;
}

/**
 * The protected admin accounts above the table.
 *
 * Its own line rather than a table row: the account has no class, no
 * picks and no actions, so every column would be empty. It is not a
 * profile, so it does not belong in a profile list.
 */
function renderProtected(users) {
  const text = $("admin-note");
  const buttons = $("admin-buttons");

  text.textContent = "";
  buttons.innerHTML = "";

  const protectedUsers = users.filter((u) => u.protected);

  text.hidden = protectedUsers.length === 0;
  buttons.hidden = true;
  if (text.hidden) return;

  text.textContent =
    "Ylläpito: " +
    protectedUsers.map((u) => u.username).join(", ") +
    " — sivuston varauloskäynti. Ei hahmo eikä muokattavissa.";

  // Only the account itself may change its password, so the button shows
  // only when you are logged in as it. Elsewhere it would promise an
  // action the server does not allow.
  const own = protectedUsers.find(
    (u) => myUsername && myUsername.toLowerCase() === u.username.toLowerCase()
  );

  if (own) {
    buttons.hidden = false;
    buttons.appendChild(
      iconButton({
        text: "Vaihda salasana",
        icon: ICON.key,
        className: "button-quiet",
        onClick: () => changePassword(own.username),
      })
    );
  }
}

function badge(text, className) {
  const span = document.createElement("span");
  span.className = "badge " + className;
  span.textContent = text;
  return span;
}

/**
 * The row's actions in one dropdown.
 *
 * Three buttons took over three hundred pixels of width and the table
 * spilled off the page. A dropdown is the same element as the class and
 * the role on the same row, so it brings nothing new to learn.
 */
function actionSelect(u) {
  const select = document.createElement("select");
  select.className = "select action-select";

  select.appendChild(new Option("Toiminnot…", ""));
  select.appendChild(
    new Option(u.locked ? "Avaa lukko" : "Lukitse profiili", "lock")
  );
  select.appendChild(new Option("Vaihda salasana", "password"));
  select.appendChild(new Option("Poista jäsen", "delete"));

  select.addEventListener("change", () => {
    const action = select.value;

    // Return to the title immediately: an action left selected would
    // look like the row's state rather than a one-off act.
    select.value = "";

    if (action === "lock") toggleLock(u.username, !u.locked);
    else if (action === "password") changePassword(u.username);
    else if (action === "delete") removeUser(u);
  });

  return select;
}

async function toggleLock(username, locked) {
  // Opening requires a reason, closing does not. The lock is what stops
  // picks changing mid-tier, so opening it is the act that gets asked
  // about later — and the reason is stored in the log.
  const result = await confirmDialog({
    title: locked ? "Lukitse profiili" : "Avaa lukko",
    text: locked
      ? `${username} ei pysty enää muuttamaan valintojaan.`
      : `${username} pääsee muuttamaan valintojaan.\n\n` +
        "Kirjoita syy. Se tallentuu lokiin eikä sitä voi jälkikäteen muuttaa.",
    confirm: locked ? "Lukitse" : "Avaa",
    input: locked
      ? null
      : {
          placeholder: "Syy, esim. vaihtoi specciä",
          min: 3,
          error: "Kirjoita syy (vähintään 3 merkkiä).",
        },
  });
  if (!result) return;

  try {
    const d = await fetch("/api/lock", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        username,
        locked,
        reason: locked ? null : result,
      }),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Muutos ei onnistunut.");
      return;
    }
    showMessage(locked ? `${username} lukittu.` : `${username} avattu.`);
    load();
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/**
 * An officer sets a new password.
 *
 * The password is shown in clear while being typed: the officer has to
 * tell it to the raider, so hiding it would only add typos without
 * protecting anything.
 */
async function changePassword(username) {
  const password = await confirmDialog({
    title: "Vaihda salasana",
    text:
      `Aseta uusi salasana käyttäjälle ${username}.\n\n` +
      "Hänen avoimet istuntonsa katkeavat, joten hän joutuu kirjautumaan " +
      "uudelleen tällä salasanalla.",
    confirm: "Aseta salasana",
    input: {
      type: "text",
      placeholder: "Uusi salasana",
      min: 6,
      error: "Salasanan on oltava vähintään 6 merkkiä.",
    },
  });

  if (password === null) return;

  try {
    const d = await fetch("/api/password", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username, password }),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Salasanan vaihto ei onnistunut.");
      return;
    }
    showMessage(`${username}: salasana vaihdettu.`);
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- sorting ---------- */

function markSortedHeader() {
  document.querySelectorAll("th[data-sort]").forEach((th) => {
    const isCurrent = th.dataset.sort === sortField;
    th.classList.toggle("sorted", isCurrent);
    th.dataset.direction = isCurrent ? (sortAscending ? "up" : "down") : "";
  });
}

document.querySelectorAll("th[data-sort]").forEach((th) => {
  th.addEventListener("click", () => {
    const field = th.dataset.sort;

    // The same header again flips the direction, a new one starts
    // ascending.
    if (field === sortField) {
      sortAscending = !sortAscending;
    } else {
      sortField = field;
      sortAscending = true;
    }

    render(sortUsers(allUsers));
    markSortedHeader();
  });
});

/* ---------- creating and removing members ---------- */

document.getElementById("new-member").addEventListener("submit", async (e) => {
  e.preventDefault();

  const details = {
    username: $("new-username").value.trim(),
    first_name: $("new-first").value.trim(),
    last_name: $("new-last").value.trim(),
    class: $("new-class").value,
    raid_role: $("new-raidrole").value,
    role: $("new-rank").value,
    password: $("new-password").value,
  };

  const ok = await confirmDialog({
    title: "Luo jäsen",
    text:
      `Tunnus: ${details.username}\n` +
      `Hahmo: ${[details.first_name || details.username, details.last_name]
        .filter(Boolean)
        .join(" ")}\n` +
      `Luokka: ${CLASSES[details.class] ? CLASSES[details.class].name : "—"}\n` +
      `Rooli: ${RAID_ROLES[details.raid_role] || "—"}\n` +
      `Rank: ${RANKS[details.role]}\n\n` +
      "Kerro salasana hänelle itse — sitä ei lähetetä mihinkään.",
    confirm: "Luo",
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/user", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(details),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Luonti ei onnistunut.");
      return;
    }

    showMessage(`${d.username} luotu.`);
    $("new-username").value = "";
    $("new-first").value = "";
    $("new-last").value = "";
    $("new-password").value = "";
    $("new-class").value = "";
    $("new-raidrole").value = "";
    $("new-rank").value = "raider";
    load();
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

async function removeUser(u) {
  const ok = await confirmDialog({
    title: "Poista jäsen",
    text:
      `${u.username} poistetaan pysyvästi.\n\n` +
      "Hänen valintansa katoavat, mutta loottihistoria jää tallelle.\n\n" +
      "Tätä ei voi perua.",
    confirm: "Poista pysyvästi",
    cancel: "Älä poista",
    warning: true,
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/user-delete", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: u.username }),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Poisto ei onnistunut.");
      return;
    }
    showMessage(`${u.username} poistettu.`);
    load();
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- helpers ---------- */

let messageTimer = null;
function showMessage(text) {
  const el = $("message");
  el.textContent = text;
  el.classList.add("visible");
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => el.classList.remove("visible"), 2600);
}

$("logout").addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST" });
  location.href = "/";
});

// The creation form's dropdowns are filled from the same source as the
// table's, so the lists do not live in two places.
fillSelect($("new-class"), CLASS_PAIRS, "", "— luokka —", classColour);
fillSelect($("new-raidrole"), ROLE_PAIRS, "", "— rooli —");

// Changing the class narrows the role dropdown. The chosen role survives
// if it is still valid.
$("new-class").addEventListener("change", () => {
  const className = $("new-class").value;
  $("new-class").style.color = classColour(className);

  const allowed = rolesForClass(className);
  const current = $("new-raidrole").value;
  const stillValid = allowed.some(([key]) => key === current);

  fillSelect(
    $("new-raidrole"),
    allowed,
    stillValid ? current : "",
    "— rooli —"
  );
});

load();
