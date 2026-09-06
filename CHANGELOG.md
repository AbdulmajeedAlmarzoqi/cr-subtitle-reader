# Changelog

All notable changes to CR Subtitle Reader are documented here.

## 1.0.2 — 2026-09-06

- The app now watches its requirements: at every launch and once a minute in the menu bar. If the Userscripts extension or the script goes missing, or Safari or VoiceOver access is revoked, VoiceOver says what is wrong and the setup assistant opens at the step that fixes it.
- "Reset CR Subtitle Reader…" in Settings (and a `--reset` launch flag) forgets every setting, removes the login item and runs the assistant again.

## 1.0.1 — 2026-09-06

- The two switches now say what they do. "Mute Subtitles" silences the script inside Safari (the real off switch); "Speak in Background" makes the app read through VoiceOver while you are in another application. Before, "Background Reading Off" looked like a mute but only handed reading back to Safari.
- The menu bar menu and the status window show who is reading right now: Safari, the app, or nobody because subtitles are muted.
- New option at the end of the setup and in Settings: keep the app in the menu bar, or let it quit with its window if you only listen inside Safari.
- The app refreshes the script inside the Userscripts extension by itself when a build ships a newer one.
- New `crsr://page/mute` and `crsr://page/unmute` links; Command+Shift+M and Command+Shift+B in the app.

## 1.0.0 — 2026-09-06

First release.

- Safari userscript that reads Crunchyroll subtitles with VoiceOver through an ARIA live region, with the same de-duplication logic as the Subtitle Reader NVDA add-on.
- Automatic subtitle language selection from the Crunchyroll account preference, with in-page shortcuts to toggle reading (Option+Shift+S), switch language (Option+Shift+L) and repeat the current line (Option+Shift+R).
- Native macOS app with a step-by-step setup assistant that installs the script into the Userscripts extension and verifies every requirement live, with no manual check buttons.
- After setup the app lives in the menu bar: closing or minimizing its window keeps it running, Command+Q quits it, and later launches just say "Ready".
- Background reading through VoiceOver's own AppleScript interface (speech and braille), including while other apps are in front.
- Menu bar quick actions, launch at login, and automatic update checks with one-click installation from GitHub Releases.
- Standalone AppleScripts for people who prefer VoiceOver Commander bindings.
