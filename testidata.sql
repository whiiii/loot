-- Testidataa hahmoikkunan kehittamiseen.
--
-- Jokainen item-id on tarkistettu Wowheadilta: nimi ja slotti vastaavat
-- sita mika tahan on kirjattu. Boss-sarake on jatetty tyhjaksi, koska sita
-- ei ole tarkistettu - tyhja kentta on parempi kuin vaara tieto.
--
-- Raidin nimi on 'Testidata' eika minkaan oikean raidin nimi: mukana on
-- itemeita useasta Classic-raidista, jotta jokaiseen paikkaan on jotain
-- valittavaa. Oikeat raidit tuodaan officerin tuontityokalulla.
--
-- Rivit kirjoitetaan tavallisena VALUES-listana. Aiempi versio kokosi ne
-- UNION ALL -ketjuksi, ja D1 torjui sen: yhdistetyssa SELECTissa saa olla
-- vain rajallinen maara osia.

DELETE FROM picks;
DELETE FROM items;
DELETE FROM raids;

INSERT INTO raids (name, is_active) VALUES ('Testidata (Classic)', 1);

INSERT INTO items (raid_id, item_id, boss, slot, armor_type) VALUES
  ((SELECT id FROM raids LIMIT 1), 18817, NULL, 'head',     NULL),
  ((SELECT id FROM raids LIMIT 1), 16795, NULL, 'head',     'cloth'),
  ((SELECT id FROM raids LIMIT 1), 16908, NULL, 'head',     'leather'),
  ((SELECT id FROM raids LIMIT 1), 19375, NULL, 'head',     'cloth'),
  ((SELECT id FROM raids LIMIT 1), 18814, NULL, 'neck',     NULL),
  ((SELECT id FROM raids LIMIT 1), 19371, NULL, 'neck',     NULL),
  ((SELECT id FROM raids LIMIT 1), 16868, NULL, 'shoulder', 'plate'),
  ((SELECT id FROM raids LIMIT 1), 19398, NULL, 'back',     NULL),
  ((SELECT id FROM raids LIMIT 1), 16865, NULL, 'chest',    'plate'),
  ((SELECT id FROM raids LIMIT 1), 16798, NULL, 'chest',    'cloth'),
  ((SELECT id FROM raids LIMIT 1), 18812, NULL, 'wrist',    NULL),
  ((SELECT id FROM raids LIMIT 1), 16861, NULL, 'wrist',    'plate'),
  ((SELECT id FROM raids LIMIT 1), 16911, NULL, 'wrist',    'leather'),
  ((SELECT id FROM raids LIMIT 1), 16799, NULL, 'wrist',    'cloth'),
  ((SELECT id FROM raids LIMIT 1), 16863, NULL, 'hands',    'plate'),
  ((SELECT id FROM raids LIMIT 1), 19143, NULL, 'hands',    NULL),
  ((SELECT id FROM raids LIMIT 1), 19137, NULL, 'waist',    'plate'),
  ((SELECT id FROM raids LIMIT 1), 16864, NULL, 'waist',    'plate'),
  ((SELECT id FROM raids LIMIT 1), 16867, NULL, 'legs',     'plate'),
  ((SELECT id FROM raids LIMIT 1), 16796, NULL, 'legs',     'cloth'),
  ((SELECT id FROM raids LIMIT 1), 16909, NULL, 'legs',     'leather'),
  ((SELECT id FROM raids LIMIT 1), 19402, NULL, 'legs',     'plate'),
  ((SELECT id FROM raids LIMIT 1), 16800, NULL, 'feet',     'cloth'),
  ((SELECT id FROM raids LIMIT 1), 19387, NULL, 'feet',     NULL),
  ((SELECT id FROM raids LIMIT 1), 19391, NULL, 'feet',     NULL),
  ((SELECT id FROM raids LIMIT 1), 17063, NULL, 'finger',   NULL),
  ((SELECT id FROM raids LIMIT 1), 19403, NULL, 'finger',   NULL),
  ((SELECT id FROM raids LIMIT 1), 18820, NULL, 'trinket',  NULL),
  ((SELECT id FROM raids LIMIT 1), 19379, NULL, 'trinket',  NULL),
  ((SELECT id FROM raids LIMIT 1), 19395, NULL, 'trinket',  NULL),
  ((SELECT id FROM raids LIMIT 1), 19406, NULL, 'trinket',  NULL),
  ((SELECT id FROM raids LIMIT 1), 18816, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 17076, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19346, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19360, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19364, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19356, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19353, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19351, NULL, 'mainhand', NULL),
  ((SELECT id FROM raids LIMIT 1), 19348, NULL, 'offhand',  NULL),
  ((SELECT id FROM raids LIMIT 1), 17069, NULL, 'ranged',   NULL),
  ((SELECT id FROM raids LIMIT 1), 19361, NULL, 'ranged',   NULL),
  ((SELECT id FROM raids LIMIT 1), 19367, NULL, 'ranged',   NULL),
  ((SELECT id FROM raids LIMIT 1), 19350, NULL, 'ranged',   NULL);
