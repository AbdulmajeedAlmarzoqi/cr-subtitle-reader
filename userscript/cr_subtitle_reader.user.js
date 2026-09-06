// ==UserScript==
// @name         CR Subtitle Reader
// @namespace    https://github.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader
// @version      1.0.2
// @description  Reads Crunchyroll subtitles aloud for VoiceOver users on Safari (ARIA live region + AppleScript bridge).
// @author       Abdulmajeed Almarzoqi
// @license      GPL-3.0-or-later
// @homepageURL  https://github.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader
// @supportURL   https://github.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader/issues
// @updateURL    https://raw.githubusercontent.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader/main/userscript/cr_subtitle_reader.meta.js
// @downloadURL  https://raw.githubusercontent.com/AbdulmajeedAlmarzoqi/cr-subtitle-reader/main/userscript/cr_subtitle_reader.user.js
// @match        https://www.crunchyroll.com/*
// @match        https://beta.crunchyroll.com/*
// @match        https://static.crunchyroll.com/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==

/*
 * CR Subtitle Reader — VoiceOver edition for Safari
 *
 * Credits
 *   - Based on the "Subtitle Reader" NVDA add-on by 福恩 (Maxe Hsieh):
 *     https://github.com/maxe-hsieh/subtitle_reader
 *   - The Crunchyroll technique (intercepting the /playback/ response, fetching the
 *     ASS subtitle file and exposing the active line to the screen reader) was found
 *     and implemented for NVDA by PlatinumTsuki (subtitle_reader pull request #58).
 *   - VoiceOver edition, Safari userscript and AppleScript by Abdulmajeed Almarzoqi.
 *
 * How it works
 *   1. Crunchyroll draws subtitles on a canvas, so they never reach the accessibility
 *      tree. This script intercepts the /playback/ response, which lists the subtitle
 *      files (ASS) for every language, downloads the selected one and parses it.
 *   2. Every 150 ms it reads the video's current time and picks the active line.
 *   3. The line goes through the same de-duplication logic as the NVDA add-on
 *      (processSubtitle / filterSamePart) and is then announced:
 *        - Default: through an ARIA live region that VoiceOver reads automatically.
 *        - Bridge mode: while the CR Subtitle Reader app is running (it sends a
 *          heartbeat every ~200 ms) the live region is left alone and the text is
 *          written to localStorage, where the app picks it up and speaks it through
 *          VoiceOver's own "output" command (speech + braille, works in the background).
 *
 * Keyboard shortcuts inside the page (Option+Shift + key)
 *   Option+Shift+S  Toggle subtitle reading on/off
 *   Option+Shift+L  Cycle through the available subtitle languages
 *   Option+Shift+R  Repeat the current subtitle line
 *   Option+Shift+I  Interrupt mode on/off (assertive live region; VoiceOver adds a tone)
 */

(function () {
	'use strict';

	// ===================== Settings =====================
	var TICK_MS = 150;                  // how often the video time is checked
	// 'polite' announces without any VoiceOver sound effect. 'assertive' interrupts the line being
	// spoken (like NVDA) but VoiceOver on macOS plays a short tone before every assertive announcement.
	// Users can switch at runtime with Option+Shift+I; the choice is stored in localStorage (crsr-interrupt).
	var LIVE_POLITENESS = 'polite';
	var BRIDGE_TIMEOUT_MS = 2000;       // without an app heartbeat for this long, fall back to the live region
	var EMPTY_RESET_MS = 1000;          // silence needed before the same line may be announced again
	var ANNOUNCE_LOADED = true;         // announce when a subtitle file has been loaded
	var STATUS_HOLD_MS = 1500;          // after a status message, hold subtitles so the message can be heard
	var KEYS = { toggle: 'KeyS', language: 'KeyL', repeat: 'KeyR', interrupt: 'KeyI' };
	var SCRIPT_VERSION = '1.0.2';

	var STR = {
		on: 'Subtitle reading: on',
		off: 'Subtitle reading: off',
		noSub: 'No subtitle right now',
		noLangs: 'Subtitle language list not loaded yet',
		lang: 'Subtitle language: ',
		loaded: 'Subtitles loaded: ',
		loadFailed: 'Could not load the subtitle file',
		interruptOn: 'Interrupt mode on: new lines cut off the previous one, with a VoiceOver tone',
		interruptOff: 'Interrupt mode off: lines are read in turn, without a tone'
	};
	var UI_LANG = 'en';
	function T(key) { return STR[key]; }

	var LANG_NAMES = {
		'ar-SA': 'Arabic', 'ar-ME': 'Arabic (Middle East)', 'en-US': 'English', 'en-IN': 'English (India)',
		'es-419': 'Spanish (Latin America)', 'es-ES': 'Spanish (Spain)', 'fr-FR': 'French',
		'de-DE': 'German', 'it-IT': 'Italian', 'pt-BR': 'Portuguese (Brazil)', 'pt-PT': 'Portuguese (Portugal)',
		'ru-RU': 'Russian', 'ja-JP': 'Japanese', 'zh-CN': 'Chinese (Simplified)', 'zh-TW': 'Chinese (Traditional)',
		'zh-HK': 'Chinese (Hong Kong)', 'ko-KR': 'Korean', 'id-ID': 'Indonesian', 'ms-MY': 'Malay', 'th-TH': 'Thai',
		'vi-VN': 'Vietnamese', 'tr-TR': 'Turkish', 'pl-PL': 'Polish', 'hi-IN': 'Hindi', 'ta-IN': 'Tamil',
		'te-IN': 'Telugu', 'ca-ES': 'Catalan', 'uk-UA': 'Ukrainian'
	};
	function langName(code) { return LANG_NAMES[code] || code; }

	// Player menu text -> candidate language codes (fallback detection, as in the NVDA version)
	var LANG_MAP = {
		'العربية': ['ar-SA', 'ar-ME'], 'arabic': ['ar-SA', 'ar-ME'], 'arabe': ['ar-SA', 'ar-ME'],
		'english': ['en-US'], 'anglais': ['en-US'],
		'français': ['fr-FR'], 'french': ['fr-FR'], 'francais': ['fr-FR'],
		'deutsch': ['de-DE'], 'german': ['de-DE'],
		'español (américa latina)': ['es-419'], 'español (españa)': ['es-ES'],
		'italiano': ['it-IT'], 'português (brasil)': ['pt-BR'], 'português (portugal)': ['pt-PT'],
		'русский': ['ru-RU'], 'bahasa indonesia': ['id-ID'], 'bahasa melayu': ['ms-MY'],
		'tiếng việt': ['vi-VN'], 'ไทย': ['th-TH'], '中文 (简体)': ['zh-CN'], '中文 (繁体)': ['zh-HK', 'zh-TW'],
		'日本語': ['ja-JP'], '한국어': ['ko-KR'], 'türkçe': ['tr-TR'], 'polski': ['pl-PL']
	};

	// ===================== State =====================
	var isTop = (window === window.top);
	var instanceId = Math.random().toString(36).slice(2, 7);
	var seqCounter = 0;

	var subtitleCues = [];
	var allSubtitleUrls = {};   // lang -> { url, format }
	var currentLang = '';
	var profileLang = '';
	var audioLocale = '';
	var loadingLang = '';
	var currentUrl = location.href;

	var lastSubtitle = '';      // self.subtitle in the NVDA add-on
	var emptySubtitleTime = 0;  // self.emptySubtitleTime in the NVDA add-on
	var liveRegion = null;
	var pendingLiveTimer = null;
	var remoteBridgeActive = false;   // when the player lives in a cross-origin frame
	var lastEnabledSeen = null;
	var lastCmdSeen = '';
	var lastSettingsBroadcast = '';
	var statusHoldUntil = 0;

	// ===================== Storage =====================
	function getStore(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
	function setStore(key, value) { try { localStorage.setItem(key, String(value)); } catch (e) {} }

	function isEnabled() { return getStore('crsr-enabled') !== '0'; }
	function interruptMode() { return getStore('crsr-interrupt') === '1'; }
	function livePoliteness() { return interruptMode() ? 'assertive' : LIVE_POLITENESS; }
	function setEnabled(value) { setStore('crsr-enabled', value ? '1' : '0'); }

	function bridgeActive() {
		var ts = Number(getStore('crsr-bridge-ts') || 0);
		return remoteBridgeActive || (Date.now() - ts) < BRIDGE_TIMEOUT_MS;
	}

	// ===================== Helpers =====================
	function getVideo() {
		var vids = document.getElementsByTagName('video');
		if (!vids.length) return null;
		var best = vids[0];
		for (var i = 1; i < vids.length; i++) {
			if ((vids[i].duration || 0) > (best.duration || 0)) best = vids[i];
		}
		return best;
	}

	function hasCrunchyrollFrame() {
		var frames = document.getElementsByTagName('iframe');
		for (var i = 0; i < frames.length; i++) {
			if (/crunchyroll\.com/.test(frames[i].src || '')) return true;
		}
		return false;
	}

	// The instance that executes external commands and announces state changes
	function isExecutor() { return !!getVideo() || (isTop && !hasCrunchyrollFrame()); }

	function subtitleLangTag() { return currentLang || UI_LANG; }

	// ===================== ARIA live region =====================
	function ensureLiveRegion() {
		if (!document.body) return null;
		if (!liveRegion || !liveRegion.isConnected) {
			liveRegion = document.getElementById('crsr-live');
			if (!liveRegion) {
				liveRegion = document.createElement('div');
				liveRegion.id = 'crsr-live';
				liveRegion.setAttribute('aria-live', livePoliteness());
				liveRegion.setAttribute('aria-atomic', 'true');
				liveRegion.setAttribute('aria-relevant', 'additions text');
				// Visually hidden but still in the accessibility tree (never display:none)
				liveRegion.style.cssText = 'position:absolute !important;width:1px !important;height:1px !important;margin:-1px !important;padding:0 !important;overflow:hidden !important;clip:rect(0 0 0 0) !important;white-space:nowrap !important;border:0 !important;';
			}
		}
		// Keep the region inside the fullscreen element so VoiceOver still sees it in fullscreen
		var host = document.fullscreenElement || document.webkitFullscreenElement ||
			document.getElementById('player-container') || document.body;
		if (liveRegion.parentNode !== host) {
			liveRegion.textContent = '';
			host.appendChild(liveRegion);
		}
		return liveRegion;
	}

	function speakLive(msg, lang) {
		var region = ensureLiveRegion();
		if (!region) return;
		var politeness = livePoliteness();
		if (region.getAttribute('aria-live') !== politeness) region.setAttribute('aria-live', politeness);
		region.setAttribute('lang', lang || UI_LANG);
		// Clear first, then set the text a moment later so VoiceOver notices the change
		// even when the text is identical to the previous one (e.g. "repeat").
		region.textContent = '';
		if (pendingLiveTimer) clearTimeout(pendingLiveTimer);
		pendingLiveTimer = setTimeout(function () {
			pendingLiveTimer = null;
			region.textContent = msg;
		}, 30);
	}

	// ===================== Output =====================
	function publishToBridge(seq, msg) {
		setStore('crsr-msg', seq + '\t' + msg);
		if (!isTop) {
			try { window.top.postMessage({ type: 'crsr-msg', seq: seq, msg: msg }, '*'); } catch (e) {}
		}
	}

	function announce(msg, lang, isStatus) {
		msg = String(msg || '').replace(/[\t\r\n]+/g, ' ').trim();
		if (!msg) return;
		if (isStatus) statusHoldUntil = Date.now() + STATUS_HOLD_MS;
		seqCounter += 1;
		var seq = instanceId + '-' + seqCounter;
		publishToBridge(seq, msg);
		if (!bridgeActive()) speakLive(msg, lang);
	}

	// ===================== ASS parser (ported from the NVDA userscript) =====================
	function toSeconds(parts) {
		var sec = parts[2].split('.');
		return parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60 + parseInt(sec[0], 10) +
			(sec.length > 1 ? parseInt(sec[1], 10) / 100 : 0);
	}

	function parseASS(assText) {
		var cues = [];
		var lines = assText.split('\n');
		var inEvents = false;
		var formatFields = [];

		for (var i = 0; i < lines.length; i++) {
			var line = lines[i].trim();
			if (line === '[Events]') { inEvents = true; continue; }
			if (/^\[.+\]$/.test(line)) { inEvents = false; continue; }
			if (!inEvents) continue;

			if (line.indexOf('Format:') === 0) {
				formatFields = line.substring(7).split(',').map(function (f) { return f.trim(); });
				continue;
			}
			if (line.indexOf('Dialogue:') !== 0) continue;

			var data = line.substring(9);
			var parts = [];
			var current = data;
			for (var s = 0; s < formatFields.length - 1; s++) {
				var commaIdx = current.indexOf(',');
				if (commaIdx === -1) break;
				parts.push(current.substring(0, commaIdx).trim());
				current = current.substring(commaIdx + 1);
			}
			parts.push(current);

			var startIdx = formatFields.indexOf('Start');
			var endIdx = formatFields.indexOf('End');
			var textIdx = formatFields.indexOf('Text');
			var styleIdx = formatFields.indexOf('Style');
			if (startIdx === -1 || endIdx === -1 || textIdx === -1) continue;

			var style = styleIdx !== -1 ? (parts[styleIdx] || '').toLowerCase() : '';
			// Skip signs and on-screen text, as the NVDA version does
			if (style.indexOf('sign') !== -1 || style.indexOf('screen') !== -1 || style.indexOf('caption') !== -1) continue;

			var rawText = parts[textIdx] || '';
			// Drawing commands (\p1) produce coordinates, not text
			if (/\\p[1-9]/.test(rawText)) continue;

			var text = rawText.replace(/\{[^}]*\}/g, '').replace(/\\[Nn]/g, ' | ').replace(/\\h/g, ' ').replace(/\s+/g, ' ').trim();
			if (!text) continue;

			var startParts = parts[startIdx].split(':');
			var endParts = parts[endIdx].split(':');
			if (startParts.length !== 3 || endParts.length !== 3) continue;

			cues.push({ start: toSeconds(startParts), end: toSeconds(endParts), text: text });
		}
		cues.sort(function (a, b) { return a.start - b.start; });
		return cues;
	}

	// ===================== VTT parser (closed captions) =====================
	function vttTime(str) {
		var p = str.trim().split(':');
		var secs = 0;
		for (var i = 0; i < p.length; i++) secs = secs * 60 + parseFloat(p[i]);
		return secs;
	}

	function parseVTT(vttText) {
		var cues = [];
		var blocks = vttText.replace(/\r/g, '').split(/\n\n+/);
		for (var i = 0; i < blocks.length; i++) {
			var lines = blocks[i].split('\n');
			var timeLineIdx = -1;
			for (var j = 0; j < lines.length; j++) {
				if (lines[j].indexOf('-->') !== -1) { timeLineIdx = j; break; }
			}
			if (timeLineIdx === -1) continue;
			var times = lines[timeLineIdx].split('-->');
			if (times.length < 2) continue;
			var text = lines.slice(timeLineIdx + 1).join(' | ').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
			if (!text) continue;
			cues.push({ start: vttTime(times[0]), end: vttTime(times[1].split(' ')[0]), text: text });
		}
		cues.sort(function (a, b) { return a.start - b.start; });
		return cues;
	}

	// ===================== Subtitle loading =====================
	function loadSubtitle(lang, announceIt) {
		if (!lang || !allSubtitleUrls[lang]) return;
		var entry = allSubtitleUrls[lang];
		loadingLang = lang;
		fetch(entry.url).then(function (r) { return r.text(); }).then(function (text) {
			if (loadingLang !== lang) return; // another language was requested meanwhile
			var cues;
			if (text.indexOf('[Events]') !== -1) cues = parseASS(text);
			else if (/^\s*WEBVTT/.test(text) || (entry.format || '').toLowerCase() === 'vtt') cues = parseVTT(text);
			else cues = [];
			if (!cues.length) { announce(T('loadFailed'), UI_LANG, true); return; }
			subtitleCues = cues;
			lastSubtitle = '';
			emptySubtitleTime = 0;
			var changed = currentLang !== lang;
			currentLang = lang;
			if (lang !== 'auto') setStore('crsr-lang', lang);
			if (announceIt) announce(T('lang') + langName(lang), UI_LANG, true);
			else if (ANNOUNCE_LOADED && changed) announce(T('loaded') + langName(lang), UI_LANG, true);
		}).catch(function () { announce(T('loadFailed'), UI_LANG, true); });
	}

	function pickCandidate(candidates) {
		if (!candidates) return null;
		if (typeof candidates === 'string') candidates = [candidates];
		for (var i = 0; i < candidates.length; i++) {
			if (allSubtitleUrls[candidates[i]]) return candidates[i];
		}
		// Match on the language part only ("ar" of "ar-SA")
		for (var j = 0; j < candidates.length; j++) {
			var base = String(candidates[j]).split('-')[0].toLowerCase();
			var keys = Object.keys(allSubtitleUrls);
			for (var k = 0; k < keys.length; k++) {
				if (keys[k].split('-')[0].toLowerCase() === base) return keys[k];
			}
		}
		return null;
	}

	function chooseLanguage() {
		var keys = Object.keys(allSubtitleUrls);
		if (!keys.length) return null;
		return pickCandidate(currentLang) ||
			pickCandidate(getStore('crsr-lang')) ||
			pickCandidate(profileLang) ||
			pickCandidate(navigator.language) ||
			keys[0];
	}

	// ===================== Language detection from the player menu (fallback) =====================
	function textToLangCode(text) {
		if (!text) return null;
		text = text.toLowerCase().trim();
		if (LANG_MAP[text]) return pickCandidate(LANG_MAP[text]);
		var keys = Object.keys(LANG_MAP);
		for (var i = 0; i < keys.length; i++) {
			if (text.indexOf(keys[i]) !== -1) return pickCandidate(LANG_MAP[keys[i]]);
		}
		return null;
	}

	function detectLangFromDOM() {
		var player = document.getElementById('player-container');
		if (!player) return null;
		var selectors = '[aria-checked="true"], [aria-selected="true"], [data-selected="true"]';
		var candidates = player.querySelectorAll(selectors);
		for (var i = 0; i < candidates.length; i++) {
			var lang = textToLangCode(candidates[i].textContent);
			// Ignore matches equal to the audio language so the audio menu is not mistaken for the subtitle menu
			if (lang && lang !== audioLocale) return lang;
		}
		return null;
	}

	function startLangObserver() {
		var player = document.getElementById('player-container');
		if (!player) { setTimeout(startLangObserver, 2000); return; }
		var debounceTimer = null;
		new MutationObserver(function () {
			if (debounceTimer) clearTimeout(debounceTimer);
			debounceTimer = setTimeout(function () {
				var lang = detectLangFromDOM();
				if (lang && lang !== currentLang && allSubtitleUrls[lang]) loadSubtitle(lang, false);
			}, 800);
		}).observe(player, {
			childList: true, subtree: true, attributes: true,
			attributeFilter: ['aria-checked', 'aria-selected', 'data-selected']
		});
	}

	// ===================== Network interception =====================
	function isProfileUrl(url) { return /\/accounts\/v1\/me\/(multiprofile|profile)/.test(url); }
	function isInterestingUrl(url) { return url.indexOf('/playback/') !== -1 || isProfileUrl(url); }

	function handleProfileData(data) {
		if (!data || typeof data !== 'object') return;
		var lang = data.preferred_content_subtitle_language;
		if (!lang && Array.isArray(data.profiles)) {
			var selected = null;
			for (var i = 0; i < data.profiles.length; i++) {
				if (data.profiles[i] && data.profiles[i].is_selected) { selected = data.profiles[i]; break; }
			}
			selected = selected || data.profiles[0];
			lang = selected && selected.preferred_content_subtitle_language;
		}
		if (typeof lang === 'string' && lang) {
			var changed = profileLang && profileLang !== lang;
			profileLang = lang;
			if (changed && allSubtitleUrls[lang] && lang !== currentLang) loadSubtitle(lang, false);
		}
	}

	function handleJsonResponse(url, data) {
		if (!data || typeof data !== 'object') return;
		if (url.indexOf('/playback/') !== -1) {
			var subtitles = data.subtitles || (data.meta && data.meta.subtitles) || {};
			var keys = Object.keys(subtitles);
			if (!keys.length && data.captions) { subtitles = data.captions; keys = Object.keys(subtitles); }
			if (!keys.length) return;
			allSubtitleUrls = {};
			for (var i = 0; i < keys.length; i++) {
				var entry = subtitles[keys[i]];
				if (entry && entry.url) allSubtitleUrls[keys[i]] = { url: entry.url, format: entry.format || '' };
			}
			audioLocale = data.audioLocale || data.audio_locale || audioLocale;
			var lang = chooseLanguage();
			if (lang) loadSubtitle(lang, false);
		} else if (isProfileUrl(url)) {
			handleProfileData(data);
		}
	}

	function handleRequestBody(url, method, body) {
		if (!isProfileUrl(url) || !/^(PATCH|PUT|POST)$/i.test(method || '')) return;
		try {
			if (typeof body === 'string') handleProfileData(JSON.parse(body));
		} catch (e) {}
	}

	var _origFetch = window.fetch;
	window.fetch = function (input, init) {
		var url = '';
		try { url = typeof input === 'string' ? input : (input && input.url ? input.url : ''); } catch (e) {}
		if (url && isInterestingUrl(url)) {
			try { handleRequestBody(url, (init && init.method) || (input && input.method) || 'GET', init && init.body); } catch (e) {}
			return _origFetch.apply(this, arguments).then(function (response) {
				try {
					response.clone().json().then(function (data) { handleJsonResponse(url, data); }).catch(function () {});
				} catch (e) {}
				return response;
			});
		}
		return _origFetch.apply(this, arguments);
	};

	var _xhrOpen = XMLHttpRequest.prototype.open;
	XMLHttpRequest.prototype.open = function (method, url) {
		try { this.__crsrUrl = String(url); this.__crsrMethod = String(method); } catch (e) {}
		return _xhrOpen.apply(this, arguments);
	};
	var _xhrSend = XMLHttpRequest.prototype.send;
	XMLHttpRequest.prototype.send = function (body) {
		try {
			var xhr = this;
			var url = xhr.__crsrUrl || '';
			if (url && isInterestingUrl(url)) {
				handleRequestBody(url, xhr.__crsrMethod, body);
				xhr.addEventListener('load', function () {
					try {
						var data = null;
						if (xhr.responseType === '' || xhr.responseType === 'text') data = JSON.parse(xhr.responseText);
						else if (xhr.responseType === 'json') data = xhr.response;
						handleJsonResponse(url, data);
					} catch (e) {}
				});
			}
		} catch (e) {}
		return _xhrSend.apply(this, arguments);
	};

	// Fallback: follow ASS files the player itself loads (reflects the language chosen in the player)
	function stripQuery(u) { return String(u).split('?')[0]; }
	function onResourceEntry(name) {
		if (!/\.ass(\?|$)/i.test(name)) return;
		var keys = Object.keys(allSubtitleUrls);
		for (var i = 0; i < keys.length; i++) {
			if (stripQuery(allSubtitleUrls[keys[i]].url) === stripQuery(name)) {
				if (keys[i] !== currentLang) loadSubtitle(keys[i], false);
				return;
			}
		}
		if (!subtitleCues.length && !loadingLang) {
			allSubtitleUrls['auto'] = { url: name, format: 'ass' };
			loadSubtitle('auto', false);
		}
	}
	try {
		new PerformanceObserver(function (list) {
			var entries = list.getEntries();
			for (var i = 0; i < entries.length; i++) onResourceEntry(entries[i].name);
		}).observe({ type: 'resource', buffered: true });
	} catch (e) {}

	// ===================== Single-page navigation =====================
	function checkNavigation() {
		if (location.href !== currentUrl) {
			currentUrl = location.href;
			subtitleCues = [];
			allSubtitleUrls = {};
			lastSubtitle = '';
			emptySubtitleTime = 0;
			loadingLang = '';
			// currentLang is kept as the preference for the next episode
		}
	}
	var _origPushState = history.pushState;
	var _origReplaceState = history.replaceState;
	history.pushState = function () { var r = _origPushState.apply(this, arguments); checkNavigation(); return r; };
	history.replaceState = function () { var r = _origReplaceState.apply(this, arguments); checkNavigation(); return r; };
	window.addEventListener('popstate', checkNavigation);

	// ===================== De-duplication (ported from the NVDA add-on) =====================
	function filterSamePart(subtitle) {
		var parts = subtitle.split(' | ');
		var newParts = [];
		for (var i = 0; i < parts.length; i++) {
			var part = parts[i];
			var ps = part.trim();
			var duplicate = false;
			for (var j = 0; j < newParts.length; j++) {
				var s = newParts[j].trim();
				if (s.indexOf(ps) !== -1 || ps === s) { duplicate = true; break; }
			}
			if (duplicate) continue;
			for (var k = 0; k < newParts.length; k++) {
				if (ps.indexOf(newParts[k].trim()) !== -1) { newParts.splice(k, 1); break; }
			}
			newParts.push(part);
		}
		return newParts.join(' | ');
	}

	function processSubtitle(subtitle) {
		// Remove characters used only for subtitle rendering
		subtitle = subtitle.replace(/\u200b/g, '').replace(/\u00a0/g, ' ');
		subtitle = filterSamePart(subtitle);
		var now = Date.now();

		if (!subtitle) {
			// Only forget the last line after a second of silence
			if (!emptySubtitleTime) emptySubtitleTime = now;
			else if (now - emptySubtitleTime >= EMPTY_RESET_MS) lastSubtitle = '';
			return;
		}
		emptySubtitleTime = 0;
		if (subtitle === lastSubtitle) return;

		var lastSubtitleText = lastSubtitle.split(' | ').join(' ');
		var subtitleText = subtitle.split(' | ').join(' ');
		lastSubtitle = subtitle;

		var msg = subtitleText;
		// The new line is part of the previous one: say nothing
		if (lastSubtitleText && lastSubtitleText.indexOf(subtitleText) !== -1) msg = '';
		// The new line contains the previous one: say only the added part
		if (lastSubtitleText && subtitleText.indexOf(lastSubtitleText) !== -1) msg = subtitleText.replace(lastSubtitleText, '');
		// Drop parts shared with the previous line
		var split = subtitle.split(' | ');
		for (var i = 0; i < split.length; i++) {
			var part = split[i];
			if (part && lastSubtitleText && lastSubtitleText.indexOf(part) !== -1) msg = msg.split(part).join('');
		}
		msg = msg.trim();
		if (!msg) return;
		announce(msg, subtitleLangTag());
	}

	// ===================== Commands =====================
	function toggleEnabled() { setEnabledAndAnnounce(!isEnabled()); }

	function setEnabledAndAnnounce(enabled) {
		setEnabled(enabled);
		lastEnabledSeen = enabled;
		if (!enabled) { lastSubtitle = ''; emptySubtitleTime = 0; }
		announce(enabled ? T('on') : T('off'), UI_LANG, true);
		broadcastSettings(true);
	}

	function cycleLanguage() {
		var langs = Object.keys(allSubtitleUrls).filter(function (k) { return k !== 'auto'; });
		if (!langs.length) { announce(T('noLangs'), UI_LANG, true); return; }
		var idx = (langs.indexOf(currentLang) + 1) % langs.length;
		loadSubtitle(langs[idx], true);
	}

	function repeatSubtitle() {
		if (lastSubtitle) announce(lastSubtitle.split(' | ').join(' '), subtitleLangTag());
		else announce(T('noSub'), UI_LANG, true);
	}

	function toggleInterrupt() {
		var on = !interruptMode();
		setStore('crsr-interrupt', on ? '1' : '0');
		announce(on ? T('interruptOn') : T('interruptOff'), UI_LANG, true);
	}

	function runCommand(cmd) {
		if (cmd === 'toggle') toggleEnabled();
		else if (cmd === 'interrupt') toggleInterrupt();
		else if (cmd === 'mute') setEnabledAndAnnounce(false);
		else if (cmd === 'unmute') setEnabledAndAnnounce(true);
		else if (cmd === 'language') cycleLanguage();
		else if (cmd === 'repeat') repeatSubtitle();
	}

	// Commands from the app / AppleScript arrive through localStorage as "command<tab>timestamp":
	// toggle, mute, unmute, language, repeat, interrupt
	function pollExternalCommand(cmdValue) {
		if (!cmdValue || cmdValue === lastCmdSeen) return false;
		lastCmdSeen = cmdValue;
		var parts = cmdValue.split('\t');
		var ts = Number(parts[1] || 0);
		if (!ts || Date.now() - ts > 5000) return false; // stale command
		if (!isExecutor()) return false;
		runCommand(parts[0]);
		return true;
	}

	window.addEventListener('keydown', function (e) {
		if (!e.altKey || !e.shiftKey || e.ctrlKey || e.metaKey) return;
		var t = e.target;
		if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
		if (e.code === KEYS.toggle) toggleEnabled();
		else if (e.code === KEYS.language) cycleLanguage();
		else if (e.code === KEYS.repeat) repeatSubtitle();
		else if (e.code === KEYS.interrupt) toggleInterrupt();
		else return;
		e.preventDefault();
		e.stopPropagation();
	}, true);

	// ===================== Cross-frame messaging =====================
	function fromCrunchyroll(origin) {
		try { return /(^|\.)crunchyroll\.com$/.test(new URL(origin).hostname); } catch (e) { return false; }
	}

	function broadcastSettings(force) {
		var payload = {
			type: 'crsr-settings',
			enabled: isEnabled() ? '1' : '0',
			bridgeActive: bridgeActive(),
			cmd: getStore('crsr-cmd') || ''
		};
		var key = payload.enabled + '|' + payload.bridgeActive + '|' + payload.cmd;
		if (!force && key === lastSettingsBroadcast) return;
		lastSettingsBroadcast = key;
		var frames = document.getElementsByTagName('iframe');
		for (var i = 0; i < frames.length; i++) {
			try { if (frames[i].contentWindow) frames[i].contentWindow.postMessage(payload, '*'); } catch (e) {}
		}
		if (!isTop) {
			try { window.top.postMessage(payload, '*'); } catch (e) {}
		}
	}

	window.addEventListener('message', function (e) {
		var d = e.data;
		if (!d || typeof d !== 'object' || typeof d.type !== 'string' || d.type.indexOf('crsr-') !== 0) return;
		if (!fromCrunchyroll(e.origin)) return;
		if (d.type === 'crsr-msg') {
			if (isTop) setStore('crsr-msg', d.seq + '\t' + d.msg);
		} else if (d.type === 'crsr-settings') {
			var enabledStr = d.enabled === '0' ? '0' : '1';
			if ((getStore('crsr-enabled') || '1') !== enabledStr) {
				setStore('crsr-enabled', enabledStr);
				lastEnabledSeen = enabledStr === '1';
				if (isTop) broadcastSettings(true);
			}
			if (!isTop) {
				remoteBridgeActive = !!d.bridgeActive;
				if (d.cmd) pollExternalCommand(d.cmd);
			}
		}
	});

	// ===================== Main loop =====================
	setInterval(function () {
		checkNavigation();
		setStore('crsr-heartbeat', Date.now());

		// The enabled flag changed externally (e.g. from the app)
		var enabled = isEnabled();
		if (lastEnabledSeen === null) lastEnabledSeen = enabled;
		else if (enabled !== lastEnabledSeen) {
			lastEnabledSeen = enabled;
			if (!enabled) { lastSubtitle = ''; emptySubtitleTime = 0; }
			if (isExecutor()) announce(enabled ? T('on') : T('off'), UI_LANG, true);
		}

		// Stop here when an external command ran, so its status message is not overwritten
		if (pollExternalCommand(getStore('crsr-cmd'))) return;
		if (isTop) broadcastSettings(false);

		if (!enabled || !subtitleCues.length) return;
		if (Date.now() < statusHoldUntil) return;
		var video = getVideo();
		if (!video) return;

		var t = video.currentTime;
		var texts = [];
		for (var i = 0; i < subtitleCues.length; i++) {
			var cue = subtitleCues[i];
			if (cue.start <= t && cue.end >= t && texts.indexOf(cue.text) === -1) texts.push(cue.text);
			if (cue.start > t) break;
		}
		var raw = texts.join(' | ');
		setStore('crsr-last', raw.split(' | ').join(' '));
		processSubtitle(raw);
	}, TICK_MS);

	document.addEventListener('fullscreenchange', function () { if (liveRegion) ensureLiveRegion(); });
	document.addEventListener('webkitfullscreenchange', function () { if (liveRegion) ensureLiveRegion(); });

	// ===================== Read-only diagnostics (browser console or the app) =====================
	window.__crsrDebug = {
		get state() {
			return {
				version: SCRIPT_VERSION, isTop: isTop, enabled: isEnabled(), bridgeActive: bridgeActive(),
				interrupt: interruptMode(), politeness: livePoliteness(),
				currentLang: currentLang, profileLang: profileLang, audioLocale: audioLocale,
				langs: Object.keys(allSubtitleUrls), cues: subtitleCues.length, lastSubtitle: lastSubtitle,
				hasVideo: !!getVideo(), videoTime: getVideo() ? getVideo().currentTime : null,
				liveRegion: !!(liveRegion && liveRegion.isConnected), url: currentUrl
			};
		}
	};

	setTimeout(startLangObserver, 3000);
})();
