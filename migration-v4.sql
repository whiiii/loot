-- Migration to version 4: the character's class, raid role, first and last
-- name, and a place for an own character picture.
--
-- Run once against an existing database. New installations get the same
-- columns straight from schema.sql.
--
-- Note: users.role is the guild rank (social/raider/officer) and
-- users.raid_role is the raid role (dps/tank/healer). They are different
-- things and therefore different columns — crammed into one field, neither
-- would be answerable.

ALTER TABLE users ADD COLUMN raid_role  TEXT;
ALTER TABLE users ADD COLUMN first_name TEXT;
ALTER TABLE users ADD COLUMN last_name  TEXT;
ALTER TABLE users ADD COLUMN avatar_key TEXT;

-- The old single-field character name moves into the first name, so that
-- nothing is lost.
UPDATE users
   SET first_name = character_name
 WHERE first_name IS NULL AND character_name IS NOT NULL;

UPDATE settings SET value = '4' WHERE key = 'schema_version';
