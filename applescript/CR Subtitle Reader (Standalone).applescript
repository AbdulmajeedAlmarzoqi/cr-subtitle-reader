(*
	CR Subtitle Reader — Standalone stay-open reader
	Developed by Abdulmajeed Almarzoqi. License: GPL-3.0-or-later.

	The CR Subtitle Reader app embeds this logic; this file is for people who prefer a
	plain AppleScript applet. Save it as a stay-open application (Script Editor:
	File > Export, File Format: Application, "Stay open after run handler"), or build it with:
	    osacompile -s -o "CR Subtitle Reader (Standalone).app" "CR Subtitle Reader (Standalone).applescript"

	Every 0.2 s it reads the newest subtitle line written by the CR Subtitle Reader userscript
	(localStorage key crsr-msg) in the Crunchyroll tab of Safari's front window and speaks it
	through VoiceOver's "output" command. While it runs, the userscript stops using its ARIA
	live region so nothing is spoken twice. Quit with Command+Q.

	Requirements: see CRSubtitleReaderBridge.applescript.
*)

property pollInterval : 0.2
property idleInterval : 1.5
property useSystemVoiceFallback : true
property warningCooldown : 60

property lastSeq : ""
property primed : false
property lastNoScriptWarning : missing value
property lastJsWarning : missing value
property voWarned : false

property bridgeJS : "(function(){try{var now=Date.now();localStorage.setItem('crsr-bridge-ts',String(now));var hb=Number(localStorage.getItem('crsr-heartbeat')||0);var age=hb?(now-hb):-1;var w=location.pathname.indexOf('/watch/')!==-1?1:0;var m=localStorage.getItem('crsr-msg')||'\\t';return w+'\\t'+age+'\\t'+m}catch(e){return ''}})()"

on run
	set primed to false
	set lastSeq to ""
	speak("CR Subtitle Reader started. Open an episode in Safari and I will read its subtitles.")
	if application "Safari" is running then tell application "Safari" to activate
end run

on reopen
	speak("CR Subtitle Reader is already running.")
end reopen

on quit
	clearBridge()
	speak("CR Subtitle Reader stopped.")
	continue quit
end quit

on idle
	set payload to ""
	try
		set payload to readBridge()
	on error errMsg number errNum
		if errNum is 8 or errMsg contains "Apple Events" then
			warnJavaScriptDisabled()
			return 5
		end if
		return 2
	end try
	if payload is "" then return idleInterval

	set parts to splitText(payload, tab)
	if (count of parts) < 4 then return pollInterval
	set isWatchPage to item 1 of parts
	set heartbeatAge to item 2 of parts
	set seq to item 3 of parts
	set msg to item 4 of parts
	if (count of parts) > 4 then set msg to joinText(items 4 thru -1 of parts, " ")

	if isWatchPage is "1" then
		set ageNumber to -1
		try
			set ageNumber to heartbeatAge as number
		end try
		if ageNumber < 0 or ageNumber > 5000 then warnNoScript()
	end if

	if not primed then
		set primed to true
		set lastSeq to seq
		return pollInterval
	end if

	if seq is not "" and seq is not lastSeq then
		set lastSeq to seq
		speak(msg)
	end if
	return pollInterval
end idle

on readBridge()
	if not (application "Safari" is running) then return ""
	tell application "Safari"
		if (count of windows) is 0 then return ""
		set theTab to current tab of front window
		set theURL to URL of theTab
		if theURL is missing value then return ""
		if theURL does not contain "crunchyroll.com" then return ""
		set jsResult to do JavaScript bridgeJS in theTab
	end tell
	if jsResult is missing value then return ""
	return jsResult as text
end readBridge

on clearBridge()
	try
		if not (application "Safari" is running) then return
		tell application "Safari"
			if (count of windows) is 0 then return
			set theTab to current tab of front window
			set theURL to URL of theTab
			if theURL is missing value then return
			if theURL does not contain "crunchyroll.com" then return
			do JavaScript "try{localStorage.removeItem('crsr-bridge-ts')}catch(e){}" in theTab
		end tell
	end try
end clearBridge

on speak(theText)
	if theText is "" then return
	if application "VoiceOver" is running then
		try
			tell application "VoiceOver" to output theText
			return
		on error
			if not voWarned then
				set voWarned to true
				display notification "Enable \"Allow VoiceOver to be controlled with AppleScript\" in VoiceOver Utility > General." with title "CR Subtitle Reader"
			end if
		end try
	end if
	if useSystemVoiceFallback then say theText without waiting until completion
end speak

on warnJavaScriptDisabled()
	if lastJsWarning is not missing value and ((current date) - lastJsWarning) < warningCooldown then return
	set lastJsWarning to current date
	speak("Safari is blocking JavaScript from Apple Events. Enable it in Safari Settings, Developer tab.")
end warnJavaScriptDisabled

on warnNoScript()
	if lastNoScriptWarning is not missing value and ((current date) - lastNoScriptWarning) < warningCooldown then return
	set lastNoScriptWarning to current date
	speak("The CR Subtitle Reader script is not running on this page. Make sure the Userscripts extension is enabled for crunchyroll.com.")
end warnNoScript

on splitText(theText, delimiter)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiter
	set theItems to text items of theText
	set AppleScript's text item delimiters to oldDelimiters
	return theItems
end splitText

on joinText(theItems, delimiter)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiter
	set theText to theItems as text
	set AppleScript's text item delimiters to oldDelimiters
	return theText
end joinText
