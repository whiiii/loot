/**
 * The action log.
 *
 * An officer reads it, does not write to it. The delete button appears
 * only for the protected admin account, and the server checks the same
 * thing again — a view is not protection.
 */

const $ = (id) => document.getElementById(id);

const ACTIONS = {
  LOCK: "Lukitsi profiilin",
  UNLOCK: "Avasi lukon",
  LOCK_OWN: "Lukitsi oman profiilinsa",
  CHANGE_ROLE: "Vaihtoi roolin",
  CHANGE_PASSWORD: "Vaihtoi salasanan",
  CREATE_USER: "Loi jäsenen",
  DELETE_USER: "Poisti jäsenen",
  UPDATE_CHARACTER: "Muokkasi hahmoa",
  IMPORT_HISTORY: "Toi loottihistorian",
  DELETE_IMPORT: "Poisti tuonnin",
  DELETE_LOG: "Poisti lokirivin",
};

// Acts worth a second look. Colouring them makes them findable in a long
// list without reading every row.
const WEIGHTY = new Set([
  "UNLOCK",
  "DELETE_USER",
  "CHANGE_ROLE",
  "DELETE_IMPORT",
  "DELETE_LOG",
]);

let mayDelete = false;

for (const [key, name] of Object.entries(ACTIONS)) {
  const option = document.createElement("option");
  option.value = key;
  option.textContent = name;
  $("filter").appendChild(option);
}

async function load() {
  const params = new URLSearchParams();
  if ($("filter").value) params.set("action", $("filter").value);
  if ($("search").value.trim()) params.set("name", $("search").value.trim());

  try {
    const d = await fetch("/api/log?" + params.toString()).then((r) => r.json());

    if (!d.ok) {
      $("log").innerHTML =
        `<tr><td colspan="6" class="dim">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    mayDelete = !!d.mayDelete;
    render(d.log || []);
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function render(rows) {
  const tbody = $("log");
  tbody.innerHTML = "";

  $("summary").textContent = `${rows.length} riviä`;

  if (rows.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" class="dim">Ei merkintöjä.</td></tr>';
    return;
  }

  for (const row of rows) {
    const tr = document.createElement("tr");

    tr.appendChild(cell(time(row.created_at)));
    tr.appendChild(cell(row.actor || "—"));

    const action = cell(ACTIONS[row.action] || row.action);
    if (WEIGHTY.has(row.action)) action.className = "partial";
    tr.appendChild(action);

    tr.appendChild(cell(row.target || "—"));

    // The details column is where the reason for opening a lock is
    // stored.
    const details = cell(row.details || "—");
    details.className = row.details ? "wrap" : "muted";
    details.title = row.details || "";
    tr.appendChild(details);

    const actions = document.createElement("td");
    if (mayDelete) {
      actions.className = "actions";
      const button = document.createElement("button");
      button.type = "button";
      button.className = "button-danger icon-button";
      button.textContent = "Poista";
      button.addEventListener("click", () => remove(row));
      actions.appendChild(button);
    }
    tr.appendChild(actions);

    tbody.appendChild(tr);
  }
}

async function remove(row) {
  const ok = await confirmDialog({
    title: "Poista lokirivi",
    text:
      `${time(row.created_at)} — ${row.actor}: ${ACTIONS[row.action] || row.action}` +
      (row.target ? ` (${row.target})` : "") +
      "\n\nPoisto kirjataan itse lokiin, joten jälki jää joka tapauksessa.",
    confirm: "Poista",
    warning: true,
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/log-delete", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: row.id }),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Poisto epäonnistui.");
      return;
    }

    showMessage("Lokirivi poistettu.");
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

let searchTimer = null;
$("search").addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(load, 300);
});

$("filter").addEventListener("change", load);

$("clear-search").addEventListener("click", () => {
  $("search").value = "";
  $("filter").value = "";
  load();
});

$("logout").addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST" });
  location.href = "/";
});

load();
