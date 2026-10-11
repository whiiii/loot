-- Migration to version 8: English action codes in the action log.
--
-- Run once against an existing database. New installations write the new
-- codes from the start.
--
-- The code is a stored value, not a label, so renaming it in the source is
-- not enough: rows already in the log would keep the old code and show up
-- as raw text, and the action filter would never match them. That is the
-- recurring trap in this project — two truths, where the code and the
-- database each believe something different.
--
-- The site's own language stays Finnish. These codes are not shown as
-- they are: src/log.js and public/static/log.js translate each one into a
-- Finnish sentence for the reader.

UPDATE audit_log SET action = 'LOCK'             WHERE action = 'LUKITSE';
UPDATE audit_log SET action = 'UNLOCK'           WHERE action = 'AVAA_LUKKO';
UPDATE audit_log SET action = 'LOCK_OWN'         WHERE action = 'LUKITSE_OMA';
UPDATE audit_log SET action = 'CHANGE_ROLE'      WHERE action = 'VAIHDA_ROOLI';
UPDATE audit_log SET action = 'CHANGE_PASSWORD'  WHERE action = 'VAIHDA_SALASANA';
UPDATE audit_log SET action = 'CREATE_USER'      WHERE action = 'LUO_KAYTTAJA';
UPDATE audit_log SET action = 'DELETE_USER'      WHERE action = 'POISTA_KAYTTAJA';
UPDATE audit_log SET action = 'UPDATE_CHARACTER' WHERE action = 'PAIVITA_HAHMO';
UPDATE audit_log SET action = 'IMPORT_HISTORY'   WHERE action = 'TUO_HISTORIA';
UPDATE audit_log SET action = 'DELETE_IMPORT'    WHERE action = 'POISTA_TUONTI';
UPDATE audit_log SET action = 'DELETE_LOG'       WHERE action = 'POISTA_LOKI';

-- The index renamed along with the rest. DROP INDEX before CREATE, because
-- "CREATE INDEX IF NOT EXISTS" with a new name on the same columns would
-- leave both in place.
DROP INDEX IF EXISTS idx_import_aika;
CREATE INDEX IF NOT EXISTS idx_import_time ON loot_import(imported_at DESC);

UPDATE settings SET value = '8' WHERE key = 'schema_version';
