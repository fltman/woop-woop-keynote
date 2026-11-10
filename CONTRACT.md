# CONTRACT — Woop Woop Keynote

Ett presentationsverktyg för tre syskon (11, 14, 16). Bindande för all kod i repot.
Ändras bara medvetet, och då i samma commit som koden som följer ändringen.

## Vad det är

- **iOS/iPadOS-appen är verktyget.** Man bygger, presenterar och exporterar där.
  Presentera går via skärmdelning (AirPlay-spegling) eller via tvOS-appen.
- **tvOS-appen är scenen.** Den visar bygget live med allas markörer och presenterar.
  Man redigerar aldrig med Siri-fjärren, men fjärren styr presentationen.
- **Samredigering på hemnätet.** Flera iPads och TV:n i samma session, utan server och utan konto.
- **Export:** .pptx är navet. Keynote och Google Slides öppnar .pptx. PDF finns som komplement.

## Arkitektur

```
Packages/SlideKit/     Delad Swift-kod för iOS, tvOS och macOS (macOS bara för tester)
  Model/               Deck, Slide, Element, Op. Ren data, Codable.
  Render/              SlideView (SwiftUI). Samma ritning överallt.
  Sync/                Värd och klient över Bonjour + TCP, längdprefixad JSON.
  Export/              PPTX-skrivare (egen OOXML och egen zip, inga beroenden).
App-iOS/               Editor, bibliotek, presentation, export.
App-tvOS/              Hitta värd, scen och presentation.
vault/                 Obsidian-vault, gitignorerad. Idéer och öppna frågor.
```

### Bindande regler

1. **Bildytan är 1920×1080 enheter (16:9).** All geometri anges i de enheterna.
   1 enhet = 6350 EMU = 0,5 pt i .pptx. Typsnittsstorlek anges i enheter, och pt = enheter × 0,5.
2. **Modellen får bara innehålla det som går att exportera.** Varje fält ska ha en motsvarighet i .pptx.
   Det som inte går att exportera (omröstningar, minispel) skrivs ut som en statisk ersättning.
   Ingen ny elementtyp utan att exporten följer med i samma commit.
3. **Värden bestämmer.** Alla ändringar är `Op`. Klienten visar `confirmed + pending`.
   Värden sätter ordningen och skickar varje op till ALLA, även avsändaren. En klient
   stryker sin egen pending-op när den kommer tillbaka. Då kan två enheter aldrig hamna olika.
4. **Lås per element i stället för textsammanslagning.** Det element du markerar låses åt dig.
   Andras ändringar av ett låst element avvisas av värden. Låsen släpps när man kopplar ner.
5. **Typsnitt:** bara de som finns på iOS, macOS, Windows och Google Slides: Arial, Georgia,
   Verdana, Trebuchet MS, Courier New och Times New Roman.
6. **Inga tredjepartsberoenden** i SlideKit så länge det går att undvika.
7. **Bilder** skalas ner vid import till högst 2048 px och lagras innehållsadresserat (sha256).
8. **Barnens innehåll lämnar aldrig hemnätet** om inte någon exporterar och delar själv.
9. **Inget delas förrän man själv trycker på Dela.** Då visas presentationen direkt på en
   ledig TV, utan att någon behöver välja med fjärren. En TV som visar något levande stannar kvar där.
10. **Värden släpper in redigerare** (ja/nej). TV:n bara tittar och kommer in direkt.
    Den som släppts in en gång kommer in direkt igen efter ett avbrott.
11. **Avbrott är det normala.** iOS pausar appen vid skärmlås, appbyte eller fjärren.
    Den som delar håller skärmen vaken, får cirka 30 s i bakgrunden och delar igen när appen
    kommer fram. Klienter och TV återansluter själva. Råa nätverksfel visas aldrig.
12. **Scenen är en livesändning.** Kameran följer bilden där något händer, ändringar lyser
    i personens färg, och flödet bredvid bilden (aldrig ovanpå) säger vem som gör vad.
    Anteckningar syns aldrig på scenen.

## Faser

1. Modell, rendering, iOS-editor, bibliotek, .pptx- och PDF-export, tvOS-scen och presentation.
2. Samredigering mellan flera iPads: lås, närvaro, live-drag på scenen och bildsynk.
3. Klickbara bilder: länk till bild, nästa och föregående (exporteras som PPTX-hyperlänkar).
4. Publiken deltar: omröstning och quiz via QR på TV:n, med en webbsida från värden.
