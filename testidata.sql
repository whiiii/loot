-- Testidataa hahmoikkunan kehittamiseen.
--
-- HUOM: nama item-id:t ovat muistinvaraisia eika niita ole tarkistettu
-- mistaan lahteesta. Osa voi osoittaa vaaraan itemiin. Tarkoitus on vain
-- saada ruudulle jotain klikattavaa - oikea lista tuodaan officerin
-- tuontityokalulla, ja silloin tama rivi poistetaan.
--
-- Tarkistus on helppo: vie hiiri itemin paalle sivustolla. Jos Wowheadin
-- tooltipissa lukee eri item kuin boss-sarakkeessa odotetaan, id on vaara.

INSERT INTO raids (name, is_active) VALUES ('Molten Core', 1);

INSERT INTO items (raid_id, item_id, boss, slot, armor_type) VALUES
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18812, 'Ragnaros',      'head',     NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18814, 'Ragnaros',      'neck',     NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18816, 'Ragnaros',      'mainhand', NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18817, 'Ragnaros',      'mainhand', NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 17076, 'Ragnaros',      'mainhand', NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 17063, 'Ragnaros',      'finger',   NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18820, 'Ragnaros',      'trinket',  NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 17204, 'Ragnaros',      'trinket',  NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18563, 'Garr',          'finger',   NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 18564, 'Baron Geddon',  'finger',   NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 17069, 'Magmadar',      'ranged',   NULL),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 16865, 'Golemagg',      'head',     'plate'),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 16861, 'Lucifron',      'chest',    'plate'),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 16795, 'Lucifron',      'head',     'cloth'),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 16800, 'Gehennas',      'shoulder', 'cloth'),
  ((SELECT id FROM raids WHERE name = 'Molten Core'), 16908, 'Shazzrah',      'legs',     'leather');
