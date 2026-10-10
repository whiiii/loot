-- Siirtyma versioon 4: hahmon luokka, raidirooli, etu- ja sukunimi seka
-- paikka omalle hahmokuvalle.
--
-- Ajetaan kerran olemassa olevaan kantaan. Uudet asennukset saavat samat
-- sarakkeet suoraan schema.sql:sta.
--
-- Huom: users.role on killan arvo (social/raider/officer) ja users.raid_role
-- on raidirooli (dps/tank/healer). Ne ovat eri asioita ja siksi eri
-- sarakkeita - yhteen kenttaan ahdettuna kumpikaan ei olisi kysyttavissa.

ALTER TABLE users ADD COLUMN raid_role  TEXT;
ALTER TABLE users ADD COLUMN first_name TEXT;
ALTER TABLE users ADD COLUMN last_name  TEXT;
ALTER TABLE users ADD COLUMN avatar_key TEXT;

-- Vanha yhden kentan hahmonimi siirretaan etunimeksi, jottei mikaan katoa.
UPDATE users
   SET first_name = character_name
 WHERE first_name IS NULL AND character_name IS NOT NULL;

UPDATE settings SET value = '4' WHERE key = 'schema_version';
