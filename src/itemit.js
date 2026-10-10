/**
 * Itemien nimet, ikonit ja tooltipit.
 *
 * Tiedot haetaan Wowheadin datapolusta kerran item-id:ta kohden ja
 * sailotaan kantaan. Sivu ei siis ole riippuvainen siita etta ulkopuolinen
 * skripti toimii selaimessa - se oli aiempi tapa, ja se epaonnistui
 * aanettomasti.
 */

const LAHDE = "https://nether.wowhead.com/classic/tooltip/item/";

/**
 * Montako puuttuvaa itemia haetaan yhdella pyynnolla.
 *
 * Workerilla on katto sille montako ulospain menevaa pyyntoa yksi kutsu saa
 * tehda. Loput haetaan seuraavalla kerralla, joten lista tayttyy muutamassa
 * latauksessa eika mikaan kaadu.
 */
const HAKU_KATTO = 20;

export async function haeItemTiedot(env, itemIdt) {
  const idt = [...new Set(itemIdt.filter((n) => Number.isFinite(n)))];
  if (idt.length === 0) return {};

  const paikat = idt.map(() => "?").join(",");
  const loytyneet = await env.DB.prepare(
    `SELECT item_id, name, quality, icon, tooltip
       FROM item_cache WHERE item_id IN (${paikat})`
  )
    .bind(...idt)
    .all();

  const tulos = {};
  for (const r of loytyneet.results ?? []) tulos[r.item_id] = r;

  const puuttuvat = idt.filter((id) => !tulos[id]).slice(0, HAKU_KATTO);
  if (puuttuvat.length === 0) return tulos;

  const haetut = await Promise.all(puuttuvat.map((id) => haeYksi(id)));

  const kirjoitukset = [];
  for (const item of haetut) {
    if (!item) continue;
    tulos[item.item_id] = item;
    kirjoitukset.push(
      env.DB.prepare(
        `INSERT INTO item_cache (item_id, name, quality, icon, tooltip)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(item_id) DO UPDATE SET
           name = excluded.name, quality = excluded.quality,
           icon = excluded.icon, tooltip = excluded.tooltip,
           fetched_at = datetime('now')`
      ).bind(item.item_id, item.name, item.quality, item.icon, item.tooltip)
    );
  }
  if (kirjoitukset.length) await env.DB.batch(kirjoitukset);

  return tulos;
}

async function haeYksi(itemId) {
  try {
    const vastaus = await fetch(LAHDE + itemId, {
      headers: { "user-agent": "loot-guild-tool (+kiltatyokalu)" },
      cf: { cacheTtl: 86400, cacheEverything: true },
    });
    if (!vastaus.ok) return null;

    const data = await vastaus.json();
    if (!data || !data.name) return null;

    return {
      item_id: itemId,
      name: String(data.name),
      quality: Number.isFinite(data.quality) ? data.quality : null,
      icon: data.icon ? String(data.icon) : null,
      tooltip: siivoa(data.tooltip ?? ""),
    };
  } catch {
    return null;
  }
}

/**
 * Tooltip tulee ulkopuoliselta sivustolta ja se kirjoitetaan sivulle
 * HTML:na, joten siita poistetaan kaikki suoritettava.
 *
 * Wowhead on luotettava lahde, mutta "luotettava lahde" ei ole suojaus -
 * se on oletus. Jos se joskus pettaa, koodi ajautuisi jokaisen raiderin
 * selaimessa.
 */
function siivoa(html) {
  return String(html)
    .replace(/<\s*script[\s\S]*?<\s*\/\s*script\s*>/gi, "")
    .replace(/<\s*iframe[\s\S]*?<\s*\/\s*iframe\s*>/gi, "")
    .replace(/\son\w+\s*=\s*"[^"]*"/gi, "")
    .replace(/\son\w+\s*=\s*'[^']*'/gi, "")
    .replace(/javascript:/gi, "");
}
