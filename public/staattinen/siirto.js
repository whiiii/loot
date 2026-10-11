/**
 * Siirto: vienti addoniin ja tuonti addonista.
 *
 * Omalla sivullaan eika profiililistan perassa, koska nama kaksi ovat
 * raidi-illan alku ja loppu - ei jotain mita selataan muun ohessa.
 */

const $ = (id) => document.getElementById(id);

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
    $("raidi").textContent = d.raid;
    $("vientitiedot").textContent =
      `${d.raid} — ${d.hahmoja} hahmoa, ${d.teksti.length} merkkiä. ` +
      "Liitä teksti addonin Tuonti-välilehdelle.";
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

/* ---------- tuonti ---------- */

$("tuo-historia").addEventListener("click", async () => {
  const teksti = $("historia").value.trim();
  if (!teksti) {
    naytaViesti("Liitä ensin addonin vienti.");
    return;
  }

  try {
    const d = await fetch("/api/historia", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ teksti, label: $("tuonti-nimi").value.trim() }),
    }).then((r) => r.json());

    if (!d.ok) {
      naytaViesti(d.error || "Tuonti epäonnistui.");
      return;
    }

    // Kerrotaan myös se mitä EI tunnistettu. Nimi joka ei vastaa ketään
    // kirjautuu historiaan mutta ei näy kenenkään profiilissa, ja se on
    // juuri se tapaus joka jäisi muuten huomaamatta.
    const osat = [`${d.uusia} uutta riviä (${d.rivit} yhteensä)`];
    if (d.tunnistamattomia > 0) {
      osat.push(`${d.tunnistamattomia} nimeä ei vastaa ketään jäsentä`);
    }
    if (d.ohitettu > 0) osat.push(`${d.ohitettu} riviä ohitettu`);
    osat.push('<a href="/historia">Katso loki</a>');

    $("tuontitiedot").innerHTML = osat.join(" · ");
    $("historia").value = "";
    $("tuonti-nimi").value = "";
    naytaViesti("Loottihistoria tuotu.");
  } catch (err) {
    naytaViesti("Virhe: " + (err && err.message ? err.message : String(err)));
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
