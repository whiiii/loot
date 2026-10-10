/**
 * Ylläpitosivu: profiililista, lukot ja vienti addoniin.
 */

const ROOLIT = window.RANGIT;
const $ = (id) => document.getElementById(id);

let paikkoja = 0;
let kaikki = [];

/**
 * Kuvakkeet polkuina, ei valmiina elementteina.
 *
 * SVG kirjoitetaan koodissa eika haeta tiedostoina: kuvakkeita on muutama
 * ja ne ovat pieniä, joten erilliset pyynnot maksaisivat enemman kuin
 * saastaisivat. Viiva perii varinsa napilta, joten sama kuvake sopii
 * jokaiseen savyyn.
 */
const KUVAKE = {
  lukkoKiinni:
    '<rect x="3" y="11" width="18" height="11" rx="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path>',
  lukkoAuki:
    '<rect x="3" y="11" width="18" height="11" rx="2"></rect><path d="M7 11V7a5 5 0 0 1 9.9-1"></path>',
  avain:
    '<circle cx="7.5" cy="15.5" r="4.5"></circle><path d="M10.7 12.3 21 2"></path><path d="m17 6 3 3"></path>',
  roska:
    '<polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>',
};

/** Nappi tai linkki, jolla on kuvake ja teksti. */
function teeNappi({ teksti, kuvake, luokka, toiminto, osoite }) {
  const el = document.createElement(osoite ? "a" : "button");
  if (osoite) el.href = osoite;
  else el.type = "button";

  el.className = luokka + " nappi-kuvake";
  el.innerHTML =
    `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" ` +
    `stroke="currentColor" stroke-width="2" stroke-linecap="round" ` +
    `stroke-linejoin="round">${kuvake}</svg><span></span>`;

  el.querySelector("span").textContent = teksti;
  if (toiminto) el.addEventListener("click", toiminto);
  return el;
}

/**
 * Lajittelu otsikon mukaan.
 *
 * Jarjestysarvo haetaan omalla funktiolla kentan sijaan, koska naytettava
 * arvo ja lajiteltava arvo eivat ole sama asia: luokka talletetaan
 * avaimena ("warrior") mutta listassa lukee nimi, ja valintojen maara on
 * luku vaikka solussa lukee "16 / 17".
 */
const LAJITTELUT = {
  username:  (u) => (u.username || "").toLowerCase(),
  hahmo:     (u) => hahmonNimi(u).toLowerCase(),
  class:     (u) => (LUOKAT[u.class] ? LUOKAT[u.class].nimi : "ö").toLowerCase(),
  raid_role: (u) => (RAIDIROOLIT[u.raid_role] || "ö").toLowerCase(),
  role:      (u) => ["officer", "raider", "social"].indexOf(u.role),
  valintoja: (u) => u.valintoja,
  locked:    (u) => (u.locked ? 1 : 0),
};

let lajitteluKentta = "role";
let lajitteluNouseva = true;

function jarjesta(users) {
  const avain = LAJITTELUT[lajitteluKentta] || LAJITTELUT.username;
  const suunta = lajitteluNouseva ? 1 : -1;

  return [...users].sort((a, b) => {
    const x = avain(a);
    const y = avain(b);
    if (typeof x === "number" && typeof y === "number") return (x - y) * suunta;
    return String(x).localeCompare(String(y), "fi") * suunta;
  });
}

/**
 * Tayttaa valitsimen avain-nimi-parien perusteella. Tyhja = "ei valittu".
 *
 * Luokkavalitsimessa jokainen vaihtoehto varitetaan omalla varillaan, ei
 * vain valittu. Muuten koko lista nayttaa siita luokasta jonka sattuu
 * olevan valittuna, mika on hamaavaa juuri silloin kun luokkaa vaihdetaan.
 */
function taytaValitsin(sel, parit, valittu, tyhjaTeksti, varit) {
  sel.innerHTML = "";

  const tyhja = document.createElement("option");
  tyhja.value = "";
  tyhja.textContent = tyhjaTeksti;
  tyhja.style.color = "var(--himmea)";
  sel.appendChild(tyhja);

  for (const [avain, nimi] of parit) {
    const o = document.createElement("option");
    o.value = avain;
    o.textContent = nimi;
    if (varit) o.style.color = varit(avain);
    if (valittu === avain) o.selected = true;
    sel.appendChild(o);
  }
  if (!valittu) tyhja.selected = true;
}

const LUOKKAPARIT = Object.entries(LUOKAT).map(([k, v]) => [k, v.nimi]);
const ROOLIPARIT = Object.entries(RAIDIROOLIT);

async function lataa() {
  try {
    const d = await fetch("/api/kayttajat").then((r) => r.json());
    if (!d.ok) {
      $("kayttajat").innerHTML =
        `<tr><td colspan="8" class="himmea">${d.error || "Haku epäonnistui."}</td></tr>`;
      return;
    }

    paikkoja = d.paikkoja || 0;
    kaikki = d.users || [];
    $("raidi").textContent = d.raid ? d.raid.name : "Ei aktiivista raidia";
    piirra(jarjesta(kaikki));
    merkitseOtsikko();
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

function piirra(users) {
  const tbody = $("kayttajat");
  tbody.innerHTML = "";

  if (users.length === 0) {
    tbody.innerHTML = '<tr><td colspan="8" class="himmea">Ei käyttäjiä.</td></tr>';
    return;
  }

  for (const u of users) {
    const tr = document.createElement("tr");

    tr.appendChild(solu(u.username));

    // Hahmon nimi luokan varissa, kuten pelissa - ja samalla linkki
    // profiiliin. Nimi on se mita officer etsii listasta, joten se on myos
    // luontevin paikka avata profiili.
    const hahmo = document.createElement("td");
    const linkki = document.createElement("a");
    linkki.className = "hahmolinkki";
    linkki.href = "/profiili?katso=" + encodeURIComponent(u.username);
    linkki.textContent = hahmonNimi(u);
    linkki.style.color = luokanVari(u.class);
    linkki.title = "Avaa profiili";
    hahmo.appendChild(linkki);
    tr.appendChild(hahmo);

    tr.appendChild(kenttaSolu(u, "class", LUOKKAPARIT, "— luokka —"));
    tr.appendChild(kenttaSolu(u, "raid_role", ROOLIPARIT, "— rooli —"));

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

    // Napit ovat samanlevyisia ja kuvakkeellisia: sama leveys pitaa rivit
    // suorassa, ja kuvake erottaa toiminnon nopeammin kuin sanan lukeminen.
    // Savy kertoo painoarvon - lukko odottaa tekemista, poisto on
    // peruuttamaton.
    toiminto.appendChild(
      teeNappi({
        teksti: u.locked ? "Avaa" : "Lukitse",
        kuvake: u.locked ? KUVAKE.lukkoAuki : KUVAKE.lukkoKiinni,
        luokka: u.locked ? "nappi-korostus" : "nappi-hillitty",
        toiminto: () => vaihdaLukko(u.username, !u.locked),
      })
    );

    toiminto.appendChild(
      teeNappi({
        teksti: "Salasana",
        kuvake: KUVAKE.avain,
        luokka: "nappi-hillitty",
        toiminto: () => vaihdaSalasana(u.username),
      })
    );

    toiminto.appendChild(
      teeNappi({
        teksti: "Poista",
        kuvake: KUVAKE.roska,
        luokka: "nappi-vaara",
        toiminto: () => poistaKayttaja(u),
      })
    );

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

/**
 * Yhden kentan valitsin taulukossa.
 *
 * Lahettaa vain sen kentan jota muutettiin. Koko rivin lahettaminen
 * tarkoittaisi etta samalla kirjoitetaan yli kentat joita ei koskettu -
 * ja jos kaksi officeria muokkaa yhta aikaa, jalkimmainen pyyhkii
 * ensimmaisen tyon.
 */
function kenttaSolu(u, kentta, parit, tyhjaTeksti) {
  const td = document.createElement("td");
  const sel = document.createElement("select");
  sel.className = "roolivalinta";

  const varit = kentta === "class" ? luokanVari : null;
  taytaValitsin(sel, parit, u[kentta] || "", tyhjaTeksti, varit);

  if (kentta === "class") sel.style.color = luokanVari(u.class);

  sel.addEventListener("change", async () => {
    const vanha = u[kentta] || "";
    try {
      const d = await fetch("/api/hahmo", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ username: u.username, [kentta]: sel.value }),
      }).then((r) => r.json());

      if (!d.ok) {
        naytaViesti(d.error || "Muutos ei onnistunut.");
        sel.value = vanha;
        return;
      }
      naytaViesti(`${u.username} päivitetty.`);
      lataa();
    } catch (err) {
      naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
      sel.value = vanha;
    }
  });

  td.appendChild(sel);
  return td;
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

/* ---------- lajittelu ---------- */

function merkitseOtsikko() {
  document.querySelectorAll("th[data-lajittele]").forEach((th) => {
    const oma = th.dataset.lajittele === lajitteluKentta;
    th.classList.toggle("lajiteltu", oma);
    th.dataset.suunta = oma ? (lajitteluNouseva ? "ylos" : "alas") : "";
  });
}

document.querySelectorAll("th[data-lajittele]").forEach((th) => {
  th.addEventListener("click", () => {
    const kentta = th.dataset.lajittele;

    // Sama otsikko toistamiseen kaantaa suunnan, uusi aloittaa nousevasta.
    if (kentta === lajitteluKentta) {
      lajitteluNouseva = !lajitteluNouseva;
    } else {
      lajitteluKentta = kentta;
      lajitteluNouseva = true;
    }

    piirra(jarjesta(kaikki));
    merkitseOtsikko();
  });
});

/* ---------- jäsenten luonti ja poisto ---------- */

document.getElementById("uusi").addEventListener("submit", async (e) => {
  e.preventDefault();

  const tiedot = {
    username: $("u-tunnus").value.trim(),
    first_name: $("u-etunimi").value.trim(),
    last_name: $("u-sukunimi").value.trim(),
    class: $("u-luokka").value,
    raid_role: $("u-raidirooli").value,
    role: $("u-rooli").value,
    password: $("u-salasana").value,
  };

  const ok = await vahvista({
    otsikko: "Luo jäsen",
    teksti:
      `Tunnus: ${tiedot.username}\n` +
      `Hahmo: ${[tiedot.first_name || tiedot.username, tiedot.last_name].filter(Boolean).join(" ")}\n` +
      `Luokka: ${LUOKAT[tiedot.class] ? LUOKAT[tiedot.class].nimi : "—"}\n` +
      `Rooli: ${RAIDIROOLIT[tiedot.raid_role] || "—"}\n` +
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
    $("u-etunimi").value = "";
    $("u-sukunimi").value = "";
    $("u-salasana").value = "";
    $("u-luokka").value = "";
    $("u-raidirooli").value = "";
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

// Luontilomakkeen valitsimet taytetaan samasta lahteesta kuin taulukon,
// jottei listoja ole kahta eri paikassa.
taytaValitsin($("u-luokka"), LUOKKAPARIT, "", "— luokka —", luokanVari);
taytaValitsin($("u-raidirooli"), ROOLIPARIT, "", "— rooli —");
$("u-luokka").addEventListener("change", () => {
  $("u-luokka").style.color = luokanVari($("u-luokka").value);
});

lataa();
