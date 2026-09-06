(*
	CR Subtitle Reader — AppleScript bridge
	Developed by Abdulmajeed Almarzoqi. License: GPL-3.0-or-later.
	https://github.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader

	This library is embedded in the CR Subtitle Reader app, which calls the handlers below.
	It is the only part of the app that talks to Safari (do JavaScript) and to VoiceOver
	(the "output" command, which speaks and shows text on a braille display).

	Requirements
	  - Safari > Settings > Advanced > "Show features for web developers", then
	    Developer tab > "Allow JavaScript from Apple Events".
	  - VoiceOver Utility > General > "Allow VoiceOver to be controlled with AppleScript".
*)

-- Returns: isWatchPage <tab> script heartbeat age in ms (-1 if none) <tab> message sequence <tab> message text
property bridgeJS : "(function(){try{var now=Date.now();localStorage.setItem('crsr-bridge-ts',String(now));var hb=Number(localStorage.getItem('crsr-heartbeat')||0);var age=hb?(now-hb):-1;var w=location.pathname.indexOf('/watch/')!==-1?1:0;var m=localStorage.getItem('crsr-msg')||'\\t';return w+'\\t'+age+'\\t'+m}catch(e){return ''}})()"
property stateJS : "(function(){try{return window.__crsrDebug?JSON.stringify(window.__crsrDebug.state):''}catch(e){return ''}})()"

-- The current tab of Safari's front window when it is on crunchyroll.com, otherwise missing value.
on crunchyrollTab()
	if not (application "Safari" is running) then return missing value
	tell application "Safari"
		if (count of windows) is 0 then return missing value
		set theTab to current tab of front window
		set theURL to URL of theTab
	end tell
	if theURL is missing value then return missing value
	if theURL does not contain "crunchyroll.com" then return missing value
	return theTab
end crunchyrollTab

-- Sends the app heartbeat and returns the latest message from the userscript ("" when not on Crunchyroll).
on readBridge()
	set theTab to crunchyrollTab()
	if theTab is missing value then return ""
	tell application "Safari" to set jsResult to do JavaScript bridgeJS in theTab
	if jsResult is missing value then return ""
	return jsResult as text
end readBridge

-- Speaks through VoiceOver. Returns "ok", "not-running", "not-authorized" (macOS Automation
-- permission missing) or "disabled" (VoiceOver's AppleScript option is off).
on speakVoiceOver(theText)
	if theText is "" then return "ok"
	if not (application "VoiceOver" is running) then return "not-running"
	try
		tell application "VoiceOver" to output theText
		return "ok"
	on error errMsg number errNum
		if errNum is -1743 then return "not-authorized"
		return "disabled"
	end try
end speakVoiceOver

-- Speaks with the system voice (fallback when VoiceOver control is unavailable).
on speakSystem(theText)
	if theText is "" then return "ok"
	say theText without waiting until completion
	return "ok"
end speakSystem

-- Sends a command to the userscript: "toggle", "language" or "repeat".
on sendCommand(cmd)
	set theTab to crunchyrollTab()
	if theTab is missing value then return "no-tab"
	tell application "Safari" to do JavaScript "localStorage.setItem('crsr-cmd','" & cmd & "\\t'+Date.now())" in theTab
	return "ok"
end sendCommand

-- Removes the heartbeat so the userscript returns to the ARIA live region immediately.
on clearBridge()
	set theTab to crunchyrollTab()
	if theTab is missing value then return "no-tab"
	tell application "Safari" to do JavaScript "try{localStorage.removeItem('crsr-bridge-ts')}catch(e){}" in theTab
	return "ok"
end clearBridge

-- "enabled", "disabled", "no-window", "not-running" or "error:<number>:<message>"
on probeSafariJavaScript()
	if not (application "Safari" is running) then return "not-running"
	try
		tell application "Safari"
			if (count of windows) is 0 then return "no-window"
			do JavaScript "1" in current tab of front window
		end tell
		return "enabled"
	on error errMsg number errNum
		if errNum is 8 or errMsg contains "Apple Events" then return "disabled"
		if errNum is -1743 then return "not-authorized"
		return "error:" & errNum & ":" & errMsg
	end try
end probeSafariJavaScript

-- "enabled", "disabled", "not-authorized" or "not-running". Speaks theText when control is available.
on probeVoiceOver(theText)
	if not (application "VoiceOver" is running) then return "not-running"
	try
		tell application "VoiceOver" to output theText
		return "enabled"
	on error errMsg number errNum
		if errNum is -1743 then return "not-authorized"
		return "disabled"
	end try
end probeVoiceOver

-- JSON state of the userscript on the current Crunchyroll tab, or "" when unavailable.
on scriptState()
	set theTab to crunchyrollTab()
	if theTab is missing value then return ""
	tell application "Safari" to set r to do JavaScript stateJS in theTab
	if r is missing value then return ""
	return r as text
end scriptState

on openInSafari(theURL)
	tell application "Safari"
		activate
		if (count of windows) is 0 then
			make new document with properties {URL:theURL}
		else
			set URL of current tab of front window to theURL
		end if
	end tell
	return "ok"
end openInSafari

on activateSafari()
	if application "Safari" is running then tell application "Safari" to activate
	return "ok"
end activateSafari
