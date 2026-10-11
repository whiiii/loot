/**
 * Import history: the list of logs imported from the addon, and the
 * contents of one log.
 */

const $ = (id) => document.getElementById(id);

const RESPONSES = {
  prio: "LootPrio",
  main: "Main spec",
  off: "Off spec",
  muu: "Muu",
};

let selected = null;

/* ---------- the list ---------- */

async function load() {
  try {
    const d = await fetch("/api/imports").then((r) => r.json());

    if (!d.ok) {
      $("imports").innerHTML =
        `<tr><td colspan="7" class="dim">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    renderList(d.imports || []);
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/** A log's name: the officer's label, else the zone and size, else time. */
function logName(entry) {
  if (entry.label) return entry.label;

  const parts = [entry.zone || entry.source_raid || "Tuonti"];
  if (entry.raid_size) parts.push(`${entry.raid_size}-man`);
  return parts.join(" ");
}

function renderList(imports) {
  const tbody = $("imports");
  tbody.innerHTML = "";

  const items = imports.reduce((n, i) => n + (i.rows_remaining || 0), 0);
  $("summary").textContent = `${imports.length} tuontia · ${items} itemiä`;

  if (imports.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="7" class="dim">Ei tuonteja. Tuo addonin historia Siirto-sivulta.</td></tr>';
    return;
  }

  for (const entry of imports) {
    const tr = document.createElement("tr");

    const nameCell = document.createElement("td");
    const link = document.createElement("a");
    link.href = "#";
    link.className = "character-link";
    link.textContent = logName(entry);
    link.addEventListener("click", (e) => {
      e.preventDefault();
      openLog(entry.id);
    });
    nameCell.appendChild(link);
    tr.appendChild(nameCell);

    tr.appendChild(cell(entry.zone || "—"));
    tr.appendChild(cell(entry.raid_size ? `${entry.raid_size}` : "—", "right"));

    // Remaining rather than imported: a row can have been deleted, and
    // the number tells what the log holds now.
    tr.appendChild(cell(String(entry.rows_remaining ?? 0), "right"));
    tr.appendChild(cell(entry.imported_by || "—"));
    tr.appendChild(cell(time(entry.imported_at)));

    const actions = document.createElement("td");
    actions.className = "actions";

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "button-danger icon-button";
    remove.textContent = "Poista";
    remove.addEventListener("click", () => removeImport(entry));
    actions.appendChild(remove);

    tr.appendChild(actions);
    tbody.appendChild(tr);
  }
}

/* ---------- one log's contents ---------- */

async function openLog(id) {
  try {
    const d = await fetch("/api/import?id=" + encodeURIComponent(id)).then((r) =>
      r.json()
    );

    if (!d.ok) {
      showMessage(d.error || "Lokia ei saatu.");
      return;
    }

    selected = d;
    $("details").hidden = false;
    $("details-title").textContent = logName(d.import);

    // Hide the raw text when switching logs: otherwise the previous
    // log's text would stay visible under a new title.
    $("raw").hidden = true;
    $("raw").value = "";
    $("copy-raw").hidden = true;
    $("show-raw").textContent = "Näytä alkuperäinen teksti";

    renderRows(d.rows || []);
    $("details").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function renderRows(rows) {
  const tbody = $("rows");
  tbody.innerHTML = "";

  if (rows.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="6" class="dim">Ei rivejä. Kaikki tämän tuonnin itemit oli jo kirjattu aiemmin.</td></tr>';
    return;
  }

  for (const row of rows) {
    const tr = document.createElement("tr");

    // The item's name is not in the database, only its number. A Wowhead
    // link is a shorter path to the name than storing the name in two
    // places.
    const item = document.createElement("td");
    const link = document.createElement("a");
    link.href = "https://www.wowhead.com/classic/item=" + row.item_id;
    link.target = "_blank";
    link.rel = "noopener";
    link.textContent = row.item_id;
    item.appendChild(link);
    tr.appendChild(item);

    tr.appendChild(cell(row.winner || "—"));
    tr.appendChild(cell(RESPONSES[row.response] || "—"));
    tr.appendChild(cell(row.roll != null ? String(row.roll) : "—", "right"));
    tr.appendChild(cell(row.zone || "—"));
    tr.appendChild(cell(time(row.awarded_at)));

    tbody.appendChild(tr);
  }
}

$("show-raw").addEventListener("click", () => {
  if (!selected) return;

  const box = $("raw");

  if (!box.hidden) {
    box.hidden = true;
    $("copy-raw").hidden = true;
    $("show-raw").textContent = "Näytä alkuperäinen teksti";
    return;
  }

  box.value = selected.import.raw_text || "";
  box.hidden = false;
  $("copy-raw").hidden = false;
  $("show-raw").textContent = "Piilota alkuperäinen teksti";
});

$("copy-raw").addEventListener("click", async () => {
  const box = $("raw");
  try {
    // The clipboard API needs a secure context and can still fail.
    // Selecting the field is a fallback that always works.
    await navigator.clipboard.writeText(box.value);
    showMessage("Kopioitu leikepöydälle.");
  } catch {
    box.focus();
    box.select();
    showMessage("Kopioi näppäimistöltä: Ctrl+C");
  }
});

/* ---------- deletion ---------- */

async function removeImport(entry) {
  const ok = await confirmDialog({
    title: "Poista tuonti",
    text:
      `${logName(entry)}\n` +
      `Tuonut ${entry.imported_by}, ${time(entry.imported_at)}.\n\n` +
      `Poistaa ${entry.rows_remaining ?? 0} itemiä historiasta. Ne häviävät ` +
      "myös jäsenten profiileista.\n\n" +
      "Tätä ei voi perua. Alkuperäinen teksti häviää samalla, joten ota se " +
      "ensin talteen, jos saatat tarvita sitä.",
    confirm: "Poista",
    warning: true,
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/import-delete", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: entry.id }),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Poisto epäonnistui.");
      return;
    }

    if (selected && selected.import.id === entry.id) {
      selected = null;
      $("details").hidden = true;
    }

    showMessage(`Tuonti poistettu, ${d.deleted} riviä.`);
    load();
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- helpers ---------- */

function cell(text, className) {
  const td = document.createElement("td");
  td.textContent = text;
  if (className) td.className = className;
  return td;
}

/** Timestamps are UTC text in the database. Minutes are precise enough. */
function time(value) {
  if (!value) return "—";
  return String(value).replace("T", " ").slice(0, 16);
}

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

load();
