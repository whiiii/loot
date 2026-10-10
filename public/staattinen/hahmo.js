/**
 * Hahmoikkuna: paikkojen piirto ja itemin valinta.
 *
 * Itemien nimet, ikonit ja tooltipit tulevat omasta rajapinnasta, joka
 * hakee ne Wowheadilta kerran ja sailoo. Aiemmin tama tehtiin Wowheadin
 * omalla selainskriptilla, mutta se paatti itse mita linkkeja se kasittelee
 * eika kertonut mitaan kun se ei tehnyt mitaan.
 */

const IKONI = "https://wow.zamimg.com/images/wow/icons/large/";
const ROOLIT = { social: "Social", raider: "Raider", officer: "Officer" };

let tila = { raid: null, paikat: [], items: [], picks: {}, tiedot: {}, lukittu: false };
let avoinPaikka = null;

const $ = (id) => document.getElementById(id);

/* ---------- lataus ---------- */

async function lataa() {
  try {
    const [mina, nakyma] = await Promise.all([
      fetch("/api/mina").then((r) => r.json()),
      fetch("/api/nakyma").then((r) => r.json()),
    ]);

    if (!mina.ok) {
      location.href = "/kirjaudu";
      return;
    }

    // Nakyvissa on hahmon nimi, ei kirjautumistunnus. Raidissa katsotaan
    // hahmoa, ja tunnus on vain tapa paasta sisaan.
    $("nimi").textContent = mina.user.character_name || mina.user.username;
    $("rooli").textContent = ROOLIT[mina.user.role] || mina.user.role;
    tila.rooli = mina.user.role;

    // Lukko ei rajoita officeria, joten hanelle se ei ole "lukittu" tila
    // vaan pelkka merkinta.
    tila.lukittu = !!mina.user.locked && mina.user.role !== "officer";
    $("lukkoilmoitus").hidden = !tila.lukittu;
    $("yllapitolinkki").hidden = mina.user.role !== "officer";
    $("tallenna").hidden = tila.lukittu;

    if (!nakyma.ok) {
      naytaViesti(nakyma.error || "Tietojen haku epäonnistui.");
      return;
    }

    tila.raid = nakyma.raid;
    tila.paikat = nakyma.paikat ?? [];
    tila.items = nakyma.items ?? [];
    tila.picks = nakyma.picks ?? {};
    tila.tiedot = nakyma.tiedot ?? {};

    $("raidi").textContent = tila.raid ? tila.raid.name : "Ei aktiivista raidia";
    piirraPaikat();
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
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
    p.textContent = "Tähän paikkaan ei ole itemejä tässä raidissa.";
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
      otsikko: "Tämän jälkeen et pääse muokkaamaan",
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
