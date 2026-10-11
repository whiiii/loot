/**
 * Transfer: the export to the addon and the import from it.
 *
 * Its own page rather than tacked onto the member list, because these
 * two are the start and the end of a raid night — not something browsed
 * alongside everything else.
 */

const $ = (id) => document.getElementById(id);

/* ---------- export ---------- */

$("create-export").addEventListener("click", async () => {
  try {
    const d = await fetch("/api/export").then((r) => r.json());
    if (!d.ok) {
      showMessage(d.error || "Vienti epäonnistui.");
      return;
    }

    const box = $("export");
    box.value = d.text;
    box.hidden = false;
    $("copy").hidden = false;
    $("raid").textContent = d.raid;
    $("export-info").textContent =
      `${d.raid} — ${d.characters} hahmoa, ${d.text.length} merkkiä. ` +
      "Liitä teksti addonin Tuonti-välilehdelle.";
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

$("copy").addEventListener("click", async () => {
  const box = $("export");
  try {
    // The clipboard API needs a secure context and can still fail.
    // Selecting the field is a fallback that always works.
    await navigator.clipboard.writeText(box.value);
    showMessage("Kopioitu leikepöydälle.");
  } catch {
    box.focus();
    box.select();
    showMessage("Kopioi näppäimistöltä: Ctrl+C");
  }
});

/* ---------- import ---------- */

$("do-import").addEventListener("click", async () => {
  const text = $("import").value.trim();
  if (!text) {
    showMessage("Liitä ensin addonin vienti.");
    return;
  }

  try {
    const d = await fetch("/api/import", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text, label: $("import-label").value.trim() }),
    }).then((r) => r.json());

    if (!d.ok) {
      showMessage(d.error || "Tuonti epäonnistui.");
      return;
    }

    // Also report what was NOT recognised. A name that matches nobody is
    // written to the history but shows in no profile, and that is exactly
    // the case that would otherwise go unnoticed.
    const parts = [`${d.added} uutta riviä (${d.rows} yhteensä)`];
    if (d.unmatched > 0) {
      parts.push(`${d.unmatched} nimeä ei vastaa ketään jäsentä`);
    }
    if (d.skipped > 0) parts.push(`${d.skipped} riviä ohitettu`);
    parts.push('<a href="/imports">Katso loki</a>');

    $("import-info").innerHTML = parts.join(" · ");
    $("import").value = "";
    $("import-label").value = "";
    showMessage("Loottihistoria tuotu.");
  } catch (err) {
    showMessage("Virhe: " + (err && err.message ? err.message : String(err)));
  }
});

/* ---------- helpers ---------- */

let messageTimer = null;
function showMessage(text) {
  const el = $("message");
  el.textContent = text;
  el.classList.add("visible");
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => el.classList.remove("visible"), 2600);
}

$("logout").addEventListener("click", async () => {
  await fetch("/api/logout", { method: "POST" });
  location.href = "/";
});
