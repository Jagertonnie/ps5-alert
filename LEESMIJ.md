# PS5 Pro stock alert

Controleert een aantal winkels en laat je iPhone als alarm afgaan zodra de PS5 Pro
te koop is voor maximaal €1000, verkocht door de winkel zelf.

## 1. Melding instellen (eenmalig, ongeveer 5 minuten)

1. Zet de app **Pushover** op je iPhone en maak in de app een account aan.
2. Log op de laptop in op [pushover.net](https://pushover.net). Bovenaan staat je **User Key**.
3. Klik onderaan op **Create an Application/API Token**, geef hem een naam (bijvoorbeeld "PS5 alert")
   en maak hem aan. Je krijgt een **API Token**.
4. Dubbelklik op `installeer.cmd`. Dat maakt `config.json` aan en start de controle.
5. Open `config.json` in Kladblok en vul de twee sleutels in tussen de aanhalingstekens:
   `pushoverUserKey` en `pushoverAppToken`. Opslaan is genoeg, herstarten hoeft niet.
6. Dubbelklik op `test-melding.cmd`. Je iPhone hoort nu af te gaan.
7. Zet in de Pushover-app bij de instellingen **Critical Alerts** aan. Dan gaat het alarm ook af
   als je telefoon op stil of "Niet storen" staat.

Pushover is 30 dagen gratis, daarna een eenmalige aankoop in de app.

## 2. Op een laptop laten draaien

Dubbelklik op `installeer.cmd`. De controle draait dan onzichtbaar op de achtergrond en start
voortaan vanzelf zodra je inlogt. PlayStation Direct wordt elke 2 minuten bekeken, de rest elke 5.

- `status.cmd` laat zien of hij draait en wat de laatste uitkomst per winkel is.
- `verwijder.cmd` stopt hem en haalt hem weg bij het opstarten.

**Laptop thuis:** zet deze hele map in OneDrive, wacht tot hij thuis gesynchroniseerd is en
dubbelklik daar ook op `installeer.cmd`. Je sleutels in `config.json` komen dan vanzelf mee.
Verplaats je de map, dubbelklik dan opnieuw op `installeer.cmd`.

## 3. In de cloud laten draaien (ook als alle laptops uit staan)

OneDrive kan alleen bestanden bewaren, geen programma's draaien. Dit kan gratis via GitHub:

1. Maak een account op [github.com](https://github.com) en maak een nieuwe **public** repository
   aan, bijvoorbeeld `ps5-alert`, zonder README.
2. Zet alle bestanden uit deze map erin, behalve `config.json` (die bevat je sleutels).
3. Ga in de repository naar **Settings > Secrets and variables > Actions** en maak twee secrets:
   `PUSHOVER_USER_KEY` en `PUSHOVER_APP_TOKEN`, met dezelfde waarden als in `config.json`.
4. Ga naar het tabblad **Actions**, kies **PS5 Pro stock alert**, klik **Run workflow**, vink
   **testalarm** aan en start. Gaat je iPhone af, dan werkt het.

Daarna controleert GitHub ongeveer elke 5 minuten. Bij drukte start GitHub soms later, dus de
laptop blijft sneller. Draaien laptop en cloud allebei, dan kun je twee alarmen krijgen voor
dezelfde aanvulling. GitHub zet de planning uit als er 60 dagen niets in de repository verandert.

Publiek is nodig omdat de controle anders meer rekentijd kost dan gratis is. Er staat niets
persoonlijks in: je sleutels staan alleen in de secrets.

## Goed om te weten

- **Het alarm gaat ook 's nachts af** en herhaalt elke 30 seconden tot je de melding opent, maximaal een uur.
- **Je krijgt een alarm per aanvulling.** Blijft hij op voorraad, dan komt er geen tweede.
- **Kan een winkel een uur lang niet uitgelezen worden**, dan krijg je daarover een gewone melding.
- **Maximumprijs aanpassen:** `maxPrijs` in `config.json`.
- **Winkels aanpassen:** `winkels.json`. Externe verkopers op MediaMarkt en Amazon tellen niet mee.
- **Amazon.de, .fr en .com.be:** controleer bij het afrekenen of ze naar Nederland bezorgen.
- **Niet gevolgd** omdat ze scripts blokkeren: bol, Nedgame, Game Mania, Azerty en Fnac.
- **PS Plus-leden** krijgen bij PlayStation Direct 5% korting op de console.
- Het logboek staat in `%LOCALAPPDATA%\ps5-alert\ps5-alert.log`.

## Tests

`powershell -NoProfile -File tests\Run-Tests.ps1` controleert het uitlezen tegen bewaarde stukken
van echte winkelpagina's. Handig als een winkel zijn site verandert.
