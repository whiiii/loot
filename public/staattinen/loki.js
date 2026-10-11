/**
 * Toimintoloki.
 *
 * Officer lukee, ei kirjoita. Poistonappi nakyy vain suojatulle
 * yllapitotunnukselle, ja palvelin tarkistaa saman uudelleen - nakyma ei
 * ole suojaus.
 */

const $ = (id) => document.getElementById(id);

const TOIMINNOT = {
  LUKITSE: "Lukitsi profiilin",
  AVAA_LUKKO: "Avasi lukon",
  LUKITSE_OMA: "Lukitsi oman profiilinsa",
  VAIHDA_ROOLI: "Vaihtoi roolin",
  VAIHDA_SALASANA: "Vaihtoi salasanan",
  LUO_KAYTTAJA: "Loi jäsenen",
  POISTA_KAYTTAJA: "Poisti jäsenen",
  PAIVITA_HAHMO: "Muokkasi hahmoa",
  TUO_HISTORIA: "Toi loottihistorian",
  POISTA_TUONTI: "Poisti tuonnin",
  POISTA_LOKI: "Poisti lokirivin",
};

// Teot joita kannattaa katsoa kahdesti. Varilla erotetut rivit loytyvat
// pitkasta listasta ilman etta jokainen pitaa lukea.
const PAINAVAT = new Set([
  "AVAA_LUKKO",
  "POISTA_KAYTTAJA",
  "VAIHDA_ROOLI",
  "POISTA_TUONTI",
  "POISTA_LOKI",
]);

let saaPoistaa = false;

for (const [avain, nimi] of Object.entries(TOIMINNOT)) {
  const o = document.createElement("option");
  o.value = avain;
  o.textContent = nimi;
  $("suodatin").appendChild(o);
}

async function lataa() {
  const p = new URLSearchParams();
  if ($("suodatin").value) p.set("toiminto", $("suodatin").value);
  if ($("haku").value.trim()) p.set("kohde", $("haku").value.trim());

  try {
    const d = await fetch("/api/loki?" + p.toString()).then((r) => r.json());

    if (!d.ok) {
      $("loki").innerHTML =
        `<tr><td colspan="6" class="himmea">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    saaPoistaa = !!d.saaPoistaa;
    piirra(d.loki || []);
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function piirra(rivit) {
  const tbody = $("loki");
  tbody.innerHTML = "";

  $("yhteenveto").textContent = `${rivit.length} riviä`;

  if (rivit.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="6" class="himmea">Ei merkintöjä.</td></tr>';
    return;
  }

  for (const r of rivit) {
    const tr = document.createElement("tr");

    tr.appendChild(solu(aika(r.created_at)));
    tr.appendChild(solu(r.actor || "—"));

    const toiminto = solu(TOIMINNOT[r.action] || r.action);
    if (PAINAVAT.has(r.action)) toiminto.className = "kesken";
    tr.appendChild(toiminto);

    tr.appendChild(solu(r.target || "—"));

    // Lisätiedot on se kenttä johon lukon avaamisen syy tallentuu.
    const lisa = solu(r.details || "—");
    lisa.className = r.details ? "katkaise" : "vaimea";
    lisa.title = r.details || "";
    tr.appendChild(lisa);

    const toimi = document.createElement("td");
    if (saaPoistaa) {
      toimi.className = "toiminnot";
      const b = document.createElement("button");
      b.type = "button";
      b.className = "nappi-vaara nappi-kuvake";
      b.textContent = "Poista";
      b.addEventListener("click", () => poista(r));
      toimi.appendChild(b);
    }
    tr.appendChild(toimi);

    tbody.appendChild(tr);
  }
}

async function poista(r) {
  const ok = await vahvista({
    otsikko: "Poista lokirivi",
    teksti:
      `${aika(r.created_at)} — ${r.actor}: ${TOIMINNOT[r.action] || r.action}` +
      (r.target ? ` (${r.target})` : "") +
      "\n\nPoisto kirjataan itse lokiin, joten jälki jää joka tapauksessa.",
    vahvista: "Poista",
    varoitus: true,
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/loki-poista", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: r.id }),
    }).then((x) => x.json());

    if (!d.ok) {
      naytaViesti(d.error || "Poisto epäonnistui.");
      return;
    }

    naytaViesti("Lokirivi poistettu.");
    lataa();
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- apurit ---------- */

function solu(teksti, luokka) {
  const td = document.createElement("td");
  td.textContent = teksti;
  if (luokka) td.className = luokka;
  return td;
}

function aika(arvo) {
  if (!arvo) return "—";
  return String(arvo).replace("T", " ").slice(0, 16);
}

let viestiAjastin = null;
function naytaViesti(teksti) {
  const el = $("viesti");
  el.textContent = teksti;
  el.classList.add("nakyy");
  clearTimeout(viestiAjastin);
  viestiAjastin = setTimeout(() => el.classList.remove("nakyy"), 2600);
}

let hakuAjastin = null;
$("haku").addEventListener("input", () => {
  clearTimeout(hakuAjastin);
  hakuAjastin = setTimeout(lataa, 300);
});

$("suodatin").addEventListener("change", lataa);

$("tyhjenna-haku").addEventListener("click", () => {
  $("haku").value = "";
  $("suodatin").value = "";
  lataa();
});

$("ulos").addEventListener("click", async () => {
  await fetch("/api/ulos", { method: "POST" });
  location.href = "/";
});

lataa();
