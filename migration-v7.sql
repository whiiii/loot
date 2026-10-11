-- Migration to version 7: import logs.
--
-- Run once against an existing database. New installations get the same
-- tables straight from schema.sql.
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

  -- What the addon reported about the evening.
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

-- Renamed to idx_import_time in version 8.
CREATE INDEX IF NOT EXISTS idx_import_aika ON loot_import(imported_at DESC);

-- Which import the row came from. Old rows stay empty: they were not
-- recorded into any log.
ALTER TABLE loot_history ADD COLUMN import_id INTEGER REFERENCES loot_import(id);
ALTER TABLE loot_history ADD COLUMN zone      TEXT;

CREATE INDEX IF NOT EXISTS idx_loot_import ON loot_history(import_id);

UPDATE settings SET value = '7' WHERE key = 'schema_version';
