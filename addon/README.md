# LootPrio — addon

Lukee killan sivustolta viedyt loottiprofiilit ja nayttaa lootmasterille
kuka on varannut minkakin itemin.

## Asennus

Kopioi kansio `LootPrio` pelin addon-kansioon:

```
World of Warcraft\_classic_era_\Interface\AddOns\LootPrio
```

Kansion sisalla pitaa olla `LootPrio.toc` ja lua-tiedostot suoraan — ei
yhta ylimaaraista kansiotasoa.

Kaynnista peli uudelleen tai kirjoita `/reload`.

Jos addon ei nay listassa, laita hahmovalinnassa **AddOns → Load out of
date AddOns** paalle. `.toc`-tiedoston `## Interface` -numero on arvaus, ja
se kannattaa paivittaa vastaamaan omaa asiakasversiota.

## Kaytto

**Tuonti.** Kirjoita `/lp tuo`, liita sivuston Vienti addoniin -kentasta
kopioitu teksti ja paina Tuo. Tuonti korvaa aiemmat profiilit kokonaan.

**Raidissa.** Kun loottiruutu aukeaa ja jokin item on jonkun profiilissa,
ikkuna aukeaa itsestaan lootmasterille. Jokaiselle halukkaalle on arvottu
luku 1-100, ja rivin Assign-nappi antaa lootin.

**Arvontojen nakyvyys.** Ikkunan alareunan valinta ratkaisee, lahetetaanko
numerot koko raidille vai jaavatko ne officereille. Saman saa komennolla
`/lp rollit raid` tai `/lp rollit officers`.

## Komennot

| Komento | Tekee |
|---|---|
| `/lp tuo` | avaa tuonti-ikkunan |
| `/lp lista` | listaa tuodut profiilit |
| `/lp loot` | avaa loottilistan uudelleen |
| `/lp rollit raid\|officers` | kuka nakee arvonnat |
| `/lp tyhjenna` | poistaa tuodut profiilit |

## Mita addon ei voi tehda

**Hakea tietoja verkosta.** Peli ei anna addonille mitaan yhteytta
ulospain, joten profiilit on tuotava liittamalla. Sama koskee toiseen
suuntaan: loottihistoriaa ei voi lahettaa sivustolle automaattisesti.

**Arpoa pelin omalla nopalla.** `/roll` naytetaan chatissa mutta sen
tulosta ei saa luettavaksi luotettavasti kaikilta. Siksi addon arpoo itse
lootmasterin koneella ja lahettaa tuloksen muille — kaikki nakevat samat
numerot, mutta luottamus on lootmasterin asiakasohjelmassa.

**Rajata viestia osalle raidia.** Raidikanava menee kaikille. Siksi
"vain officerit" tarkoittaa, ettei numeroita laheteta lainkaan: officerit
nakevat ne omasta ikkunastaan, koska he ajavat samaa addonia.
