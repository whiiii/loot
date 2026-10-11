-- Siirtyma versioon 7: tuontilokit.
--
-- Ajetaan kerran olemassa olevaan kantaan. Uudet asennukset saavat samat
-- taulut suoraan schema.sql:sta.
--
-- Viikossa voi olla useita raideja eri kokoonpanoilla: yksi 40-man ja pari
-- 20-man. Jokainen on oma iltansa ja oma lootmasterinsa, joten jokainen
-- tuonti on oma lokinsa eika yksi yhteinen kasa.
--
-- raw_text tallettaa addonin tekstin sellaisenaan. Se on varmuuskopio:
-- jos tuonti menee vikaan tai rivi katoaa, alkuperainen on tallessa eika
-- sita tarvitse pyytaa lootmasterilta uudelleen.

CREATE TABLE IF NOT EXISTS loot_import (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Officerin antama nimi, esim. "MC 40 ke". Vapaaehtoinen: jos sita ei
  -- anneta, lista nayttaa instanssin ja koon.
  label        TEXT,

  -- Addonin kertomat tiedot illasta.
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

CREATE INDEX IF NOT EXISTS idx_import_aika ON loot_import(imported_at DESC);

-- Mista tuonnista rivi tuli. Vanhat rivit jaavat tyhjiksi: niita ei ole
-- kirjattu mihinkaan lokiin.
ALTER TABLE loot_history ADD COLUMN import_id INTEGER REFERENCES loot_import(id);
ALTER TABLE loot_history ADD COLUMN zone      TEXT;

CREATE INDEX IF NOT EXISTS idx_loot_import ON loot_history(import_id);

UPDATE settings SET value = '7' WHERE key = 'schema_version';
