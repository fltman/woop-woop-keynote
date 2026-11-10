# Woop Woop Keynote

[![Support me on Patreon](https://img.shields.io/badge/Patreon-Support%20my%20work-FF424D?style=flat&logo=patreon&logoColor=white)](https://www.patreon.com/AndersBjarby)

A presentation tool for kids, built for three siblings (11, 14 and 16). The iPhone/iPad app is
where you build, together and live. The Apple TV app is the stage: it shows the build as it
happens and then the presentation itself. Everything runs on the home network, with no server
and no accounts. The app's interface is in Swedish.

## What it does

- **Build together.** Several iPhones and iPads edit the same presentation at once. One device
  shares, the others join after the sharer says yes. The element you select is locked to you.
- **Apple TV as the stage.** Tap *Dela* (Share) and the presentation appears on the TV. The TV
  follows the slide where something is happening, glows edits in each person's colour and
  shows a feed of who is doing what.
- **Present.** Reveal elements on tap with effects (fade, pop, fly, spin, bounce, confetti),
  make them vanish on tap, attach recorded sounds, and link elements to slides.
  With an Apple TV connected the phone becomes a presenter display: next slide, clock, notes.
- **Live extras.** Laser pointer, drawing on the slide, a sound board, and emoji reactions from
  the audience that float up over the slide.
- **Polls and quizzes.** A poll is an element on the slide. The audience scans a QR code and
  votes in the browser on a small web page served by the sharing device.
- **Content.** Text, shapes, photos, freehand drawings, paste from other apps, and GIF search
  through GIPHY (always `rating=g`), and images generated from a description (via OpenRouter).
- **Quiz as a game.** Named players, points for correct and fast answers, a podium, a buzzer,
  a spinning wheel and questions from the audience.
- **More building blocks.** Charts, countdown timers, short video clips, sticky notes for
  collaborators, a shared whiteboard on the TV, and a practice mode that times each slide.
- **AI help (optional).** Rewrite text, draft a presentation from a topic, generate images and
  backgrounds. Background removal runs on the device.
- **iCloud.** Presentations are backed up to each person's own iCloud; generated images go to a
  shared family library.
- **Export.** `.pptx` (opens in PowerPoint, Keynote and Google Slides) and PDF.

## Build

Requirements: Xcode (developed with Xcode 27), [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an Apple
Developer account for running on real devices.

```sh
brew install xcodegen
xcodegen generate
open WoopWoop.xcodeproj
```

Before building:

1. Set your own `DEVELOPMENT_TEAM` and bundle identifiers in `project.yml`.
2. GIF search is optional. To enable it, copy `Config/Secrets.example.xcconfig` to
   `Config/Secrets.xcconfig` and add a free API key from
   [developers.giphy.com](https://developers.giphy.com). The file is gitignored.
3. AI image generation is optional too. Add an `OPENROUTER_API_KEY` to the same file. The key is
   compiled into the app, so only share builds with people you trust, and set a credit limit on it.
   Generated images that are used are saved to a shared library in the app's iCloud container;
   set `ICLOUD_CONTAINER` in `Config/Base.xcconfig` to your own container.

The project has two targets: `WoopWoop` (iOS/iPadOS 18+) and `WoopWoopTV` (tvOS 18+).

Run the tests for the shared package:

```sh
cd Packages/SlideKit && swift test
```

## How it is built

```
Packages/SlideKit/   Shared Swift package for iOS, tvOS and macOS (macOS only for tests)
  Model/             Deck, Slide, Element, Op. Plain Codable data.
  Render/            SlideView (SwiftUI). The same drawing code everywhere.
  Sync/              Host and clients over Bonjour + TCP, length-prefixed JSON.
  Export/            PPTX writer (own OOXML and zip, no dependencies).
App-iOS/             Editor, library, presenting, export.
App-tvOS/            Stage and presentation.
tools/               Script that draws the Apple TV icon.
```

The sharing device is the authority: every change is an `Op`, clients show confirmed state plus
their own pending ops, and the host sends each committed op to everyone. There are no
third-party dependencies. [`CONTRACT.md`](CONTRACT.md) (in Swedish) holds the binding design rules.

## Good to know

- Devices must be on the same Wi-Fi. iOS suspends apps in the background, so the sharing device
  keeps its screen awake and everyone reconnects automatically after an interruption.
- The only things that leave the home network are the search words sent to GIPHY and the
  descriptions typed for AI images.
- Keynote drops click sounds from exported `.pptx` files. Polls export as plain text.
- The sound board effects were generated with ElevenLabs.

## License

MIT, see [LICENSE](LICENSE).
