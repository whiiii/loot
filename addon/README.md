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
raidilaisen ikkuna aukeaa samaan näkymään. Itemit ovat välilehtinä, ja
jokaisen kohdalla vastataan yhdellä napilla: **LootPrio, Main spec, Off
spec, Muu** tai **Pass**.

Vastaukset lähetetään raidille, joten **jokainen näkee mitä muut
vastasivat** — vastaus, arvonta, pelaaja ja montako loottia hän on jo
saanut. Lista on järjestetty vahvimmasta perusteesta alkaen, ja
lootmasterilla on jokaisella rivillä Assign-nappi.

Kaikki itemit menevät jakoon, eivät vain profiileissa olevat — profiili on
yksi peruste neljästä, ei pääsyvaatimus.

**LootPrio-nappi on käytössä vain jos item on oikeasti omassa
profiilissa.** Jos joku silti väittää priota, rivi merkitään punaisella
huutomerkillä kaikille joilla profiilit on tuotuna.

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

**Pakottaa muita vastaamaan.** Ikkuna aukeaa vain niille joilla on addon.
Lista näyttää myös ketkä eivät ole vastanneet, joten puuttuva vastaus
erottuu hiljaisuudesta.

**Luottaa vastaukseen sokeasti.** Vastaus tulee pelaajan omalta koneelta.
Siksi prio-väite tarkistetaan jokaisella koneella tuotuja profiileja
vasten ja merkitään jos se ei täsmää.

**Pitää vastauksia salassa.** Raidikanava menee kaikille, joten tiedot
ovat jokaisen koneella riippumatta asetuksesta. "Vain officerit" on
näkyvyysvalinta, ei salaisuus - muokattu addon näkisi ne silti.
