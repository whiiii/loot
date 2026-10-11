-- Siirtyma versioon 6: suojattu yllapitotunnus.
--
-- Ajetaan kerran olemassa olevaan kantaan. Uudet asennukset saavat saman
-- sarakkeen suoraan schema.sql:sta.
--
-- Suojaus on oma sarakkeensa eika uusi rooli, koska role-sarakkeessa on
-- CHECK-rajoite johon 'admin' ei mahdu. Rajoitteen purkaminen vaatisi koko
-- users-taulun uudelleenrakentamisen viiteavaimineen, ja se olisi
-- kohtuuton riski asialle joka hoituu yhdella lipulla. Rajoite on myos
-- hyva olemassa.
--
-- Yllapitotunnus on siis officer jolla on protected = 1: se tarvitsee
-- officerin oikeudet, mutta siihen ei saa kohdistua yhtaan toimea.

ALTER TABLE users ADD COLUMN protected INTEGER NOT NULL DEFAULT 0;

-- Yllapitotunnus ei ole hahmo: ei luokkaa, ei raidiroolia, ei sukunimea.
UPDATE users
   SET protected      = 1,
       role           = 'officer',
       class          = NULL,
       raid_role      = NULL,
       last_name      = NULL,
       character_name = NULL,
       locked         = 0
 WHERE username = 'admin';

-- Mahdolliset aiemmat valinnat pois: suojattu tunnus ei osallistu raidiin
-- eika sen valintoja vieda addoniin.
DELETE FROM picks
 WHERE user_id IN (SELECT id FROM users WHERE protected = 1);

UPDATE settings SET value = '6' WHERE key = 'schema_version';
