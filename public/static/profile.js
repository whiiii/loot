/**
 * The character sheet: drawing the slots and picking an item.
 *
 * Item names, icons and tooltips come from our own endpoint, which
 * fetches them from Wowhead once and caches them. This used to be done
 * with Wowhead's own browser script, but that decided for itself which
 * links it handled and said nothing when it did nothing.
 */

const ICON_BASE = "https://wow.zamimg.com/images/wow/icons/large/";

let state = {
  raid: null,
  slots: [],
  items: [],
  picks: {},
  details: {},
  received: new Set(),
  locked: false,
  viewing: false,
  role: null,
};
let openSlot = null;

const $ = (id) => document.getElementById(id);

/* ---------- loading ---------- */

// Another member's profile opens at /profile?username=name.
const viewedUser = new URLSearchParams(location.search).get("username") || "";

async function load() {
  try {
    const viewUrl =
      "/api/view" +
      (viewedUser ? "?username=" + encodeURIComponent(viewedUser) : "");

    const [me, view] = await Promise.all([
      fetch("/api/me").then((r) => r.json()),
      fetch(viewUrl).then((r) => r.json()),
    ]);

    if (!me.ok) {
      location.href = "/login";
      return;
    }

    if (!view.ok) {
      showMessage(view.error || "Tietojen haku epäonnistui.");
      return;
    }

    // What is shown is the character's name, not the login username. In a
    // raid you look at the character; the username is only a way in.
    const u = view.user || me.user;
    const nameEl = $("name");
    nameEl.textContent = characterName(u);
    nameEl.style.color = classColour(u.class);

    // Class and raid role on one line under the name. The guild rank is
    // not here: it belongs to the admin pages, not the character sheet.
    const parts = [];
    if (CLASSES[u.class]) parts.push(CLASSES[u.class].name);
    if (RAID_ROLES[u.raid_role]) parts.push(RAID_ROLES[u.raid_role]);
    $("role").textContent = parts.join(" · ");

    state.role = me.user.role;
    state.viewing = view.ownProfile === false;

    // Someone else's profile is for looking at, not editing. Editing
    // belongs to whoever owns it — an officer opens the lock, a raider
    // makes the picks.
    if (state.viewing) {
      // Whose profile is open shows from the character's name and the
      // roster highlight, so no separate notice bar is needed.
      state.locked = true;
      $("lock-notice").hidden = true;
      $("save").hidden = true;
      if (me.user.role === "officer") showOfficerNav();
    } else {
      // The lock does not restrict an officer, so for them it is not a
      // "locked" state but merely a marker.
      state.locked = !!me.user.locked && me.user.role !== "officer";
      $("lock-notice").hidden = !state.locked;
      if (me.user.role === "officer") showOfficerNav();
      $("save").hidden = state.locked;
    }

    state.raid = view.raid;
    state.slots = view.slots ?? [];
    state.items = view.items ?? [];
    state.picks = view.picks ?? {};
    state.details = view.details ?? {};
    state.received = new Set(view.received ?? []);

    $("raid").textContent = state.raid ? state.raid.name : "Ei aktiivista raidia";
    drawSlots();
    loadRoster(u.username);
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- the roster ---------- */

/**
 * Which groups the user has opened.
 *
 * Kept only for the session: the default is closed, but moving from one
 * profile to another must not collapse what the user just opened.
 */
function openGroups() {
  try {
    return new Set(JSON.parse(sessionStorage.getItem("roster-open") || "[]"));
  } catch {
    return new Set();
  }
}

function saveOpenGroups(groups) {
  try {
    sessionStorage.setItem("roster-open", JSON.stringify([...groups]));
  } catch {
    // A private window or blocked storage. The list still works.
  }
}

/**
 * The member list for the sidebar.
 *
 * For everyone, not just officers: comparing picks is the whole point of
 * the site, and a raider needs to see who else reserved the same item.
 */
async function loadRoster(current) {
  const container = $("roster-list");

  try {
    const d = await fetch("/api/roster").then((r) => r.json());

    if (!d.ok) {
      container.innerHTML = '<p class="dim">Lista ei latautunut.</p>';
      return;
    }

    if (d.members.length === 0) {
      container.innerHTML = '<p class="dim">Ei jäseniä.</p>';
      return;
    }

    container.innerHTML = "";

    // By class. The order follows the CLASSES list so the same class is
    // always in the same place — alphabetical order would move them
    // around depending on who happens to be in the guild.
    const groups = new Map();
    for (const key of Object.keys(CLASSES)) groups.set(key, []);
    groups.set("", []);

    for (const member of d.members) {
      const key = CLASSES[member.class] ? member.class : "";
      groups.get(key).push(member);
    }

    const opened = openGroups();

    for (const [key, members] of groups) {
      if (members.length === 0) continue;

      const classInfo = CLASSES[key];

      const group = document.createElement("div");
      group.className = "roster-group";

      const head = document.createElement("button");
      head.type = "button";
      head.className = "roster-head";

      const arrow = document.createElement("span");
      arrow.className = "roster-arrow";
      arrow.textContent = "▶";
      head.appendChild(arrow);

      const name = document.createElement("span");
      name.textContent = classInfo ? classInfo.name : "Ei luokkaa";
      if (classInfo) name.style.color = classInfo.colour;
      head.appendChild(name);

      const count = document.createElement("span");
      count.className = "roster-count";
      count.textContent = members.length;
      head.appendChild(count);

      const body = document.createElement("div");
      body.className = "roster-body";

      for (const member of members) {
        const row = document.createElement("button");
        row.type = "button";
        row.className = "roster-row";
        row.textContent = characterName(member);
        row.style.color = classColour(member.class);
        if (member.username === current) row.classList.add("current");

        row.addEventListener("click", () => {
          location.href = "/profile?username=" + encodeURIComponent(member.username);
        });

        body.appendChild(row);
      }

      group.appendChild(head);
      group.appendChild(body);
      container.appendChild(group);

      // The height is measured from the content rather than guessed at a
      // constant: too small would cut the list off, too large would make
      // the animation stutter.
      const expand = (animate) => {
        group.classList.add("open");
        head.setAttribute("aria-expanded", "true");
        body.style.transition = animate ? "" : "none";
        body.style.maxHeight = body.scrollHeight + "px";
        if (!animate) requestAnimationFrame(() => (body.style.transition = ""));
      };

      const collapse = () => {
        group.classList.remove("open");
        head.setAttribute("aria-expanded", "false");
        body.style.maxHeight = "0";
      };

      collapse();
      if (opened.has(key)) expand(false);

      head.addEventListener("click", () => {
        const now = openGroups();

        if (group.classList.contains("open")) {
          collapse();
          now.delete(key);
        } else {
          expand(true);
          now.add(key);
        }

        saveOpenGroups(now);
      });
    }
  } catch {
    container.innerHTML = '<p class="dim">Lista ei latautunut.</p>';
  }
}

/* ---------- showing an item ---------- */

function itemDetails(itemId) {
  return state.details[itemId] || state.details[String(itemId)] || null;
}

/**
 * The icon and the name in the quality colour. If there are no details,
 * the id is shown — the site must not go blank because an outside source
 * did not answer.
 */
function itemElement(itemId) {
  const d = itemDetails(itemId);
  const wrapper = document.createElement("span");
  wrapper.className = "item";
  wrapper.dataset.itemId = itemId;

  const icon = document.createElement("span");
  icon.className = "item-icon";
  if (d && d.icon) {
    const img = document.createElement("img");
    img.src = ICON_BASE + d.icon + ".jpg";
    img.alt = "";
    img.loading = "lazy";
    icon.appendChild(img);
  }

  const text = document.createElement("span");
  text.className = "item-text";

  const name = document.createElement("span");
  name.className = "item-name q" + (d && d.quality != null ? d.quality : 1);
  name.textContent = d && d.name ? d.name : "item " + itemId;

  // The item id, small. It is what the addon and the database use, so
  // seeing it makes comparing and finding mistakes easier.
  const id = document.createElement("span");
  id.className = "item-id";
  id.textContent = itemId;

  text.appendChild(name);
  text.appendChild(id);

  wrapper.appendChild(icon);
  wrapper.appendChild(text);

  // A received item is marked. The information comes from the loot
  // history imported from the addon, so the mark means the item really
  // was awarded in a raid — not that somebody ticked it off on the site.
  if (state.received.has(itemId)) {
    wrapper.classList.add("received");

    const mark = document.createElement("span");
    mark.className = "received-mark";
    mark.title = "Saatu raidissa";
    mark.innerHTML =
      '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" ' +
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" ' +
      'stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    wrapper.appendChild(mark);
  }

  return wrapper;
}

/* ---------- drawing ---------- */

const SIDE_IDS = { left: "column-left", right: "column-right", bottom: "row-below" };

function drawSlots() {
  for (const id of Object.values(SIDE_IDS)) $(id).innerHTML = "";

  for (const slot of state.slots) {
    const picked = state.picks[slot.key] ?? null;

    const button = document.createElement("button");
    button.type = "button";
    button.className = "slot" + (picked ? " chosen" : "");

    const label = document.createElement("span");
    label.className = "slot-label";
    label.textContent = slot.name;

    const value = document.createElement("span");
    value.className = "slot-value";

    if (picked) {
      value.appendChild(itemElement(picked));
    } else {
      const empty = document.createElement("span");
      empty.className = "slot-empty";
      empty.textContent = "— ei valintaa —";
      value.appendChild(empty);
    }

    button.appendChild(label);
    button.appendChild(value);
    button.addEventListener("click", () => openPicker(slot));
    $(SIDE_IDS[slot.side]).appendChild(button);
  }
}

/* ---------- the picker ---------- */

function openPicker(slot) {
  if (state.viewing) return;
  if (state.locked) { showMessage("Profiili on lukittu."); return; }
  if (!state.raid) { showMessage("Aktiivista raidia ei ole."); return; }

  openSlot = slot;
  $("picker-title").textContent = slot.name;

  const list = $("picker-list");
  list.innerHTML = "";

  const fitting = state.items.filter((i) => i.slot === slot.slot);

  if (fitting.length === 0) {
    const p = document.createElement("p");
    p.className = "dim";
    p.textContent = "Tähän paikkaan ei ole itemeitä tässä raidissa.";
    list.appendChild(p);
  }

  // Alphabetical by name: numeric order tells the reader nothing.
  fitting.sort((a, b) => {
    const an = itemDetails(a.item_id)?.name || String(a.item_id);
    const bn = itemDetails(b.item_id)?.name || String(b.item_id);
    return an.localeCompare(bn);
  });

  for (const item of fitting) {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "picker-row";
    row.appendChild(itemElement(item.item_id));

    if (item.boss) {
      const boss = document.createElement("span");
      boss.className = "boss";
      boss.textContent = item.boss;
      row.appendChild(boss);
    }

    row.addEventListener("click", () => choose(item.item_id));
    list.appendChild(row);
  }

  $("overlay").hidden = false;
}

function closePicker() {
  $("overlay").hidden = true;
  hideTooltip();
  openSlot = null;
}

async function choose(itemId) {
  if (!openSlot) return;
  const slot = openSlot;
  closePicker();
  await savePick(slot.key, itemId);
}

async function savePick(slotKey, itemId) {
  try {
    const response = await fetch("/api/pick", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ slot_key: slotKey, item_id: itemId }),
    });
    const data = await response.json();

    if (!data.ok) {
      showMessage(data.error || "Tallennus ei onnistunut.");
      return;
    }

    // The server can drop the same item from another slot, so the state
    // is fetched again rather than the outcome being guessed.
    const fresh = await fetch("/api/view").then((r) => r.json());
    if (fresh.ok) {
      state.picks = fresh.picks ?? {};
      state.details = fresh.details ?? state.details;
      drawSlots();
    }
    showMessage(itemId ? "Tallennettu." : "Valinta poistettu.");
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
    console.error("savePick():", err);
  }
}

/* ---------- tooltip ---------- */

const tooltip = $("tooltip");

document.addEventListener("mouseover", (e) => {
  const target = e.target.closest ? e.target.closest(".item") : null;
  if (!target) return;

  const d = itemDetails(parseInt(target.dataset.itemId, 10));
  if (!d || !d.tooltip) return;

  // The content was sanitised on the server: scripts and event handlers
  // were stripped before it was stored.
  tooltip.innerHTML = d.tooltip;
  tooltip.hidden = false;
  moveTooltip(e);
});

document.addEventListener("mousemove", (e) => {
  if (!tooltip.hidden) moveTooltip(e);
});

document.addEventListener("mouseout", (e) => {
  const target = e.target.closest ? e.target.closest(".item") : null;
  if (target) hideTooltip();
});

function moveTooltip(e) {
  const margin = 16;
  const width = tooltip.offsetWidth;
  const height = tooltip.offsetHeight;

  let x = e.clientX + margin;
  let y = e.clientY + margin;

  if (x + width > window.innerWidth) x = e.clientX - width - margin;
  if (y + height > window.innerHeight) y = window.innerHeight - height - 8;
  if (y < 8) y = 8;

  tooltip.style.left = x + "px";
  tooltip.style.top = y + "px";
}

function hideTooltip() {
  tooltip.hidden = true;
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

const portrait = $("portrait-image");
if (portrait) {
  portrait.addEventListener("error", () => {
    portrait.hidden = true;
    $("portrait-empty").hidden = false;
  });
}

$("picker-close").addEventListener("click", closePicker);
$("picker-clear").addEventListener("click", async () => {
  if (!openSlot) return;
  const slot = openSlot;
  closePicker();
  await savePick(slot.key, null);
});
$("overlay").addEventListener("click", (e) => {
  if (e.target === $("overlay")) closePicker();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closePicker();
});

/**
 * Save locks the profile.
 *
 * Picks are stored as they are clicked, so this button saves nothing new
 * — it marks the profile as finished. That is also why it asks for
 * confirmation: a raider cannot change their picks themselves after it.
 */
$("save").addEventListener("click", async () => {
  const officer = state.role === "officer";

  const first = await confirmDialog({
    title: "Tallenna profiili",
    text: officer
      ? "Merkitäänkö profiili valmiiksi?\n\nLukko ei rajoita officeria, joten pääset muokkaamaan valintoja myös tämän jälkeen."
      : "Valintasi tallentuvat ja profiili merkitään valmiiksi.",
    confirm: "Tallenna",
  });
  if (!first) return;

  // The second confirmation only for the person the lock actually
  // affects. For an officer it would be one more click for nothing,
  // because they can still edit.
  if (!officer) {
    const second = await confirmDialog({
      title: "Tämän jälkeen et pääse muokkaamaan valintojasi",
      text:
        "Profiili lukitaan. Et pysty itse avaamaan sitä etkä muuttamaan " +
        "valintojasi.\n\nMikäli ei kerrasta osunut, niin oleppa jonnekki " +
        "yhteyksissä, sanat tiijätte",
      confirm: "Ymmärrän, lukitse",
      cancel: "En vielä",
      warning: true,
    });
    if (!second) return;
  }

  try {
    const data = await fetch("/api/lock-own", { method: "POST" })
      .then((r) => r.json());
    if (!data.ok) {
      showMessage(data.error || "Tallennus ei onnistunut.");
      return;
    }
    showMessage("Profiili tallennettu.");
    if (state.role !== "officer") {
      state.locked = true;
      $("lock-notice").hidden = false;
      $("save").hidden = true;
    }
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

$("logout").addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST" });
  location.href = "/";
});

load();
