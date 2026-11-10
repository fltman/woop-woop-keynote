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
   En bild utan fil (`ImageBox.placeholder`) är en bildplats: den syns när man bygger, men aldrig
   i presentationen eller i exporten. Mallar använder bildplatser, inte former som låtsas vara det.
8. **Barnens innehåll lämnar aldrig hemnätet** om inte någon exporterar och delar själv.
   Undantagen: sökorden i GIPHY-sökningen (§13) och beskrivningen man skriver när man gör en
   bild med AI (§18). AI-bilder som används sparas i familjens bibliotek i iCloud (§19).
9. **Inget delas förrän man själv trycker på Dela.** Då visas presentationen direkt på en
   TV, utan att någon behöver välja med fjärren. Den senaste delningen tar över: börjar någon
   annan dela avslutas den tidigare delningen (annonsen bär starttiden) och TV:n byter.
10. **Värden släpper in redigerare** (ja/nej). TV:n bara tittar och kommer in direkt.
    Den som släppts in en gång kommer in direkt igen efter ett avbrott.
11. **Avbrott är det normala.** iOS pausar appen vid skärmlås, appbyte eller fjärren.
    Den som delar håller skärmen vaken. I bakgrunden hålls appen vid liv upp till en kvart
    (tyst ljud, `BackgroundKeeper`), så att man kan hämta en bild i Safari utan att TV:n tappar
    kontakten. Därefter pausas den och delar igen när appen kommer fram. Klienter och TV återansluter själva. Råa nätverksfel visas aldrig.
12. **Scenen är en livesändning.** Kameran följer bilden där något händer, ändringar lyser
    i personens färg, och flödet bredvid bilden (aldrig ovanpå) säger vem som gör vad.
    Anteckningar syns aldrig på scenen.
13. **GIPHY:** bara sökorden skickas till GIPHY, alltid med `rating=g` (barnvänligt), och
    "Drivs av GIPHY" syns i sökrutan. Nyckeln ligger i `Config/Secrets.xcconfig` (gitignorerad).
    Animerade GIF:ar sparas orörda och animeras överallt. .pptx spelar dem själv.
14. **Visa när jag trycker och ljud.** Ett element med `reveal` syns inte på presentationsskärmen
    förrän den som presenterar trycker på det. Den som presenterar ser det som ett spöke.
    "Nästa" visar dolda element i ordning innan bilden byts, och bakåt ger en färdigbyggd bild.
    Ljud (`sound`) spelas av presentationsskärmen: TV:n om den är med, annars den som presenterar.
    Export: klickanimationer och klickljud (WAV) i .pptx. Känd begränsning: Keynote tappar klickljuden.
    Effekterna snurra och konfetti exporteras som zoom, studsa som flyg in uppifrån.
    "Försvinner när jag trycker" (`vanish`) finns bara i appen; i .pptx står elementet kvar.
15. **Delningen har ett fast id.** Bonjour-annonsen bär presentationens id i sin TXT-post. Namnet
    ("Ida: Vulkaner") är bara det som visas och får bytas medan man delar. TV:n och klienterna
    hittar tillbaka via id:t, och en inbjudan till TV:n (Spela → Apple TV) skickar id:t.
16. **Live under presentationen** (`LiveEvent`): reaktioner, laserpekare, streck och ljudknappar är
    flyktiga. De går via värden till alla, sparas aldrig och exporteras aldrig. Streck och pekare
    försvinner vid bildbyte. Ljudknapparnas ljud är effekter gjorda med ElevenLabs som följer med appen.
    En teckning som görs i editorn (Rita) blir däremot en vanlig bild och exporteras som en sådan.
17. **Publiken röstar på hemnätet.** Omröstningar och quiz (`Content.poll`) är element på bilden.
    Den som delar kör en liten webbserver; QR-koden i rutan leder dit. Bara värden räknar röster,
    en röst per mobil, och man får byta tills rätt svar visas. Rätt svar skickas inte till publikens
    sida förrän presentatören visar det. Rösterna sparas inte. Export: frågan och alternativen som text.
18. **Bilder med AI.** Beskrivningen man skriver skickas till en bildmodell via OpenRouter,
    tillsammans med fasta ramar om att bilden ska passa barn. Väljer man en referensbild skickas
    den också (rutan säger det och avråder från foton på personer). Trollstaven vid ett fält
    skickar fältets text till en snabb textmodell som skriver om den; alla fält där man beskriver
    något för en modell ska ha den (`PromptField`). Resultatet blir en vanlig bild i
    presentationen. Nyckeln ligger i `Config/Secrets.xcconfig` och följer med i appen som byggs,
    så appen delas bara inom familjen. Högst 30 bilder per enhet och dag.
19. **Familjens bildbibliotek.** En AI-bild som läggs på en bild sparas i appens iCloud-behållare
    (CloudKits gemensamma databas) med beskrivningen och vem som gjorde den, så att alla i familjen
    kan återanvända den. Bara AI-bilder: foton, teckningar och presentationer lämnar aldrig hemnätet.
    Den som gjorde en bild kan ta bort den. Ett fel mot iCloud får aldrig hindra arbetet.
20. **Säkerhetskopia i iCloud.** Varje persons presentationer kopieras till personens EGEN iCloud
    (CloudKits privata databas) en stund efter varje ändring, med bilderna de använder. De går att
    hämta hem på en ny enhet. Det här är ett medvetet undantag från §8: kopian ligger i barnets
    eget iCloud-konto och delas inte med någon. Ett fel mot iCloud får aldrig störa arbetet.
21. **Publiken tävlar.** Webbsidan tar ett namn. Rätt svar i ett quiz ger 100 poäng och upp till 100
    till för snabbhet, och delas ut en gång, när rätt svar visas. Bara värden räknar. Prispall,
    buzzer (först att trycka), slumphjul och publikfrågor läggs över presentationen och är flyktiga
    (`LiveEvent`). Presentatören väljer vilka publikfrågor som visas.
22. **Det som inte går att exportera plattas till.** Diagram och nedräkningar blir bilder av sig
    själva, videoklipp blir sin stillbild, och lappar och tomma bildplatser tas bort
    (`Deck.flattened`). Rörelse (gunga, pulsera …) och övergången "vänd blad" finns bara i appen.
23. **Lappar** (`sticky`) är kommentarer till dem som bygger. De syns aldrig i presentationen.
24. **Gemensam rityta.** När någon öppnar ritytan visar TV:n en tavla där alla ritar från sina
    telefoner. Strecken är flyktiga tills någon väljer "Spara som bild".
25. **AI med text.** Trollstaven i textrutor och utkastet från ett ämne skickar texten respektive
    ämnet till en textmodell via OpenRouter. Utkast ska alltid uppmana till att kontrollera fakta.

## Faser

1. Modell, rendering, iOS-editor, bibliotek, .pptx- och PDF-export, tvOS-scen och presentation.
2. Samredigering mellan flera iPads: lås, närvaro, live-drag på scenen och bildsynk.
3. Klickbara bilder: länk till bild, nästa och föregående (exporteras som PPTX-hyperlänkar).
   Visa när jag trycker, inträdeseffekter och ljud (§14). Klistra in och GIPHY (§13).
4. Publiken deltar: omröstning och quiz via QR på TV:n, med en webbsida från värden (§17).
   Reaktioner, laserpekare, rita, ljudknappar och presentatörens skärm (§16).
5. Tävling och samarbete (§21, §24), diagram, nedräkning, video, lappar, övningsläge, AI med text
   och bild (§18, §25), familjens bildbibliotek (§19) och säkerhetskopia i iCloud (§20).
