/**
 * Hahmoikkuna: paikkojen piirto ja itemin valinta.
 *
 * Itemien nimet, ikonit ja tooltipit tulevat omasta rajapinnasta, joka
 * hakee ne Wowheadilta kerran ja sailoo. Aiemmin tama tehtiin Wowheadin
 * omalla selainskriptilla, mutta se paatti itse mita linkkeja se kasittelee
 * eika kertonut mitaan kun se ei tehnyt mitaan.
 */

const IKONI = "https://wow.zamimg.com/images/wow/icons/large/";

let tila = {
  raid: null, paikat: [], items: [], picks: {}, tiedot: {},
  saadut: new Set(), lukittu: false,
};
let avoinPaikka = null;

const $ = (id) => document.getElementById(id);

/* ---------- lataus ---------- */

// Officer voi avata toisen profiilin osoitteella /profiili?katso=tunnus.
const katsottava = new URLSearchParams(location.search).get("katso") || "";

async function lataa() {
  try {
    const nakymaOsoite =
      "/api/nakyma" + (katsottava ? "?username=" + encodeURIComponent(katsottava) : "");

    const [mina, nakyma] = await Promise.all([
      fetch("/api/mina").then((r) => r.json()),
      fetch(nakymaOsoite).then((r) => r.json()),
    ]);

    if (!mina.ok) {
      location.href = "/kirjaudu";
      return;
    }

    if (!nakyma.ok) {
      naytaViesti(nakyma.error || "Tietojen haku epäonnistui.");
      return;
    }

    // Nakyvissa on hahmon nimi, ei kirjautumistunnus. Raidissa katsotaan
    // hahmoa, ja tunnus on vain tapa paasta sisaan.
    const u = nakyma.user || mina.user;
    const nimi = $("nimi");
    nimi.textContent = hahmonNimi(u);
    nimi.style.color = luokanVari(u.class);

    // Luokka ja raidirooli yhdella rivilla nimen alla. Killan arvo ei ole
    // tassa: se kuuluu yllapitoon, ei hahmoikkunaan.
    const osat = [];
    if (LUOKAT[u.class]) osat.push(LUOKAT[u.class].nimi);
    if (RAIDIROOLIT[u.raid_role]) osat.push(RAIDIROOLIT[u.raid_role]);
    $("rooli").textContent = osat.join(" · ");

    tila.rooli = mina.user.role;
    tila.katselu = nakyma.omaProfiili === false;

    // Toisen profiili on katseltava, ei muokattava. Muokkaus kuuluu sille
    // jonka profiili se on - officer avaa lukon, raideri valitsee itse.
    if (tila.katselu) {
      tila.lukittu = true;
      $("katseluilmoitus").hidden = false;
      $("katseltava").textContent = hahmonNimi(u);
      $("lukkoilmoitus").hidden = true;
      $("tallenna").hidden = true;
      if (mina.user.role === "officer") naytaOfficerValikko();
    } else {
      // Lukko ei rajoita officeria, joten hanelle se ei ole "lukittu" tila
      // vaan pelkka merkinta.
      tila.lukittu = !!mina.user.locked && mina.user.role !== "officer";
      $("lukkoilmoitus").hidden = !tila.lukittu;
      if (mina.user.role === "officer") naytaOfficerValikko();
      $("tallenna").hidden = tila.lukittu;
    }

    tila.raid = nakyma.raid;
    tila.paikat = nakyma.paikat ?? [];
    tila.items = nakyma.items ?? [];
    tila.picks = nakyma.picks ?? {};
    tila.tiedot = nakyma.tiedot ?? {};
    tila.saadut = new Set(nakyma.saadut ?? []);

    $("raidi").textContent = tila.raid ? tila.raid.name : "Ei aktiivista raidia";
    piirraPaikat();
    lataaRoster(u.username);
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
}

/* ---------- jäsenlista ---------- */

/**
 * Jäsenlista sivupalkkiin.
 *
 * Kaikille, ei vain officerille: valintojen vertailu on koko sivuston
 * tarkoitus, ja raiderin pitää nähdä kuka muu on varannut saman itemin.
 */
async function lataaRoster(nykyinen) {
  const sailio = $("roster-lista");

  try {
    const d = await fetch("/api/roster").then((r) => r.json());

    if (!d.ok) {
      sailio.innerHTML = '<p class="himmea">Lista ei latautunut.</p>';
      return;
    }

    sailio.innerHTML = "";

    for (const j of d.jasenet) {
      const rivi = document.createElement("button");
      rivi.type = "button";
      rivi.className = "roster-rivi";
      if (j.username === nykyinen) rivi.classList.add("nyt");

      const nimi = document.createElement("span");
      nimi.className = "roster-nimi";
      nimi.textContent = hahmonNimi(j);
      nimi.style.color = luokanVari(j.class);
      rivi.appendChild(nimi);

      // Luokka, rooli ja valintojen määrä: niistä näkee kenen profiilia
      // kannattaa katsoa ja kuka ei ole vielä täyttänyt omaansa.
      const osat = [];
      if (LUOKAT[j.class]) osat.push(LUOKAT[j.class].nimi);
      if (RAIDIROOLIT[j.raid_role]) osat.push(RAIDIROOLIT[j.raid_role]);

      const tiedot = document.createElement("span");
      tiedot.className = "roster-tiedot";
      tiedot.textContent =
        (osat.join(" · ") || "—") + `  ${j.valintoja}/${d.paikkoja}`;
      rivi.appendChild(tiedot);

      rivi.addEventListener("click", () => {
        location.href = "/profiili?katso=" + encodeURIComponent(j.username);
      });

      sailio.appendChild(rivi);
    }

    if (d.jasenet.length === 0) {
      sailio.innerHTML = '<p class="himmea">Ei jäseniä.</p>';
    }
  } catch {
    sailio.innerHTML = '<p class="himmea">Lista ei latautunut.</p>';
  }
}

/* ---------- itemin esitys ---------- */

function tiedot(itemId) {
  return tila.tiedot[itemId] || tila.tiedot[String(itemId)] || null;
}

/**
 * Ikoni ja nimi laadun varissa. Jos tietoja ei ole, naytetaan id -
 * sivusto ei saa jaada tyhjaksi siksi etta ulkopuolinen lahde ei vastannut.
 */
function itemElementti(itemId) {
  const d = tiedot(itemId);
  const kaari = document.createElement("span");
  kaari.className = "item";
  kaari.dataset.itemId = itemId;

  const ikoni = document.createElement("span");
  ikoni.className = "item-ikoni";
  if (d && d.icon) {
    const img = document.createElement("img");
    img.src = IKONI + d.icon + ".jpg";
    img.alt = "";
    img.loading = "lazy";
    ikoni.appendChild(img);
  }

  const teksti = document.createElement("span");
  teksti.className = "item-teksti";

  const nimi = document.createElement("span");
  nimi.className = "item-nimi q" + (d && d.quality != null ? d.quality : 1);
  nimi.textContent = d && d.name ? d.name : "item " + itemId;

  // Item-id nakyviin pienella. Se on se mita addon ja tietokanta kayttavat,
  // joten sen nakeminen helpottaa vertailua ja virheiden etsimista.
  const id = document.createElement("span");
  id.className = "item-id";
  id.textContent = itemId;

  teksti.appendChild(nimi);
  teksti.appendChild(id);

  kaari.appendChild(ikoni);
  kaari.appendChild(teksti);

  // Saatu item merkitaan. Tieto tulee addonista tuodusta loottihistoriasta,
  // joten merkinta kertoo etta item on oikeasti jaettu raidissa - ei sita
  // etta joku olisi kuitannut sen sivustolla.
  if (tila.saadut.has(itemId)) {
    kaari.classList.add("saatu");

    const merkki = document.createElement("span");
    merkki.className = "saatu-merkki";
    merkki.title = "Saatu raidissa";
    merkki.innerHTML =
      '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" ' +
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" ' +
      'stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    kaari.appendChild(merkki);
  }

  return kaari;
}

/* ---------- piirto ---------- */

function piirraPaikat() {
  for (const alue of ["vasen", "oikea", "ala"]) $(alue).innerHTML = "";

  for (const paikka of tila.paikat) {
    const valittu = tila.picks[paikka.key] ?? null;

    const nappi = document.createElement("button");
    nappi.type = "button";
    nappi.className = "paikka" + (valittu ? " valittu" : "");

    const otsikko = document.createElement("span");
    otsikko.className = "otsikko";
    otsikko.textContent = paikka.nimi;

    const sisalto = document.createElement("span");
    sisalto.className = "sisalto";

    if (valittu) {
      sisalto.appendChild(itemElementti(valittu));
    } else {
      const tyhja = document.createElement("span");
      tyhja.className = "tyhja";
      tyhja.textContent = "— ei valintaa —";
      sisalto.appendChild(tyhja);
    }

    nappi.appendChild(otsikko);
    nappi.appendChild(sisalto);
    nappi.addEventListener("click", () => avaaValitsin(paikka));
    $(paikka.puoli).appendChild(nappi);
  }
}

/* ---------- valitsin ---------- */

function avaaValitsin(paikka) {
  if (tila.katselu) { return; }
  if (tila.lukittu) { naytaViesti("Profiili on lukittu."); return; }
  if (!tila.raid)   { naytaViesti("Aktiivista raidia ei ole."); return; }

  avoinPaikka = paikka;
  $("valitsin-otsikko").textContent = paikka.nimi;

  const lista = $("valitsin-lista");
  lista.innerHTML = "";

  const sopivat = tila.items.filter((i) => i.slot === paikka.slot);

  if (sopivat.length === 0) {
    const p = document.createElement("p");
    p.className = "himmea";
    p.textContent = "Tähän paikkaan ei ole itemeitä tässä raidissa.";
    lista.appendChild(p);
  }

  // Aakkosjarjestys nimen mukaan: numerojarjestys ei kerro katsojalle mitaan.
  sopivat.sort((a, b) => {
    const an = tiedot(a.item_id)?.name || String(a.item_id);
    const bn = tiedot(b.item_id)?.name || String(b.item_id);
    return an.localeCompare(bn);
  });

  for (const item of sopivat) {
    const rivi = document.createElement("button");
    rivi.type = "button";
    rivi.className = "rivi";
    rivi.appendChild(itemElementti(item.item_id));

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
}

function suljeValitsin() {
  $("peite").hidden = true;
  piilotaTooltip();
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
      tila.tiedot = uusi.tiedot ?? tila.tiedot;
      piirraPaikat();
    }
    naytaViesti(itemId ? "Tallennettu." : "Valinta poistettu.");
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
    console.error("tallenna():", err);
  }
}

/* ---------- tooltip ---------- */

const tooltip = $("tooltip");

document.addEventListener("mouseover", (e) => {
  const kohde = e.target.closest ? e.target.closest(".item") : null;
  if (!kohde) return;

  const d = tiedot(parseInt(kohde.dataset.itemId, 10));
  if (!d || !d.tooltip) return;

  // Sisalto on siivottu palvelimella: skriptit ja tapahtumakasittelijat
  // on poistettu ennen kuin se tallennettiin.
  tooltip.innerHTML = d.tooltip;
  tooltip.hidden = false;
  siirraTooltip(e);
});

document.addEventListener("mousemove", (e) => {
  if (!tooltip.hidden) siirraTooltip(e);
});

document.addEventListener("mouseout", (e) => {
  const kohde = e.target.closest ? e.target.closest(".item") : null;
  if (kohde) piilotaTooltip();
});

function siirraTooltip(e) {
  const marginaali = 16;
  const leveys = tooltip.offsetWidth;
  const korkeus = tooltip.offsetHeight;

  let x = e.clientX + marginaali;
  let y = e.clientY + marginaali;

  if (x + leveys > window.innerWidth) x = e.clientX - leveys - marginaali;
  if (y + korkeus > window.innerHeight) y = window.innerHeight - korkeus - 8;
  if (y < 8) y = 8;

  tooltip.style.left = x + "px";
  tooltip.style.top = y + "px";
}

function piilotaTooltip() {
  tooltip.hidden = true;
}

/* ---------- apurit ---------- */

let viestiAjastin = null;
function naytaViesti(teksti) {
  const el = $("viesti");
  el.textContent = teksti;
  el.classList.add("nakyy");
  clearTimeout(viestiAjastin);
  viestiAjastin = setTimeout(() => el.classList.remove("nakyy"), 2600);
}

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

/**
 * Tallenna lukitsee profiilin.
 *
 * Valinnat tallentuvat jo klikatessa, joten tama nappi ei tallenna mitaan
 * uutta - se merkitsee profiilin valmiiksi. Siksi se myos kysyy varmistuksen:
 * raider ei paase enaa muuttamaan valintojaan itse.
 */
$("tallenna").addEventListener("click", async () => {
  const officer = tila.rooli === "officer";

  const eka = await vahvista({
    otsikko: "Tallenna profiili",
    teksti: officer
      ? "Merkitäänkö profiili valmiiksi?\n\nLukko ei rajoita officeria, joten pääset muokkaamaan valintoja myös tämän jälkeen."
      : "Valintasi tallentuvat ja profiili merkitään valmiiksi.",
    vahvista: "Tallenna",
  });
  if (!eka) return;

  // Toinen varmistus vain sille jota lukko oikeasti koskee. Officerille se
  // olisi pelkka ylimaarainen klikkaus, koska han paasee muokkaamaan yha.
  if (!officer) {
    const toka = await vahvista({
      otsikko: "Tämän jälkeen et pääse muokkaamaan valintojasi",
      teksti:
        "Profiili lukitaan. Et pysty itse avaamaan sitä etkä muuttamaan " +
        "valintojasi.\n\nMikäli ei kerrasta osunut, niin oleppa jonnekki " +
        "yhteyksissä, sanat tiijätte",
      vahvista: "Ymmärrän, lukitse",
      peruuta: "En vielä",
      varoitus: true,
    });
    if (!toka) return;
  }

  try {
    const data = await fetch("/api/lukitse", { method: "POST" }).then((r) => r.json());
    if (!data.ok) {
      naytaViesti(data.error || "Tallennus ei onnistunut.");
      return;
    }
    naytaViesti("Profiili tallennettu.");
    if (tila.rooli !== "officer") {
      tila.lukittu = true;
      $("lukkoilmoitus").hidden = false;
      $("tallenna").hidden = true;
    }
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

$("ulos").addEventListener("click", async () => {
  await fetch("/api/ulos", { method: "POST" });
  location.href = "/";
});

lataa();
