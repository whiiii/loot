-- Loot — tietokantarakenne.
--
-- D1 on SQLite. Aikaleimat ovat tekstia muodossa 'YYYY-MM-DD HH:MM:SS' UTC,
-- koska SQLitessa ei ole omaa aikatyyppia ja teksti jarjestyy oikein.
--
-- Vain item-id:t tallennetaan. Nimet, ikonit ja statsit haetaan
-- esitysvaiheessa, jottei kannassa ole kopiota pelin datasta vanhenemassa.

-- Versio 1 oli pelkka meta-taulu, jolla todistettiin putki toimivaksi.
DROP TABLE IF EXISTS meta;


-- Sivuston asetukset. Tassa elaa mm. yhteisen sisaankaynnin salasanan
-- tiiviste, jotta sen voi vaihtaa ilman uutta julkaisua.
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);


-- Kayttajat.
--
-- Rooli on jarjestetty: social < raider < officer. Oikeudet luetaan
-- roolista jokaisella pyynnolla, ei kirjautumishetkella tallennetusta
-- tiedosta - niin roolin muutos astuu voimaan heti eika selain voi
-- vaittaa olevansa officer.
CREATE TABLE IF NOT EXISTS users (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  username       TEXT NOT NULL COLLATE NOCASE UNIQUE,
  password_hash  TEXT NOT NULL,
  role           TEXT NOT NULL DEFAULT 'raider',
  character_name TEXT,
  class          TEXT,

  -- Lukittu profiili: valinnat on tehty eika niita voi muuttaa ennen kuin
  -- officer avaa lukon.
  locked         INTEGER NOT NULL DEFAULT 0,

  created_at     TEXT NOT NULL DEFAULT (datetime('now')),
  last_login_at  TEXT,

  CHECK (role IN ('social', 'raider', 'officer'))
);


-- Istunnot. Tunnus elaa httpOnly-evasteessa, eika sita kirjoiteta
-- selaimen muistiin missaan vaiheessa.
CREATE TABLE IF NOT EXISTS sessions (
  token      TEXT PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);


-- Raidit. Kerrallaan yksi on aktiivinen, ja profiilit tehdaan siihen.
CREATE TABLE IF NOT EXISTS raids (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  is_active  INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


-- Raidista tippuvat itemit.
--
-- slot on hahmoikkunan slotti. Sormuksia ja koruja on kaksi, mutta item
-- itse tietaa vain olevansa sormus - kumpaan paikkaan se valitaan,
-- ratkaistaan vasta valinnassa.
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


-- Raiderin valinnat: yksi item per paikka.
--
-- slot_key on paikka hahmoikkunassa, ei itemin slotti - siksi 'finger1' ja
-- 'finger2' ovat eri avaimia vaikka molempiin kelpaa sormus. Perusavain
-- takaa ettei samaan paikkaan voi tulla kahta valintaa.
CREATE TABLE IF NOT EXISTS picks (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  raid_id    INTEGER NOT NULL REFERENCES raids(id) ON DELETE CASCADE,
  slot_key   TEXT NOT NULL,
  item_id    INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),

  PRIMARY KEY (user_id, raid_id, slot_key)
);

-- Lootmasterin tarkein kysely: kuka on varannut taman itemin.
CREATE INDEX IF NOT EXISTS idx_picks_item ON picks(raid_id, item_id);


-- Jaettu loot.
--
-- winner on hahmon nimi pelista. user_id yhdistetaan siihen jos tunnus
-- loytyy, mutta se saa jaada tyhjaksi - historia ei saa kadota siksi etta
-- pelaaja on poistunut killasta.
--
-- UNIQUE tekee tuonnista idempotentin: saman viennin voi tuoda kahdesti
-- ilman etta rivit kahdentuvat. Se on olennaista, koska tuonti on kasityota
-- ja kasityo toistetaan.
CREATE TABLE IF NOT EXISTS loot_history (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  raid_id    INTEGER REFERENCES raids(id) ON DELETE SET NULL,
  item_id    INTEGER NOT NULL,
  winner     TEXT NOT NULL COLLATE NOCASE,
  user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  boss       TEXT,
  awarded_at TEXT NOT NULL,
  awarded_by TEXT,
  imported_at TEXT NOT NULL DEFAULT (datetime('now')),

  UNIQUE (item_id, winner, awarded_at)
);
CREATE INDEX IF NOT EXISTS idx_loot_user ON loot_history(user_id);
CREATE INDEX IF NOT EXISTS idx_loot_raid ON loot_history(raid_id);


-- Officerin toimet jaavat nakyviin.
--
-- Roolin muutos, lukon avaus ja salasanan vaihto ovat juuri niita asioita
-- joista myohemmin kysytaan "kuka teki ja milloin".
CREATE TABLE IF NOT EXISTS audit_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  actor      TEXT NOT NULL,
  action     TEXT NOT NULL,
  target     TEXT,
  details    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);


INSERT INTO settings (key, value) VALUES ('schema_version', '2')
  ON CONFLICT(key) DO UPDATE SET value = excluded.value;
