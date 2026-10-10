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

## Raidissa

Jako kulkee laukkujen kautta, ei loottiruudun. Lootmaster kerää pudonneet
itemit ensin omiin laukkuihinsa ja laittaa ne sitten jakoon.

1. **Kerää lootit laukkuihin.** Addon ei lue loottiruutua.
2. **Loot → Jaa lootit.** Ikkuna listaa laukkujen puettavat itemit ja
   kertoo jokaisen kohdalla montako paikalla olevaa on varannut sen.
   Valitse jaettavat ja paina *Aloita jako (n)*.
3. **Jokaisen raidilaisen ikkuna aukeaa** samaan näkymään. Itemit ovat
   välilehtinä, ja jokaisen kohdalla vastataan yhdellä napilla:
   **LootPrio, Main spec, Off spec, Muu** tai **Pass**.
4. **Lootmaster näkee kaikki vastaukset** yhdessä listassa: peruste,
   arvonta, pelaaja ja montako loottia hän on jo saanut. Listan voi
   **lajitella otsikoista**; oletuksena vahvin peruste on ylimpänä ja
   arvonta ratkaisee vain tasatilanteen.
5. **Assign** rivin lopusta antaa itemin. Addon ilmoittaa raidichattiin
   mikä item meni kenelle ja millä perusteella.
6. **Jaettu item katoaa välilehdistä** ja jää Historia-välilehdelle.
   Jäljellä on aina vain se mikä on vielä päättämättä.

Kaikki valitut itemit menevät jakoon, eivät vain profiileissa olevat —
profiili on yksi peruste neljästä, ei pääsyvaatimus.

**LootPrio-nappi on käytössä vain jos item on oikeasti omassa
profiilissa.** Jos joku silti väittää priota, rivi merkitään punaisella
huutomerkillä kaikille joilla profiilit on tuotuna.

**Historia.** Jaetut itemit kirjautuvat Historia-välilehdelle: item, saaja,
peruste ja arvonta. *Luo vienti sivustolle* vaihtaa listan tilalle tekstin,
jonka liittää sivuston ylläpitoon — sen jälkeen saadut itemit saavat
profiiliin vihreän merkin.

**Laaturaja.** Asetukset → *Jaettavien vähimmäislaatu* ratkaisee mitä
laukuista tarjotaan. Oletus on sininen; ilman rajaa listassa olisi jokainen
juomapullo.

**Testi.** Asetukset → *Käynnistä testi* tekee neljä kuviteltua loottia
tuoduista valinnoista ja arpoo niille vastaukset. Mitään ei lähetetä
raidille eikä pelin loottiin kosketa.

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

**Siirtää itemiä laukusta toiselle pelaajalle.** Pelin oma lootin jako
toimii vain avoimen loottiruudun kautta. Siksi *Assign* kirjaa päätöksen ja
kertoo sen raidille, mutta tavaran lootmaster antaa itse kaupassa.
