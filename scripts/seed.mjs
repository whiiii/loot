/**
 * Builds an SQL file for the first accounts.
 *
 * Passwords are hashed here rather than in the database, because the
 * Worker's CPU time is not worth spending on one-off work. Node produces
 * exactly the same hash as the browser's Web Crypto, as long as the
 * parameters match — PBKDF2, SHA-256, 25000 rounds, a 16-byte salt and a
 * 32-byte result.
 *
 * Usage:
 *   node scripts/seed.mjs            (reads seed.json, writes seed.sql)
 *
 * Neither file belongs in version control.
 */
import { pbkdf2Sync, randomBytes } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const ITERATIONS = 25000;

function hash(password) {
  const salt = randomBytes(16);
  const dk = pbkdf2Sync(password, salt, ITERATIONS, 32, "sha256");
  return `pbkdf2$${ITERATIONS}$${salt.toString("base64")}$${dk.toString("base64")}`;
}

function sqlString(s) {
  return "'" + String(s).replace(/'/g, "''") + "'";
}

const config = JSON.parse(readFileSync("seed.json", "utf8"));
const lines = [];

lines.push("-- Written by scripts/seed.mjs. Do not add to version control.");
lines.push("");

if (config.gate) {
  const token = randomBytes(32).toString("hex");
  lines.push("-- The shared entrance.");
  for (const [key, value] of [
    ["gate_username", config.gate.username],
    ["gate_password", hash(config.gate.password)],
    ["gate_token", token],
  ]) {
    lines.push(
      `INSERT INTO settings (key, value) VALUES (${sqlString(key)}, ${sqlString(value)})\n` +
        `  ON CONFLICT(key) DO UPDATE SET value = excluded.value;`
    );
  }
  lines.push("");
}

for (const u of config.users ?? []) {
  lines.push(`-- ${u.username} (${u.role})`);
  lines.push(
    `INSERT INTO users (username, password_hash, role, character_name)\n` +
      `  VALUES (${sqlString(u.username)}, ${sqlString(hash(u.password))}, ${sqlString(u.role)}, ${sqlString(u.character_name ?? u.username)})\n` +
      `  ON CONFLICT(username) DO UPDATE SET\n` +
      `    password_hash = excluded.password_hash,\n` +
      `    role          = excluded.role;`
  );
  lines.push("");
}

writeFileSync("seed.sql", lines.join("\n"), "utf8");
console.log(`seed.sql written (${config.users?.length ?? 0} users).`);
