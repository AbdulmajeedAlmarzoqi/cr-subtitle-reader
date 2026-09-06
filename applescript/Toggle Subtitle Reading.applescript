(*
	CR Subtitle Reader — Toggle Subtitle Reading
	Turns subtitle reading on or off by sending a command to the CR Subtitle Reader userscript
	in the Crunchyroll tab that is active in Safari's front window.
	The userscript announces the result (ARIA live region, or the app when it is running).

	Handy for VoiceOver Utility > Commanders > Keyboard > "Run AppleScript".
	Requires Safari > Settings > Developer > "Allow JavaScript from Apple Events".

	Developed by Abdulmajeed Almarzoqi. License: GPL-3.0-or-later.
*)

on run
	my sendCommand("toggle")
end run

on sendCommand(cmd)
	if not (application "Safari" is running) then return
	tell application "Safari"
		if (count of windows) is 0 then return
		set theTab to current tab of front window
		set theURL to URL of theTab
		if theURL is missing value then return
		if theURL does not contain "crunchyroll.com" then return
		do JavaScript "localStorage.setItem('crsr-cmd','" & cmd & "\\t'+Date.now())" in theTab
	end tell
end sendCommand
