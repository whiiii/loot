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

## Jos addon lukee punaisella "Incompatible"

Silloin `.toc`-tiedoston `## Interface` -numero ei vastaa clientiä, eikä
addon lataudu lainkaan — ei `/lp`-komentoa eikä minimap-nappia. Kyse ei ole
koodivirheestä.

Numero **ei ole** pelin versionumero vaan siitä johdettu kokonaisluku
kaavalla `major × 10000 + minor × 100 + patch`. Esimerkiksi versio 1.60.1
on `11601` ja 1.15.7 on `11507`.

Oikean numeron saa pelistä. Nämä ovat pelin omia komentoja eivätkä vaadi
yhtäkään ladattua addonia:

```
/run print((select(4, GetBuildInfo())))
```

Vaihda saamasi luku `LootPrio.toc`-tiedoston ensimmäiselle riville ja tee
`/reload`. Kun addon kerran latautuu, se huomauttaa itse jos numero on
väärin, eikä arvailua enää tarvita.

Laita samalla Lua-virheet näkyviin, jotta hiljainen kaatuminen ei jää
huomaamatta:

```
/console scriptErrors 1
```

**AddOns → Load out of date AddOns** vaikuttaa vasta kun painaa *Okay* ja
käyttöliittymä latautuu uudelleen, eikä se ohita kuin pienen versioeron.

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

   Kaikkea ei tarvitse olla laukussa: **shift-klikkaa item ikkunan
   kenttään** ja paina *Lisää*, niin se tulee mukaan jakoon. Näin voi
   jakaa myös itemin joka on jonkun toisen hallussa tai mennyt vikaan.
3. **Jokaisen raidilaisen ikkuna aukeaa** samaan näkymään. Itemit ovat
   välilehtinä, ja jokaisen kohdalla vastataan yhdellä napilla:
   **LootPrio, Main spec, Off spec, Muu** tai **Pass**.
4. **Lootmaster näkee kaikki vastaukset** yhdessä listassa: peruste,
   arvonta, pelaaja ja montako loottia hän on jo saanut. Listan voi
   **lajitella otsikoista**; oletuksena vahvin peruste on ylimpänä ja
   arvonta ratkaisee vain tasatilanteen. Kulunut aika näkyy oikeassa
   alareunassa ja muuttuu punaiseksi kun odotusaika ylittyy.
   *Sulje vastaukset* estää uudet vastaukset kun päätös on tehty.
5. **Assign** rivin lopusta antaa itemin. Addon ilmoittaa raidichattiin
   mikä item meni kenelle ja millä perusteella. *Peru jako* kumoaa
   viimeisimmän: item palaa välilehtiin ja historiarivi häviää.
6. **Jaettu item katoaa välilehdistä** ja jää Historia-välilehdelle.
   Jäljellä on aina vain se mikä on vielä päättämättä.
7. **Päätä jako** lähettää raidichattiin yhteenvedon illan jaosta: yksi
   rivi per pelaaja.
8. **Avaa kauppa voittajan kanssa.** Assignatut itemit asettuvat
   vaihtopaikoille itsestään — ks. *Kauppa*-välilehti alla.

## Kuka saa jakaa

Jaon avaaminen vaatii **kaksi asiaa yhtä aikaa**:

1. **Raid assist tai raid leader** pelissä, ja
2. **officer-rooli killan sivustolla**.

Raidin arvo yksin ei riitä, koska assist annetaan usein markkereita varten
eikä loottia. Sivuston rooli yksin ei riitä myöskään: raidissa jakaa se
jolla on raidin oikeudet, ei officer joka on paikalla vain katsomassa.

Officer-lista tulee viennin mukana. Jos vientiä ei ole tuotu, listaa ei
ole — silloin pelkkä raidin arvo riittää, koska itsensä lukitseva addon on
hyödyttömämpi kuin luottavainen. **Jos joku saa officerin sivustolla kesken
illan, vienti pitää tehdä uudelleen ennen kuin addon tietää siitä.**

Jäsenet-listassa officerin nimen perässä on kultainen ◆.

**Lootmaster on se joka avaa jaon.** Vain yksi jako voi olla kerrallaan
auki, ja vain lootmaster voi antaa, perua, sulkea tai päättää sen. Jos
lootmaster putoaa linjoilta, raidin johtaja voi ottaa jaon haltuunsa — ja
jos hän ei ole paikalla, jako vapautuu itsestään toisen avattavaksi.

## Ennen raidia: tarkista addonit

**Jäsenet → Tarkista addonit** kysyy koko raidin version. Lista näyttää
kolme eri tilaa, koska ne vaativat eri toimen:

| ADDON | Tarkoittaa |
|---|---|
| `v0.6` vihreänä | kaikki kunnossa |
| `v0.5` punaisena | vanha versio — päivitettävä |
| `ei dataa` punaisena | addon on, mutta vientiä ei ole tuotu |
| `—` harmaana | ei vastannut: addon puuttuu |

Alareunassa näkyy lisäksi ketkä paikallaolijat **eivät ole profiililistassa
lainkaan**. Heille jako näyttää rikkinäiseltä — LootPrio-nappi on harmaa
eikä syy näy mistään — vaikka mikään ei ole rikki.

Tämä on syytä tehdä kerran ennen ensimmäistä bossia. Eri versiot eivät
kerro itsestään mitään: viestien kenttämäärä vain ei täsmää, ja osa jaoista
jää kirjautumatta hiljaa.

**SAATU-sarake** on sivuston koko historia. Jos luvun perässä on `(+2)`,
kaksi niistä on tämän koneen kirjaamia jakoja joita ei ole vielä viety
sivustolle.

## Kauppa

Addon ei voi antaa laukussa olevaa itemiä koodista käsin, mutta se voi
täyttää kauppaikkunan. Kun avaat kaupan pelaajan kanssa jolle on
assignattu itemejä, ne **asettuvat vaihtopaikoille itsestään**.

Addon ei koskaan hyväksy kauppaa. *Kauppa*-nappia painat itse: väärin
mennyttä kauppaa ei voi perua, ja silmä ehtii aina katsoa kerran.

**Kauppa-välilehti** on luovuttamattomien lista. Siinä näkyy item, saaja
ja se löytyykö item vielä omista laukuista — jos ei löydy, kauppaikkuna
jäisi tyhjäksi, ja syy on parempi nähdä tässä kuin kaupan auettua.
*Annettu* merkitsee rivin käsin, jos item vaihtoi omistajaa muuten.

Toimitetuksi merkitseminen perustuu laukkujen kappalemäärään kaupan
ennen ja jälkeen, joten **peruttu kauppa ei merkitse mitään annetuksi**.

Automaatin voi kytkeä pois Asetuksista.

Kaikki valitut itemit menevät jakoon, eivät vain profiileissa olevat —
profiili on yksi peruste neljästä, ei pääsyvaatimus.

**LootPrio-nappi on käytössä vain jos item on oikeasti omassa
profiilissa.** Jos joku silti väittää priota, rivi merkitään punaisella
huutomerkillä kaikille joilla profiilit on tuotuna.

**Historia.** Jaetut itemit kirjautuvat Historia-välilehdelle: item, saaja,
peruste ja arvonta. *Luo vienti sivustolle* vaihtaa listan tilalle tekstin,
jonka liittää sivuston ylläpitoon — sen jälkeen saadut itemit saavat
profiiliin vihreän merkin ja siirtyvät seuraavan viennin SAATU-lukuun.

Kierros on siis: tuo profiilit → jaa → vie historia → tuo profiilit
uudelleen → tyhjennä paikallinen historia. Niin kauan kuin se tehdään
tässä järjestyksessä, luvut eivät kahdennu.

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
| `/lp kauppa` | avaa luovuttamattomien listan |

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
toimii vain avoimen loottiruudun kautta. Addon voi täyttää kauppaikkunan,
mutta *Kauppa*-nappia painaa ihminen.

**Kaupata sidottua itemiä.** Jos item sitoutuu lootmasteriin kun hän
nostaa sen laukkuun, sitä ei voi enää antaa kenellekään — silloin
master loot on ainoa tapa. Tämä riippuu siitä onko palvelimella
kaupankäyntiaikaa sidotuille itemeille.
