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
3. Follow the setup assistant:
   1. Install the Userscripts extension from the App Store.
   2. Let the app copy the CR Subtitle Reader script into the extension's folder.
   3. In Safari, press Command+Comma, open **Extensions**, turn on Userscripts and allow it on crunchyroll.com.
   4. Optional: in Safari's **Advanced** tab turn on "Show features for web developers", then in the **Developer** tab turn on **Allow JavaScript from Apple Events**. This enables background reading, the menu bar actions and automatic verification.
   5. Optional: in **VoiceOver Utility > General** turn on **Allow VoiceOver to be controlled with AppleScript** so background reading uses VoiceOver's voice and braille.
4. Open any episode on Crunchyroll in Safari. You will hear "Subtitles loaded: …" and then every line as it appears.

## Using it

| Where | Action | Result |
|---|---|---|
| Crunchyroll page | Option+Shift+S | Turn subtitle reading on or off |
| Crunchyroll page | Option+Shift+L | Switch to the next available subtitle language |
| Crunchyroll page | Option+Shift+R | Repeat the current line |
| App or menu bar | Start Background Reading | Speak through VoiceOver even when Safari is not in front |
| App or menu bar | Check for Updates… | Fetch the latest release, show its notes and install it |

### Automation with `crsr://` links

The app registers the `crsr` URL scheme, so any tool that can open a link can drive it, for example a VoiceOver Commander AppleScript, a Shortcuts action or the Terminal:

| Link | Action |
|---|---|
| `crsr://reader/start`, `crsr://reader/stop`, `crsr://reader/toggle` | Background reading through VoiceOver |
| `crsr://page/toggle`, `crsr://page/language`, `crsr://page/repeat` | Send a command to the script in the Crunchyroll tab |
| `crsr://update/check` | Check for updates |
| `crsr://setup`, `crsr://show` | Open the setup assistant or the main window |

Example from the Terminal or an AppleScript: `open -g "crsr://reader/toggle"`.

The `applescript` folder also contains standalone scripts (toggle, next language, repeat, and a stay-open reader) that you can bind to keys with VoiceOver Utility > Commanders > Keyboard > Run AppleScript.

## How it works

1. The userscript runs in the page at document start and wraps `fetch`/`XMLHttpRequest`. When Crunchyroll requests `/playback/…`, the response lists subtitle files (ASS) for every language; the script downloads the selected one and parses it.
2. Every 150 ms it reads the `<video>` element's current time and picks the active line, skipping signs and on-screen text.
3. The line passes through the de-duplication logic ported from the NVDA add-on (`processSubtitle` / `filterSamePart`) so partial repeats and overlapping lines are not read twice.
4. The result is written to a visually hidden `aria-live="assertive"` region inside the player, which VoiceOver announces.
5. When the app's background reader is running, it sends a heartbeat through `localStorage`; the script then stops using the live region and the app speaks the text with VoiceOver's `output` command through the embedded AppleScript bridge. Stopping the app hands control back immediately.

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
