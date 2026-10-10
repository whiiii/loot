/**
 * Ylläpitosivu: profiililista, lukot ja vienti addoniin.
 */

const ROOLIT = { social: "Social", raider: "Raider", officer: "Officer" };
const $ = (id) => document.getElementById(id);

let paikkoja = 0;

async function lataa() {
  try {
    const d = await fetch("/api/kayttajat").then((r) => r.json());
    if (!d.ok) {
      $("kayttajat").innerHTML =
        `<tr><td colspan="6" class="himmea">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    paikkoja = d.paikkoja || 0;
    $("raidi").textContent = d.raid ? d.raid.name : "Ei aktiivista raidia";
    piirra(d.users || []);
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function piirra(users) {
  const tbody = $("kayttajat");
  tbody.innerHTML = "";

  if (users.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" class="himmea">Ei käyttäjiä.</td></tr>';
    return;
  }

  for (const u of users) {
    const tr = document.createElement("tr");

    tr.appendChild(solu(u.username));
    tr.appendChild(solu(u.character_name || "—"));

    const rooli = document.createElement("td");
    rooli.appendChild(merkki(ROOLIT[u.role] || u.role, "rooli"));
    tr.appendChild(rooli);

    const valinnat = solu(`${u.valintoja} / ${paikkoja}`);
    valinnat.className = "oikealle";
    tr.appendChild(valinnat);

    const tila = document.createElement("td");
    tila.appendChild(
      u.locked ? merkki("Lukittu", "lukko") : merkki("Avoin", "auki")
    );
    tr.appendChild(tila);

    const toiminto = document.createElement("td");
    const nappi = document.createElement("button");
    nappi.className = "pieni";
    nappi.textContent = u.locked ? "Avaa lukko" : "Lukitse";
    nappi.addEventListener("click", () => vaihdaLukko(u.username, !u.locked));
    toiminto.appendChild(nappi);
    tr.appendChild(toiminto);

    tbody.appendChild(tr);
  }
}

function solu(teksti) {
  const td = document.createElement("td");
  td.textContent = teksti;
  return td;
}

function merkki(teksti, luokka) {
  const span = document.createElement("span");
  span.className = "merkki " + luokka;
  span.textContent = teksti;
  return span;
}

async function vaihdaLukko(username, locked) {
  try {
    const d = await fetch("/api/lukko", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username, locked }),
    }).then((r) => r.json());

    if (!d.ok) {
      naytaViesti(d.error || "Muutos ei onnistunut.");
      return;
    }
    naytaViesti(locked ? `${username} lukittu.` : `${username} avattu.`);
    lataa();
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- vienti ---------- */

$("luo-vienti").addEventListener("click", async () => {
  try {
    const d = await fetch("/api/vienti").then((r) => r.json());
    if (!d.ok) {
      naytaViesti(d.error || "Vienti epäonnistui.");
      return;
    }

    const ta = $("vienti");
    ta.value = d.teksti;
    ta.hidden = false;
    $("kopioi").hidden = false;
    $("vientitiedot").textContent =
      `${d.raid} — ${d.hahmoja} hahmoa, ${d.teksti.length} merkkiä.`;
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

$("kopioi").addEventListener("click", async () => {
  const ta = $("vienti");
  try {
    // Leikepöydän rajapinta vaatii turvallisen yhteyden ja voi silti
    // epäonnistua. Valinta kenttään on varatie, joka toimii aina.
    await navigator.clipboard.writeText(ta.value);
    naytaViesti("Kopioitu leikepöydälle.");
  } catch {
    ta.focus();
    ta.select();
    naytaViesti("Kopioi näppäimistöltä: Ctrl+C");
  }
});

/* ---------- apurit ---------- */

let viestiAjastin = null;
function naytaViesti(teksti) {
  const el = $("viesti");
  el.textContent = teksti;
  el.classList.add("nakyy");
  clearTimeout(viestiAjastin);
  viestiAjastin = setTimeout(() => el.classList.remove("nakyy"), 2600);
}

$("ulos").addEventListener("click", async () => {
  await fetch("/api/ulos", { method: "POST" });
  location.href = "/";
});

lataa();
