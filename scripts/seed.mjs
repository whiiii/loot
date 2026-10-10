/**
 * Luo SQL-tiedoston ensimmaisista tunnuksista.
 *
 * Salasanat tiivistetaan taalla eika kannassa, koska Workerin suoritinaikaa
 * ei kannata kuluttaa kertaluontoiseen tyohon. Node tuottaa taysin saman
 * tiivisteen kuin selaimen Web Crypto, kunhan parametrit ovat samat -
 * PBKDF2, SHA-256, 25000 kierrosta, 16 tavun suola, 32 tavun tulos.
 *
 * Kaytto:
 *   node scripts/seed.mjs            (lukee seed.json, kirjoittaa seed.sql)
 *
 * Kumpikaan tiedosto ei kuulu versionhallintaan.
 */
import { pbkdf2Sync, randomBytes } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const ITERATIONS = 25000;

function hash(password) {
  const salt = randomBytes(16);
  const dk = pbkdf2Sync(password, salt, ITERATIONS, 32, "sha256");
  return `pbkdf2$${ITERATIONS}$${salt.toString("base64")}$${dk.toString("base64")}`;
}

function sqlStr(s) {
  return "'" + String(s).replace(/'/g, "''") + "'";
}

const conf = JSON.parse(readFileSync("seed.json", "utf8"));
const rivit = [];

rivit.push("-- Luotu scripts/seed.mjs:lla. Ala lisaa versionhallintaan.");
rivit.push("");

if (conf.gate) {
  const token = randomBytes(32).toString("hex");
  rivit.push("-- Yhteinen sisaankaynti.");
  for (const [key, value] of [
    ["gate_username", conf.gate.username],
    ["gate_password", hash(conf.gate.password)],
    ["gate_token", token],
  ]) {
    rivit.push(
      `INSERT INTO settings (key, value) VALUES (${sqlStr(key)}, ${sqlStr(value)})\n` +
        `  ON CONFLICT(key) DO UPDATE SET value = excluded.value;`
    );
  }
  rivit.push("");
}

for (const u of conf.users ?? []) {
  rivit.push(`-- ${u.username} (${u.role})`);
  rivit.push(
    `INSERT INTO users (username, password_hash, role, character_name)\n` +
      `  VALUES (${sqlStr(u.username)}, ${sqlStr(hash(u.password))}, ${sqlStr(u.role)}, ${sqlStr(u.character_name ?? u.username)})\n` +
      `  ON CONFLICT(username) DO UPDATE SET\n` +
      `    password_hash = excluded.password_hash,\n` +
      `    role          = excluded.role;`
  );
  rivit.push("");
}

writeFileSync("seed.sql", rivit.join("\n"), "utf8");
console.log(`seed.sql kirjoitettu (${conf.users?.length ?? 0} kayttajaa).`);
