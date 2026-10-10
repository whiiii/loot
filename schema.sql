-- Loot — tietokantarakenne.
--
-- Tassa vaiheessa vain meta-taulu, jolla todistetaan etta migraatio ajautuu
-- ja Worker saa yhteyden kantaan. Varsinaiset taulut lisataan vasta kun
-- putki on todettu toimivaksi.

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO meta (key, value) VALUES ('schema_version', '1')
  ON CONFLICT(key) DO UPDATE SET value = excluded.value;
