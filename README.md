# Woop Woop Keynote

[![Support me on Patreon](https://img.shields.io/badge/Patreon-Support%20my%20work-FF424D?style=flat&logo=patreon&logoColor=white)](https://www.patreon.com/AndersBjarby)

A presentation tool for kids, built for three siblings (11, 14 and 16). The iPhone/iPad app is
where you build, together and live. The Apple TV app is the stage: it shows the build as it
happens and then the presentation itself. Everything runs on the home network, with no server
and no accounts. The app's interface is in Swedish.

## Features

**Build**
- Text, shapes, photos, GIFs (search through GIPHY, always `rating=g`), freehand drawings,
  charts (bar and pie), short video clips and countdown timers
- 17 themes, 14 slide layouts and ready-made outlines: school project, book review, top 5,
  quiz, about me
- Image placeholders filled from the camera, the clipboard, your photos, AI or the family library
- Paste images and text from other apps
- Move, resize, rotate, reorder layers, duplicate, undo and redo
- Speaker notes for every slide

**Build together**
- Several iPhones and iPads edit the same presentation at once on the home network, with no
  server and no accounts
- The sharer lets others in, and the element you select is locked to you
- Whoever taps *Dela* (Share) last takes over the TV
- Yellow sticky notes for collaborators that only show while building
- A shared whiteboard where everyone draws on the TV at once
- Give a copy of the presentation to someone who has joined

**Apple TV**
- A waiting screen with flying slides and a theme tune
- A build view that follows the slide where something is happening and shows who is doing what
- Presentation mode, controlled from the phone or the remote

**Present**
- The phone as a remote with notes, a clock and a hint about what the next tap does
- Reveal elements on tap with eight effects, make them vanish on tap, and give them sounds
- Motion on elements (wobble, pulse, float, spin) and six slide transitions
- Clickable elements that jump to another slide
- Laser pointer, pen and eight sound-board buttons
- Practice mode that times each slide

**The audience**
- Votes through a QR code in the browser, with no app
- Polls and quizzes with names, and points for correct and fast answers
- Scoreboard, buzzer, spinning wheel and questions to the presenter
- Emoji reactions that float up over the slide

**AI (optional, needs your own key)**
- Generate images from a description, with a style, a shape and an optional reference image
- A magic wand that improves the description
- Help with text: bullet points, shorter, spelling, headline suggestions
- A draft of a whole presentation from a topic
- AI-generated slide backgrounds
- Remove the background from an image, entirely on the device

**Save and share**
- Export to PowerPoint, Keynote and Google Slides (`.pptx`) and to PDF
- Backup of presentations to each person's own iCloud
- A shared family library of generated images
- Sharing survives the app being in the background for up to fifteen minutes

**Under the hood**
- Two apps (iOS/iPadOS and tvOS) sharing one Swift package, with no third-party dependencies
- A hand-written writer for the PowerPoint format
- 22 automated tests and 25 design rules in [`CONTRACT.md`](CONTRACT.md)

Not yet confirmed on real devices: the two iCloud features, video clips, and the shared
whiteboard across several phones.

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
