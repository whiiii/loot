-- Loot — the database structure.
--
-- D1 is SQLite. Timestamps are text in the form 'YYYY-MM-DD HH:MM:SS' UTC,
-- because SQLite has no time type of its own and text sorts correctly.
--
-- Only item ids are stored. Names, icons and stats are fetched at display
-- time, so the database holds no copy of the game's data going stale.

-- Version 1 was a bare meta table, used to prove the pipeline worked.
DROP TABLE IF EXISTS meta;


-- Site settings. Among other things the shared entrance password's hash
-- lives here, so it can be changed without a new deploy.
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);


-- Users.
--
-- The role is ordered: social < raider < officer. Permissions are read
-- from the role on every request, not from something stored at login
-- time — so a role change takes effect at once and the browser cannot
-- claim to be an officer.
--
-- The admin account is an officer with protected = 1. It is not a role of
-- its own but a property: the account needs an officer's permissions, but
-- no action may be aimed at it.
CREATE TABLE IF NOT EXISTS users (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  username       TEXT NOT NULL COLLATE NOCASE UNIQUE,
  password_hash  TEXT NOT NULL,

  -- The guild rank. A different thing from raid_role, which is the role
  -- in a raid.
  role           TEXT NOT NULL DEFAULT 'raider',

  character_name TEXT,
  first_name     TEXT,
  last_name      TEXT,
  class          TEXT,
  raid_role      TEXT,

  -- A reference to the character's own picture. Empty means the default
  -- picture, so no separate "has an own picture" state is needed.
  avatar_key     TEXT,

  -- A locked profile: the picks are made and cannot be changed until an
  -- officer opens the lock.
  locked         INTEGER NOT NULL DEFAULT 0,

  -- A protected account: the site's emergency exit. It gets in even when
  -- officer permissions have gone missing for some reason, so no action
  -- may be aimed at it — no role change, no lock, no deletion and no
  -- editing of character details. Set by hand in SQL, because protection
  -- handed out through the API would not be protection.
  protected      INTEGER NOT NULL DEFAULT 0,

  created_at     TEXT NOT NULL DEFAULT (datetime('now')),
  last_login_at  TEXT,

  CHECK (role IN ('social', 'raider', 'officer'))
);


-- Sessions. The token lives in an httpOnly cookie and is never written
-- into the browser's memory at any point.
CREATE TABLE IF NOT EXISTS sessions (
  token      TEXT PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);


-- Raids. One is active at a time, and profiles are made for it.
CREATE TABLE IF NOT EXISTS raids (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  is_active  INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


-- The items the raid drops.
--
-- slot is the character window's slot. There are two rings and two
-- trinkets, but the item itself only knows it is a ring — which position
-- it is picked into is decided at pick time.
CREATE TABLE IF NOT EXISTS items (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  raid_id    INTEGER NOT NULL REFERENCES raids(id) ON DELETE CASCADE,
  item_id    INTEGER NOT NULL,
  boss       TEXT,
  slot       TEXT NOT NULL,
  armor_type TEXT,

  UNIQUE (raid_id, item_id),
  CHECK (slot IN (
    'head', 'neck', 'shoulder', 'back', 'chest', 'wrist', 'hands',
    'waist', 'legs', 'feet', 'finger', 'trinket',
    'mainhand', 'offhand', 'ranged'
  ))
);
CREATE INDEX IF NOT EXISTS idx_items_raid_slot ON items(raid_id, slot);


-- A raider's picks: one item per position.
--
-- slot_key is the position in the character window, not the item's slot —
-- which is why 'finger1' and 'finger2' are different keys even though a
-- ring fits both. The primary key makes sure one position cannot get two
-- picks.
CREATE TABLE IF NOT EXISTS picks (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  raid_id    INTEGER NOT NULL REFERENCES raids(id) ON DELETE CASCADE,
  slot_key   TEXT NOT NULL,
  item_id    INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),

  PRIMARY KEY (user_id, raid_id, slot_key)
);

-- The lootmaster's most important query: who reserved this item.
CREATE INDEX IF NOT EXISTS idx_picks_item ON picks(raid_id, item_id);


-- Awarded loot.
--
-- winner is the character's name from the game. user_id is matched to it
-- if the account is found, but it may stay empty — history must not
-- disappear because a player left the guild.
--
-- UNIQUE makes importing idempotent: the same export can be imported
-- twice without the rows doubling. That matters, because importing is
-- manual work and manual work gets repeated.
CREATE TABLE IF NOT EXISTS loot_history (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  raid_id    INTEGER REFERENCES raids(id) ON DELETE SET NULL,
  item_id    INTEGER NOT NULL,
  winner     TEXT NOT NULL COLLATE NOCASE,
  user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  boss       TEXT,

  -- Which import the row came from and which instance it was awarded in.
  -- A week can hold several raids, so a row without a log is a loose
  -- fact.
  import_id  INTEGER REFERENCES loot_import(id),
  zone       TEXT,

  -- On what grounds the item was given: prio, main, off, muu. The addon's
  -- response button code as it is. "Who got it and on which button" is
  -- what gets asked of the history afterwards, so the reason is stored
  -- alongside the number.
  response   TEXT,
  roll       INTEGER,

  awarded_at TEXT NOT NULL,
  awarded_by TEXT,
  imported_at TEXT NOT NULL DEFAULT (datetime('now')),

  UNIQUE (item_id, winner, awarded_at)
);
CREATE INDEX IF NOT EXISTS idx_loot_user ON loot_history(user_id);
CREATE INDEX IF NOT EXISTS idx_loot_raid ON loot_history(raid_id);
CREATE INDEX IF NOT EXISTS idx_loot_import ON loot_history(import_id);


-- Import logs.
--
-- A week can hold several raids with different line-ups: one 40-man and a
-- couple of 20-mans. Each is its own evening with its own lootmaster, so
-- each import is its own log rather than one shared heap.
--
-- raw_text keeps the addon's text as it is. It is a backup: if an import
-- goes wrong or a row disappears, the original is still there and does not
-- have to be asked of the lootmaster again.
CREATE TABLE IF NOT EXISTS loot_import (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,

  -- The name an officer gave, e.g. "MC 40 ke". Optional: without it the
  -- list shows the instance and the size.
  label        TEXT,

  zone         TEXT,
  raid_size    INTEGER,
  source_raid  TEXT,
  source_time  TEXT,

  imported_by  TEXT NOT NULL,
  imported_at  TEXT NOT NULL DEFAULT (datetime('now')),

  rows_total   INTEGER NOT NULL DEFAULT 0,
  rows_new     INTEGER NOT NULL DEFAULT 0,
  rows_skipped INTEGER NOT NULL DEFAULT 0,

  raw_text     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_import_time ON loot_import(imported_at DESC);


-- An officer's acts stay visible.
--
-- A role change, an opened lock and a changed password are exactly the
-- things that later get asked "who did this and when".
CREATE TABLE IF NOT EXISTS audit_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  actor      TEXT NOT NULL,
  action     TEXT NOT NULL,
  target     TEXT,
  details    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);


-- Item names, icons and tooltips.
--
-- This is a cache, not the truth. The details are fetched from Wowhead
-- once per item id and kept, so every page load does not load an outside
-- service — and so the site works even when that service is down.
--
-- These used to be fetched in the browser with Wowhead's own script. That
-- is more fragile than it looks: the script decides for itself which links
-- it handles, and if it does not recognise an address format, nothing
-- happens and nothing is said.
CREATE TABLE IF NOT EXISTS item_cache (
  item_id    INTEGER PRIMARY KEY,
  name       TEXT,
  quality    INTEGER,
  icon       TEXT,
  tooltip    TEXT,
  fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
);


INSERT INTO settings (key, value) VALUES ('schema_version', '8')
  ON CONFLICT(key) DO UPDATE SET value = excluded.value;
