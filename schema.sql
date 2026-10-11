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
--
-- Yllapitotunnus on officer jolla on protected = 1. Se ei ole oma roolinsa
-- vaan ominaisuus: tunnus tarvitsee officerin oikeudet, mutta siihen ei saa
-- kohdistua yhtaan toimea.
CREATE TABLE IF NOT EXISTS users (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  username       TEXT NOT NULL COLLATE NOCASE UNIQUE,
  password_hash  TEXT NOT NULL,

  -- Killan arvo. Eri asia kuin raid_role, joka on rooli raidissa.
  role           TEXT NOT NULL DEFAULT 'raider',

  character_name TEXT,
  first_name     TEXT,
  last_name      TEXT,
  class          TEXT,
  raid_role      TEXT,

  -- Viite omaan hahmokuvaan. Tyhja tarkoittaa oletuskuvaa, joten erillista
  -- "onko oma kuva" -tilaa ei tarvita.
  avatar_key     TEXT,

  -- Lukittu profiili: valinnat on tehty eika niita voi muuttaa ennen kuin
  -- officer avaa lukon.
  locked         INTEGER NOT NULL DEFAULT 0,

  -- Suojattu tunnus: sivuston varauloskaynti. Silla paasee sisaan
  -- silloinkin kun officer-oikeudet ovat jostain syysta kadonneet, joten
  -- siihen ei saa kohdistua yhtaan toimea - ei roolin vaihtoa, lukitusta,
  -- poistoa eika hahmotietojen muokkausta. Asetetaan kasin SQL:lla, koska
  -- rajapinnan kautta annettava suojaus ei olisi suojaus.
  protected      INTEGER NOT NULL DEFAULT 0,

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

  -- Mista tuonnista rivi tuli ja missa instanssissa se jaettiin. Viikossa
  -- voi olla useita raideja, joten rivi ilman lokia on irrallinen tieto.
  import_id  INTEGER REFERENCES loot_import(id),
  zone       TEXT,

  -- Milla perusteella item annettiin: prio, main, off, muu. Addonin
  -- vastausnapin koodi sellaisenaan. "Kuka sai ja milla napilla" on se mita
  -- historiasta jalkikateen kysytaan, joten numeron rinnalla talletetaan
  -- myos peruste.
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


-- Tuontilokit.
--
-- Viikossa voi olla useita raideja eri kokoonpanoilla: yksi 40-man ja pari
-- 20-man. Jokainen on oma iltansa ja oma lootmasterinsa, joten jokainen
-- tuonti on oma lokinsa eika yksi yhteinen kasa.
--
-- raw_text tallettaa addonin tekstin sellaisenaan. Se on varmuuskopio: jos
-- tuonti menee vikaan tai rivi katoaa, alkuperainen on tallessa eika sita
-- tarvitse pyytaa lootmasterilta uudelleen.
CREATE TABLE IF NOT EXISTS loot_import (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Officerin antama nimi, esim. "MC 40 ke". Vapaaehtoinen: ilman sita
  -- lista nayttaa instanssin ja koon.
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
CREATE INDEX IF NOT EXISTS idx_import_aika ON loot_import(imported_at DESC);


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


-- Itemien nimet, ikonit ja tooltipit.
--
-- Tama on valimuisti, ei totuus. Tiedot haetaan Wowheadilta kerran item-id:ta
-- kohden ja sailotaan, jottei jokainen sivulataus kuormita ulkopuolista
-- palvelua - ja jotta sivusto toimii silloinkin kun se on alhaalla.
--
-- Aiemmin nama haettiin selaimessa Wowheadin omalla skriptilla. Se on
-- hauraampi kuin nayttaa: skripti paattaa itse mita linkkeja se kasittelee,
-- ja jos se ei tunnista osoitemuotoa, mitaan ei tapahdu eika mitaan kerrota.
CREATE TABLE IF NOT EXISTS item_cache (
  item_id    INTEGER PRIMARY KEY,
  name       TEXT,
  quality    INTEGER,
  icon       TEXT,
  tooltip    TEXT,
  fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
);


INSERT INTO settings (key, value) VALUES ('schema_version', '7')
  ON CONFLICT(key) DO UPDATE SET value = excluded.value;
