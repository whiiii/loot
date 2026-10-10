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
    rooli.appendChild(roolivalitsin(u));
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
    toiminto.className = "toiminnot";

    // Napit eroavat toisistaan tarkoituksella. Lukko on arkinen toiminto,
    // salasana hillitty, poisto peruuttamaton - ja sen pitaa nayttaa silta.
    const lukko = document.createElement("button");
    lukko.className = u.locked ? "nappi-korostus" : "nappi-hillitty";
    lukko.textContent = u.locked ? "Avaa lukko" : "Lukitse";
    lukko.addEventListener("click", () => vaihdaLukko(u.username, !u.locked));
    toiminto.appendChild(lukko);

    const salasana = document.createElement("button");
    salasana.className = "nappi-hillitty";
    salasana.textContent = "Salasana";
    salasana.addEventListener("click", () => vaihdaSalasana(u.username));
    toiminto.appendChild(salasana);

    const poista = document.createElement("button");
    poista.className = "nappi-vaara";
    poista.textContent = "Poista";
    poista.addEventListener("click", () => poistaKayttaja(u));
    toiminto.appendChild(poista);

    tr.appendChild(toiminto);

    tbody.appendChild(tr);
  }
}

/**
 * Roolin vaihto suoraan listasta.
 *
 * Valitsin palautetaan entiselleen jos palvelin torjuu muutoksen - muuten
 * ruudulla lukisi eri rooli kuin kannassa, eika kayttaja huomaisi etta
 * muutos ei mennyt lapi.
 */
function roolivalitsin(u) {
  const sel = document.createElement("select");
  sel.className = "roolivalinta";

  for (const avain of Object.keys(ROOLIT)) {
    const o = document.createElement("option");
    o.value = avain;
    o.textContent = ROOLIT[avain];
    if (u.role === avain) o.selected = true;
    sel.appendChild(o);
  }

  sel.addEventListener("change", async () => {
    const uusi = sel.value;
    const vanha = u.role;

    const ok = await vahvista({
      otsikko: "Vaihda rooli",
      teksti: `${u.username}: ${ROOLIT[vanha]} → ${ROOLIT[uusi]}`,
      vahvista: "Vaihda",
      varoitus: vanha === "officer" && uusi !== "officer",
    });

    if (!ok) {
      sel.value = vanha;
      return;
    }

    try {
      const d = await fetch("/api/rooli", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ username: u.username, role: uusi }),
      }).then((r) => r.json());

      if (!d.ok) {
        naytaViesti(d.error || "Roolin vaihto ei onnistunut.");
        sel.value = vanha;
        return;
      }
      naytaViesti(`${u.username}: ${ROOLIT[uusi]}`);
      lataa();
    } catch (err) {
      naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
      sel.value = vanha;
    }
  });

  return sel;
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
  const ok = await vahvista({
    otsikko: locked ? "Lukitse profiili" : "Avaa lukko",
    teksti: locked
      ? `${username} ei pysty enää muuttamaan valintojaan.`
      : `${username} pääsee muuttamaan valintojaan.`,
    vahvista: locked ? "Lukitse" : "Avaa",
  });
  if (!ok) return;

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

/**
 * Officer asettaa uuden salasanan.
 *
 * Salasana naytetaan kirjoitettaessa selvakielisena: officer joutuu
 * kertomaan sen raiderille, joten piilottaminen vain lisaisi kirjoitusvirheita
 * ilman etta suojaisi mitaan.
 */
async function vaihdaSalasana(username) {
  const uusi = await vahvista({
    otsikko: "Vaihda salasana",
    teksti:
      `Aseta uusi salasana käyttäjälle ${username}.\n\n` +
      "Hänen avoimet istuntonsa katkeavat, joten hän joutuu kirjautumaan " +
      "uudelleen tällä salasanalla.",
    vahvista: "Aseta salasana",
    syote: {
      tyyppi: "text",
      vihje: "Uusi salasana",
      minimi: 6,
      virhe: "Salasanan on oltava vähintään 6 merkkiä.",
    },
  });

  if (uusi === null) return;

  try {
    const d = await fetch("/api/salasana", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username, password: uusi }),
    }).then((r) => r.json());

    if (!d.ok) {
      naytaViesti(d.error || "Salasanan vaihto ei onnistunut.");
      return;
    }
    naytaViesti(`${username}: salasana vaihdettu.`);
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- jäsenten luonti ja poisto ---------- */

document.getElementById("uusi").addEventListener("submit", async (e) => {
  e.preventDefault();

  const tiedot = {
    username: $("u-tunnus").value.trim(),
    character_name: $("u-hahmo").value.trim(),
    role: $("u-rooli").value,
    password: $("u-salasana").value,
  };

  const ok = await vahvista({
    otsikko: "Luo jäsen",
    teksti:
      `Tunnus: ${tiedot.username}\n` +
      `Hahmo: ${tiedot.character_name || tiedot.username}\n` +
      `Rooli: ${ROOLIT[tiedot.role]}\n\n` +
      "Kerro salasana hänelle itse — sitä ei lähetetä mihinkään.",
    vahvista: "Luo",
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/kayttaja", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(tiedot),
    }).then((r) => r.json());

    if (!d.ok) {
      naytaViesti(d.error || "Luonti ei onnistunut.");
      return;
    }

    naytaViesti(`${d.username} luotu.`);
    $("u-tunnus").value = "";
    $("u-hahmo").value = "";
    $("u-salasana").value = "";
    $("u-rooli").value = "raider";
    lataa();
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

async function poistaKayttaja(u) {
  const ok = await vahvista({
    otsikko: "Poista jäsen",
    teksti:
      `${u.username} poistetaan pysyvästi.\n\n` +
      "Hänen valintansa katoavat, mutta loottihistoria jää tallelle.\n\n" +
      "Tätä ei voi perua.",
    vahvista: "Poista pysyvästi",
    peruuta: "Älä poista",
    varoitus: true,
  });
  if (!ok) return;

  try {
    const d = await fetch("/api/poista", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: u.username }),
    }).then((r) => r.json());

    if (!d.ok) {
      naytaViesti(d.error || "Poisto ei onnistunut.");
      return;
    }
    naytaViesti(`${u.username} poistettu.`);
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
