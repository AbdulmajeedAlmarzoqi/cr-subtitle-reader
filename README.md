# CR Subtitle Reader

**Read Crunchyroll subtitles with VoiceOver in Safari.**

Crunchyroll draws its subtitles as pixels on a canvas, so screen readers never see them. CR Subtitle Reader fixes that on macOS: a small script inside the page fetches the subtitle file Crunchyroll already uses, follows the video and announces every line through VoiceOver, with the same smart de-duplication as the Subtitle Reader add-on for NVDA.

It comes as a native macOS app that guides you through the setup step by step, installs the script for you, verifies every requirement, and keeps itself up to date.

## Features

- **Works in Safari with VoiceOver.** Subtitles are announced through an ARIA live region as soon as they appear, in fullscreen too.
- **Background reading.** Optionally, the app speaks subtitles through VoiceOver's own AppleScript interface (speech and braille) while you are in another app.
- **Automatic language.** Picks the subtitle language from your Crunchyroll profile, remembers your choice, and lets you switch languages without touching the player's visual menu.
- **In-page shortcuts.** Option+Shift+S toggles reading, Option+Shift+L switches language, Option+Shift+R repeats the current line.
- **Setup assistant.** Installs the free Userscripts extension's script for you and checks Safari and VoiceOver settings.
- **Menu bar quick actions, launch at login, automatic updates** with release notes and one-click installation.
- **Free and open source** under the GPL-3.0-or-later.

## Requirements

- macOS 13 Ventura or later, Safari, VoiceOver.
- The free [Userscripts](https://apps.apple.com/app/userscripts/id1463298887) Safari extension (the app opens the App Store page for you).
- A Crunchyroll account (subtitles come from Crunchyroll's own subtitle files).

## Install

1. Download `CR-Subtitle-Reader-<version>.zip` from the [latest release](https://github.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader/releases/latest) and unzip it.
2. Move **CR Subtitle Reader.app** to your Applications folder and open it.
   The app is signed locally, not notarized by Apple, so the first launch is blocked by Gatekeeper. Open **System Settings > Privacy & Security**, scroll to the message about CR Subtitle Reader and choose **Open Anyway** (or Control-click the app in Finder and choose Open). This is needed once.
3. Follow the setup assistant. Each step checks itself continuously, so you only follow the instructions and press Continue:
   1. Install the Userscripts extension from the App Store (the page notices when it is installed).
   2. Safari access: choose **Allow** when macOS asks whether the app may control Safari, and in Safari turn on Settings > Advanced > "Show features for web developers", then Developer > **Allow JavaScript from Apple Events**.
   3. VoiceOver access: choose **Allow** when macOS asks, and in **VoiceOver Utility > General** turn on **Allow VoiceOver to be controlled with AppleScript**. VoiceOver confirms as soon as it works.
   4. The app places the script in the Userscripts folder and opens crunchyroll.com. In Safari Settings > Extensions turn on Userscripts and allow it for crunchyroll.com; the page reports "Running" the moment the script responds.
   5. Decide whether the app should keep running in the menu bar (needed for speaking in the background), launch at login and check for updates by itself, then press **Finish**.
4. Open any episode on Crunchyroll in Safari. You will hear "Subtitles loaded: …" and then every line as it appears.

With the menu bar option on, later launches open no window: VoiceOver says "Ready" and the app waits in the menu bar. Click the menu bar icon or the Dock icon to open the status window; closing (Command+W) or minimizing it keeps the app running, Command+Q quits it. With the option off, the app opens its status window and quits when you close it.

## Using it

Two things can read the subtitles, and the app always tells you which one is active (the "Now:" line at the top of its menu, and the "Who is reading right now" section in its window):

- **Safari itself.** The script writes each line into a hidden live region and VoiceOver reads it like any other page change. Nothing else is needed, but it only works while Safari is the front application.
- **The app, in the background.** Turn on "Speak in Background" and the app reads through VoiceOver's own voice and braille wherever you are. This needs the Safari and VoiceOver access from the setup.

"Mute Subtitles" is the real off switch: it silences the script inside the page, so neither channel reads anything until you unmute.

| Where | Action | Result |
|---|---|---|
| Crunchyroll page | Option+Shift+S | Mute or unmute subtitles |
| Crunchyroll page | Option+Shift+L | Switch to the next available subtitle language |
| Crunchyroll page | Option+Shift+R | Repeat the current line |
| Menu bar or Actions menu | Mute Subtitles / Unmute Subtitles | Same as Option+Shift+S (Command+Shift+M in the app) |
| Menu bar or Actions menu | Speak in Background | Read through VoiceOver even when Safari is not in front (Command+Shift+B in the app) |
| Menu bar or app menu | Check for Updates… | Fetch the latest release, show its notes and install it |

If you only listen inside Safari and do not want a menu bar icon, turn off "Keep running in the menu bar" at the end of the setup or in Settings. The app then quits when you close its window and behaves as a plain setup and status tool.

### Automation with `crsr://` links

The app registers the `crsr` URL scheme, so any tool that can open a link can drive it, for example a VoiceOver Commander AppleScript, a Shortcuts action or the Terminal:

| Link | Action |
|---|---|
| `crsr://reader/start`, `crsr://reader/stop`, `crsr://reader/toggle` | Background reading through VoiceOver |
| `crsr://page/mute`, `crsr://page/unmute`, `crsr://page/toggle` | Silence or resume the script in the Crunchyroll tab |
| `crsr://page/language`, `crsr://page/repeat` | Next subtitle language, repeat the current line |
| `crsr://update/check` | Check for updates |
| `crsr://setup`, `crsr://show` | Open the setup assistant or the main window |

Example from the Terminal or an AppleScript: `open -g "crsr://reader/toggle"`.

The `applescript` folder also contains standalone scripts (toggle, next language, repeat, and a stay-open reader) that you can bind to keys with VoiceOver Utility > Commanders > Keyboard > Run AppleScript.

## How it works

1. The userscript runs in the page at document start and wraps `fetch`/`XMLHttpRequest`. When Crunchyroll requests `/playback/…`, the response lists subtitle files (ASS) for every language; the script downloads the selected one and parses it.
2. Every 150 ms it reads the `<video>` element's current time and picks the active line, skipping signs and on-screen text.
3. The line passes through the de-duplication logic ported from the NVDA add-on (`processSubtitle` / `filterSamePart`) so partial repeats and overlapping lines are not read twice.
4. The result is written to a visually hidden `aria-live="assertive"` region inside the player, which VoiceOver announces.
5. VoiceOver only announces live regions of the front application, so reading stops the moment you switch away from Safari. While "Speak in Background" is on, the app sends a heartbeat through `localStorage`; the script then stops using the live region and the app speaks the text with VoiceOver's `output` command through the embedded AppleScript bridge, wherever you are. Turning it off hands control back to the live region immediately.

The script never sends data anywhere, never touches your credentials and does not change playback.

## Building from source

Requires the Xcode Command Line Tools (Swift 5.9 or later).

```bash
git clone https://github.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader.git
cd cr-subtitle-reader
./scripts/build-app.sh
```

The universal app lands in `build/CR Subtitle Reader.app` together with a zip and its SHA-256. Set `CODESIGN_IDENTITY` to sign with a Developer ID. `swift build` alone compiles the executable for development.

`test/index.html` is a small harness that simulates Crunchyroll's playback response, a subtitle file and a video element, so the script's logic can be tested in any browser without an account (`python3 -m http.server 8765`, then open `http://localhost:8765/test/`).

## Releasing

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, `@version` in `userscript/cr_subtitle_reader.user.js` (and its `.meta.js`), and update `CHANGELOG.md`.
2. Commit, tag `vX.Y.Z` and push. GitHub Actions builds the app and attaches the zip to the release; the app's updater reads the release notes from the release body.

## Credits

- **Abdulmajeed Almarzoqi** — AppleScript, Safari userscript and the macOS app (VoiceOver edition).
- **[Subtitle Reader](https://github.com/maxe-hsieh/subtitle_reader)** for NVDA by **福恩 (maxe-hsieh)** — the original project and its subtitle de-duplication logic.
- **[PlatinumTsuki](https://github.com/PlatinumTsuki)** — found and implemented the Crunchyroll technique for NVDA ([pull request #58](https://github.com/maxe-hsieh/subtitle_reader/pull/58)); this project ports that work to Safari and VoiceOver.
- **[Userscripts](https://github.com/quoid/userscripts)** by quoid — the open-source Safari extension that runs the script.

## License

GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
