-- Migration to version 6: the protected admin account.
--
-- Run once against an existing database. New installations get the same
-- column straight from schema.sql.
--
-- The protection is a column of its own rather than a new role, because
-- the role column has a CHECK constraint that 'admin' does not fit.
-- Dropping the constraint would mean rebuilding the whole users table with
-- its foreign keys, and that would be an unreasonable risk for something
-- one flag handles. The constraint is also worth keeping.
--
-- The admin account is therefore an officer with protected = 1: it needs
-- an officer's permissions, but no action may be aimed at it.

ALTER TABLE users ADD COLUMN protected INTEGER NOT NULL DEFAULT 0;

-- The admin account is not a character: no class, no raid role, no last
-- name.
UPDATE users
   SET protected      = 1,
       role           = 'officer',
       class          = NULL,
       raid_role      = NULL,
       last_name      = NULL,
       character_name = NULL,
       locked         = 0
 WHERE username = 'admin';

-- Any earlier picks go: a protected account does not join a raid and its
-- picks are not exported to the addon.
DELETE FROM picks
 WHERE user_id IN (SELECT id FROM users WHERE protected = 1);

UPDATE settings SET value = '6' WHERE key = 'schema_version';
