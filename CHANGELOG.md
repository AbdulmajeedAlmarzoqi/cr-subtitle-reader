# Changelog

All notable changes to CR Subtitle Reader are documented here.

## 1.0.0 — 2026-09-06

First release.

- Safari userscript that reads Crunchyroll subtitles with VoiceOver through an ARIA live region, with the same de-duplication logic as the Subtitle Reader NVDA add-on.
- Automatic subtitle language selection from the Crunchyroll account preference, with in-page shortcuts to toggle reading (Option+Shift+S), switch language (Option+Shift+L) and repeat the current line (Option+Shift+R).
- Native macOS app with a step-by-step setup assistant that installs the script into the Userscripts extension and verifies every requirement live, with no manual check buttons.
- After setup the app lives in the menu bar: closing or minimizing its window keeps it running, Command+Q quits it, and later launches just say "Ready".
- Background reading through VoiceOver's own AppleScript interface (speech and braille), including while other apps are in front.
- Menu bar quick actions, launch at login, and automatic update checks with one-click installation from GitHub Releases.
- Standalone AppleScripts for people who prefer VoiceOver Commander bindings.
