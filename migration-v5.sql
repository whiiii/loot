-- Migration to version 5: the reason for the award and the roll, into the
-- loot history.
--
-- Run once against an existing database. New installations get the same
-- columns straight from schema.sql.
--
-- The addon already sends two extra fields in its export (the roll and the
-- response button's code), but without these columns they are dropped on
-- import. Old rows stay empty: their reason is not stored anywhere.

ALTER TABLE loot_history ADD COLUMN response TEXT;
ALTER TABLE loot_history ADD COLUMN roll     INTEGER;

UPDATE settings SET value = '5' WHERE key = 'schema_version';
