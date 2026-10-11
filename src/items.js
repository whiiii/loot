/**
 * Item names, icons and tooltips.
 *
 * The data is fetched from Wowhead's data endpoint once per item id and
 * cached in the database. The page therefore does not depend on an
 * external script working in the browser — that was the earlier
 * approach, and it failed silently.
 */

const SOURCE = "https://nether.wowhead.com/classic/tooltip/item/";

/**
 * How many missing items are fetched in one request.
 *
 * A Worker has a cap on how many outbound requests one invocation may
 * make. The rest are fetched next time, so the cache fills over a few
 * page loads and nothing breaks.
 */
const FETCH_CAP = 20;

export async function getItemDetails(env, itemIds) {
  const ids = [...new Set(itemIds.filter((n) => Number.isFinite(n)))];
  if (ids.length === 0) return {};

  const placeholders = ids.map(() => "?").join(",");
  const cached = await env.DB.prepare(
    `SELECT item_id, name, quality, icon, tooltip
       FROM item_cache WHERE item_id IN (${placeholders})`
  )
    .bind(...ids)
    .all();

  const result = {};
  for (const row of cached.results ?? []) result[row.item_id] = row;

  const missing = ids.filter((id) => !result[id]).slice(0, FETCH_CAP);
  if (missing.length === 0) return result;

  const fetched = await Promise.all(missing.map((id) => fetchOne(id)));

  const writes = [];
  for (const item of fetched) {
    if (!item) continue;
    result[item.item_id] = item;
    writes.push(
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
  if (writes.length) await env.DB.batch(writes);

  return result;
}

async function fetchOne(itemId) {
  try {
    const response = await fetch(SOURCE + itemId, {
      headers: { "user-agent": "loot-guild-tool (+kiltatyokalu)" },
      cf: { cacheTtl: 86400, cacheEverything: true },
    });
    if (!response.ok) return null;

    const data = await response.json();
    if (!data || !data.name) return null;

    return {
      item_id: itemId,
      name: String(data.name),
      quality: Number.isFinite(data.quality) ? data.quality : null,
      icon: data.icon ? String(data.icon) : null,
      tooltip: sanitise(data.tooltip ?? ""),
    };
  } catch {
    return null;
  }
}

/**
 * The tooltip comes from an external site and is written into the page
 * as HTML, so everything executable is stripped from it.
 *
 * Wowhead is a trustworthy source, but "trustworthy source" is not a
 * protection — it is an assumption. If it ever failed, the code would
 * run in every raider's browser.
 */
function sanitise(html) {
  return String(html)
    .replace(/<\s*script[\s\S]*?<\s*\/\s*script\s*>/gi, "")
    .replace(/<\s*iframe[\s\S]*?<\s*\/\s*iframe\s*>/gi, "")
    .replace(/\son\w+\s*=\s*"[^"]*"/gi, "")
    .replace(/\son\w+\s*=\s*'[^']*'/gi, "")
    .replace(/javascript:/gi, "");
}
