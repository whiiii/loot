/**
 * Hahmoikkuna: paikkojen piirto ja itemin valinta.
 *
 * Itemien nimet ja ikonit tulevat Wowheadilta linkin id:n perusteella.
 * Sivusto ei tallenna niita, joten patchin jalkeen tiedot ovat oikein
 * ilman etta taalla tehdaan mitaan.
 */

// Wowheadin osoitteen versio-osa. Forever on Classicin jatko, joten
// Classic-itemit loytyvat samoilla id:lla.
const WH = "https://www.wowhead.com/forever";

const ROOLIT = { social: "Social", raider: "Raider", officer: "Officer" };

let tila = { raid: null, paikat: [], items: [], picks: {}, lukittu: false };
let avoinPaikka = null;

const $ = (id) => document.getElementById(id);

/* ---------- lataus ---------- */

async function lataa() {
  const [minaVastaus, nakymaVastaus] = await Promise.all([
    fetch("/api/mina").then((r) => r.json()),
    fetch("/api/nakyma").then((r) => r.json()),
  ]);

  if (!minaVastaus.ok) {
    location.href = "/kirjaudu";
    return;
  }

  const u = minaVastaus.user;
  $("nimi").textContent = u.username;
  $("rooli").textContent = ROOLIT[u.role] || u.role;
  tila.lukittu = !!u.locked;
  $("lukkoilmoitus").hidden = !tila.lukittu;

  if (!nakymaVastaus.ok) {
    naytaViesti("Tietojen haku epäonnistui.");
    return;
  }

  tila.raid = nakymaVastaus.raid;
  tila.paikat = nakymaVastaus.paikat ?? [];
  tila.items = nakymaVastaus.items ?? [];
  tila.picks = nakymaVastaus.picks ?? {};

  $("raidi").textContent = tila.raid ? tila.raid.name : "Ei aktiivista raidia";
  piirraPaikat();
}

/* ---------- piirto ---------- */

function piirraPaikat() {
  for (const alue of ["vasen", "oikea", "ala"]) $(alue).innerHTML = "";

  for (const paikka of tila.paikat) {
    const nappi = document.createElement("button");
    nappi.type = "button";
    nappi.className = "paikka";
    nappi.dataset.key = paikka.key;

    const valittu = tila.picks[paikka.key] ?? null;

    nappi.innerHTML = `
      <span class="ruutu"></span>
      <span class="teksti">
        <span class="otsikko">${paikka.nimi}</span>
        <span class="arvo${valittu ? "" : " tyhja"}"></span>
      </span>`;

    const arvo = nappi.querySelector(".arvo");
    if (valittu) {
      // Wowhead korvaa linkin tekstin itemin nimella ja varittaa sen.
      const a = document.createElement("a");
      a.href = `${WH}/item=${valittu}`;
      a.textContent = `item ${valittu}`;
      arvo.appendChild(a);
      nappi.classList.add("valittu");
    } else {
      arvo.textContent = "— ei valintaa —";
    }

    nappi.addEventListener("click", () => avaaValitsin(paikka));
    $(paikka.puoli).appendChild(nappi);
  }

  paivitaWowhead();
}

/**
 * Pyytaa Wowheadin skriptia kasittelemaan juuri lisatyt linkit.
 *
 * Skripti kay sivun lapi kerran latauksessa. Kun linkkeja syntyy vasta
 * sen jalkeen, ne jaavat kasittelematta ellei sita pyydeta uudelleen.
 */
function paivitaWowhead() {
  // Ulkopuolinen skripti ei saa kaataa tallennusta. Jos Wowhead on alhaalla
  // tai estetty, linkit jaavat pelkiksi id-numeroiksi - se on rumaa mutta
  // sivusto toimii.
  try {
    const wh = window.$WowheadPower;
    if (wh && typeof wh.refreshLinks === "function") wh.refreshLinks(true);
  } catch (err) {
    /* ei mitaan */
  }
}

/* ---------- valitsin ---------- */

function avaaValitsin(paikka) {
  if (tila.lukittu) {
    naytaViesti("Profiili on lukittu.");
    return;
  }
  if (!tila.raid) {
    naytaViesti("Aktiivista raidia ei ole.");
    return;
  }

  avoinPaikka = paikka;
  $("valitsin-otsikko").textContent = paikka.nimi;

  const lista = $("valitsin-lista");
  lista.innerHTML = "";

  const sopivat = tila.items.filter((i) => i.slot === paikka.slot);

  if (sopivat.length === 0) {
    lista.innerHTML =
      '<p class="himmea">Tähän paikkaan ei ole itemejä tässä raidissa.</p>';
  }

  for (const item of sopivat) {
    const rivi = document.createElement("button");
    rivi.type = "button";
    rivi.className = "rivi";

    const a = document.createElement("a");
    a.href = `${WH}/item=${item.item_id}`;
    a.textContent = `item ${item.item_id}`;
    // Linkkia ei seurata: klikkaus on valinta, ei siirtyma Wowheadiin.
    a.addEventListener("click", (e) => e.preventDefault());

    rivi.appendChild(a);

    if (item.boss) {
      const boss = document.createElement("span");
      boss.className = "boss";
      boss.textContent = item.boss;
      rivi.appendChild(boss);
    }

    rivi.addEventListener("click", () => valitse(item.item_id));
    lista.appendChild(rivi);
  }

  $("peite").hidden = false;
  paivitaWowhead();
}

function suljeValitsin() {
  $("peite").hidden = true;
  avoinPaikka = null;
}

async function valitse(itemId) {
  if (!avoinPaikka) return;
  const paikka = avoinPaikka;
  suljeValitsin();
  await tallenna(paikka.key, itemId);
}

async function tallenna(slotKey, itemId) {
  try {
    const vastaus = await fetch("/api/valinta", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ slot_key: slotKey, item_id: itemId }),
    });
    const data = await vastaus.json();

    if (!data.ok) {
      naytaViesti(data.error || "Tallennus ei onnistunut.");
      return;
    }

    // Palvelin voi pudottaa saman itemin toisesta paikasta, joten tila
    // haetaan uudelleen sen sijaan etta arvattaisiin lopputulos.
    const uusi = await fetch("/api/nakyma").then((r) => r.json());
    if (uusi.ok) {
      tila.picks = uusi.picks ?? {};
      piirraPaikat();
    }
    naytaViesti(itemId ? "Tallennettu." : "Valinta poistettu.");
  } catch (err) {
    // Virheen teksti nakyviin sellaisenaan.
    //
    // Tassa luki aiemmin pelkka "Yhteysvirhe", vaikka tallennus oli
    // mennyt lapi ja vika oli vasta sen jalkeisessa piirrossa. Yleinen
    // teksti vei tutkimuksen vaaraan suuntaan.
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
    console.error("tallenna():", err);
  }
}

/* ---------- apurit ---------- */

let viestiAjastin = null;
function naytaViesti(teksti) {
  const el = $("viesti");
  el.textContent = teksti;
  el.classList.add("nakyy");
  clearTimeout(viestiAjastin);
  viestiAjastin = setTimeout(() => el.classList.remove("nakyy"), 2200);
}

// Hahmokuva on valinnainen: jos tiedostoa ei ole, naytetaan teksti sen
// sijaan etta jaisi rikkinainen kuvake.
const hahmokuva = $("hahmokuva");
if (hahmokuva) {
  hahmokuva.addEventListener("error", () => {
    hahmokuva.hidden = true;
    $("keski-tyhja").hidden = false;
  });
}

$("sulje").addEventListener("click", suljeValitsin);
$("tyhjenna").addEventListener("click", async () => {
  if (!avoinPaikka) return;
  const paikka = avoinPaikka;
  suljeValitsin();
  await tallenna(paikka.key, null);
});
$("peite").addEventListener("click", (e) => {
  if (e.target === $("peite")) suljeValitsin();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") suljeValitsin();
});

$("ulos").addEventListener("click", async () => {
  await fetch("/api/ulos", { method: "POST" });
  location.href = "/";
});

lataa();
