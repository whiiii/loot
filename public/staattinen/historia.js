/**
 * Tuontihistoria: lista addonista tuoduista lokeista ja yhden lokin sisältö.
 */

const $ = (id) => document.getElementById(id);

const PERUSTE = {
  prio: "LootPrio",
  main: "Main spec",
  off: "Off spec",
  muu: "Muu",
};

let valittu = null;

/* ---------- lista ---------- */

async function lataa() {
  try {
    const d = await fetch("/api/tuonnit").then((r) => r.json());

    if (!d.ok) {
      $("tuonnit").innerHTML =
        `<tr><td colspan="7" class="himmea">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    piirraLista(d.tuonnit || []);
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/** Lokin nimi: officerin antama, muuten instanssi ja koko, muuten aika. */
function lokinNimi(t) {
  if (t.label) return t.label;

  const osat = [t.zone || t.source_raid || "Tuonti"];
  if (t.raid_size) osat.push(`${t.raid_size}-man`);
  return osat.join(" ");
}

function piirraLista(tuonnit) {
  const tbody = $("tuonnit");
  tbody.innerHTML = "";

  const itemeja = tuonnit.reduce((n, t) => n + (t.rivit_jaljella || 0), 0);
  $("yhteenveto").textContent =
    `${tuonnit.length} tuontia · ${itemeja} itemiä`;

  if (tuonnit.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="7" class="himmea">Ei tuonteja. Tuo addonin historia Ylläpito-sivulta.</td></tr>';
    return;
  }

  for (const t of tuonnit) {
    const tr = document.createElement("tr");

    const nimi = document.createElement("td");
    const linkki = document.createElement("a");
    linkki.href = "#";
    linkki.className = "hahmolinkki";
    linkki.textContent = lokinNimi(t);
    linkki.addEventListener("click", (e) => {
      e.preventDefault();
      avaa(t.id);
    });
    nimi.appendChild(linkki);
    tr.appendChild(nimi);

    tr.appendChild(solu(t.zone || "—"));
    tr.appendChild(solu(t.raid_size ? `${t.raid_size}` : "—", "oikealle"));

    // Jäljellä eikä tuotuja: rivi on voitu poistaa, ja luku kertoo mitä
    // lokissa nyt on.
    tr.appendChild(solu(String(t.rivit_jaljella ?? 0), "oikealle"));
    tr.appendChild(solu(t.imported_by || "—"));
    tr.appendChild(solu(aika(t.imported_at)));

    const toiminto = document.createElement("td");
    toiminto.className = "toiminnot";

    const poista = document.createElement("button");
    poista.type = "button";
    poista.className = "nappi-vaara nappi-kuvake";
    poista.textContent = "Poista";
    poista.addEventListener("click", () => poistaTuonti(t));
    toiminto.appendChild(poista);

    tr.appendChild(toiminto);
    tbody.appendChild(tr);
  }
}

/* ---------- yhden lokin sisältö ---------- */

async function avaa(id) {
  try {
    const d = await fetch("/api/tuonti?id=" + encodeURIComponent(id)).then((r) =>
      r.json()
    );

    if (!d.ok) {
      naytaViesti(d.error || "Lokia ei saatu.");
      return;
    }

    valittu = d;
    $("tiedot").hidden = false;
    $("tiedot-otsikko").textContent = lokinNimi(d.tuonti);

    // Raakateksti piiloon lokia vaihdettaessa: muuten nakyviin jaisi
    // edellisen lokin teksti uuden otsikon alla.
    $("raaka").hidden = true;
    $("raaka").value = "";
    $("kopioi-raaka").hidden = true;
    $("nayta-raaka").textContent = "Näytä alkuperäinen teksti";

    piirraRivit(d.rivit || []);
    $("tiedot").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function piirraRivit(rivit) {
  const tbody = $("rivit");
  tbody.innerHTML = "";

  if (rivit.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="6" class="himmea">Ei rivejä. Kaikki tämän tuonnin itemit oli jo kirjattu aiemmin.</td></tr>';
    return;
  }

  for (const r of rivit) {
    const tr = document.createElement("tr");

    // Itemin nimeä ei ole kannassa, vain numero. Wowhead-linkki on
    // lyhyempi tie nimeen kuin nimen tallettaminen kahteen paikkaan.
    const item = document.createElement("td");
    const linkki = document.createElement("a");
    linkki.href = "https://www.wowhead.com/classic/item=" + r.item_id;
    linkki.target = "_blank";
    linkki.rel = "noopener";
    linkki.textContent = r.item_id;
    item.appendChild(linkki);
    tr.appendChild(item);

    tr.appendChild(solu(r.winner || "—"));
    tr.appendChild(solu(PERUSTE[r.response] || "—"));
    tr.appendChild(solu(r.roll != null ? String(r.roll) : "—", "oikealle"));
    tr.appendChild(solu(r.zone || "—"));
    tr.appendChild(solu(aika(r.awarded_at)));

    tbody.appendChild(tr);
  }
}

$("nayta-raaka").addEventListener("click", () => {
  if (!valittu) return;

  const ta = $("raaka");

  if (!ta.hidden) {
    ta.hidden = true;
    $("kopioi-raaka").hidden = true;
    $("nayta-raaka").textContent = "Näytä alkuperäinen teksti";
    return;
  }

  ta.value = valittu.tuonti.raw_text || "";
  ta.hidden = false;
  $("kopioi-raaka").hidden = false;
  $("nayta-raaka").textContent = "Piilota alkuperäinen teksti";
});

$("kopioi-raaka").addEventListener("click", async () => {
  const ta = $("raaka");
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

/* ---------- poisto ---------- */

async function poistaTuonti(t) {
  const ok = await vahvista({
    otsikko: "Poista tuonti",
    teksti:
      `${lokinNimi(t)}\n` +
      `Tuonut ${t.imported_by}, ${aika(t.imported_at)}.\n\n` +
      `Poistaa ${t.rivit_jaljella ?? 0} itemiä historiasta. Ne häviävät myös ` +
      "jäsenten profiileista.\n\n" +
      "Tätä ei voi perua. Alkuperäinen teksti häviää samalla, joten ota se " +
      "ensin talteen jos saatat tarvita sitä.",
    vahvista: "Poista",
    varoitus: true,
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/tuonti-poista", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: t.id }),
    }).then((r) => r.json());

    if (!d.ok) {
      naytaViesti(d.error || "Poisto epäonnistui.");
      return;
    }

    if (valittu && valittu.tuonti.id === t.id) {
      valittu = null;
      $("tiedot").hidden = true;
    }

    naytaViesti(`Tuonti poistettu, ${d.poistettuja} riviä.`);
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

/** Aikaleima kannassa on UTC-tekstia. Naytetaan se sellaisenaan ilman
 *  sekunteja: kellonajan tarkkuus minuutilleen riittaa lokissa. */
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

$("ulos").addEventListener("click", async () => {
  await fetch("/api/ulos", { method: "POST" });
  location.href = "/";
});

lataa();
