# LootPrio — addon

Lukee killan sivustolta viedyt loottiprofiilit, kerää raidilaisten
vastaukset jaettavista itemeistä ja näyttää lootmasterille kaikki
yhdessä listassa.

## Asennus

Kopioi kansio `LootPrio` pelin addon-kansioon:

```
World of Warcraft\_classic_era_\Interface\AddOns\LootPrio
```

Kansion sisällä pitää olla `LootPrio.toc` ja lua-tiedostot suoraan — ei
yhtä ylimääräistä kansiotasoa.

Käynnistä peli uudelleen tai kirjoita `/reload`.

Jos addon ei näy listassa, laita hahmovalinnassa **AddOns → Load out of
date AddOns** päälle. `.toc`-tiedoston `## Interface` -numero on arvaus, ja
se kannattaa päivittää vastaamaan omaa asiakasversiota.

## Käyttö

Kaikki löytyy **minimap-napista** avautuvasta ikkunasta. Komennot ovat
oikotie, eivät ainoa tie.

**Tuonti.** Ikkunan Tuonti-välilehti: liitä sivuston *Vienti addoniin*
-teksti ja paina Tuo. Tuonti korvaa aiemmat profiilit kokonaan.

**Raidissa.** Kun loottiruutu aukeaa, lootmaster avaa jaon ja jokaisen
raidilaisen ruudulle tulee vastausikkuna: **LootPrio, Main spec, Off spec,
Muu** tai **Pass**. Vastaukset kertyvät lootmasterin listaan vahvimmasta
perusteesta alkaen, ja rivin Assign-nappi antaa lootin.

Kaikki itemit menevät jakoon, eivät vain profiileissa olevat — profiili on
yksi peruste neljästä, ei pääsyvaatimus.

**LootPrio-nappi on käytössä vain jos item on oikeasti omassa
profiilissa.** Lootmaster näkee lisäksi merkinnän, jos joku väittää priota
ilman että se näkyy tuoduissa profiileissa.

**Historia.** Jaetut itemit kirjautuvat Historia-välilehdelle. Luo vienti
ja liitä teksti sivuston ylläpitoon, niin saadut itemit saavat profiiliin
vihreän merkin.

**Testi.** Asetukset → *Käynnistä testi* tekee kolme kuviteltua loottia ja
arpoo niille vastaukset. Mitään ei anneta kenellekään eikä pelin loottiin
kosketa.

## Komennot

| Komento | Tekee |
|---|---|
| `/lp` | avaa ikkunan |
| `/lp loot` | avaa jakonäkymän |
| `/lp tuo` | avaa tuonnin |
| `/lp jasenet` | avaa jäsenlistan |
| `/lp historia` | avaa historian |

## Mitä addon ei voi tehdä

**Hakea tietoja verkosta.** Peli ei anna addonille mitään yhteyttä
ulospäin, joten profiilit on tuotava liittämällä ja historia vietävä
samalla tavalla takaisin.

**Pakottaa muita vastaamaan.** Vastausikkuna aukeaa vain niille joilla on
addon. Lootmaster näkee listassa myös ketkä eivät ole vastanneet, joten
puuttuva vastaus erottuu hiljaisuudesta.

**Luottaa vastaukseen sokeasti.** Vastaus tulee pelaajan omalta koneelta.
Siksi lootmasterin addon tarkistaa prio-väitteen omia profiilitietojaan
vasten ja merkitsee sen jos se ei täsmää.

**Rajata viestiä osalle raidia.** Raidikanava menee kaikille. Siksi
"vain officerit" tarkoittaa, ettei arvontoja lähetetä lainkaan.
