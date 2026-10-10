-- Siirtyma versioon 5: jaon peruste ja arvonta loottihistoriaan.
--
-- Ajetaan kerran olemassa olevaan kantaan. Uudet asennukset saavat samat
-- sarakkeet suoraan schema.sql:sta.
--
-- Addon lahettaa viennissa jo kaksi kenttaa lisaa (roll ja vastausnapin
-- koodi), mutta ilman naita sarakkeita ne putoavat tuonnissa pois. Vanhat
-- rivit jaavat tyhjiksi: niiden perustetta ei ole missaan tallessa.

ALTER TABLE loot_history ADD COLUMN response TEXT;
ALTER TABLE loot_history ADD COLUMN roll     INTEGER;

UPDATE settings SET value = '5' WHERE key = 'schema_version';
