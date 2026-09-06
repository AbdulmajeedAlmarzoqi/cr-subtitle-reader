import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var channelMenuItem: NSMenuItem?
    private var muteMenuItem: NSMenuItem?
    private var backgroundMenuItem: NSMenuItem?
    private var actionsMuteItem: NSMenuItem?
    private var actionsBackgroundItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    private var state: AppState { AppState.shared }

    // MARK: Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Launched \(AppInfo.name) \(AppInfo.version) from \(Bundle.main.bundleURL.path); bridge loaded: \(state.bridge.isLoaded)")
        if state.stayInMenuBar { installStatusItem() }
        state.$stayInMenuBar
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] stay in
                if stay { self?.installStatusItem() } else { self?.removeStatusItem() }
            }
            .store(in: &cancellables)

        state.updates.$showUpdateWindow
            .receive(on: RunLoop.main)
            .sink { show in
                if show { AppWindows.openUpdate() } else { AppWindows.closeUpdate() }
            }
            .store(in: &cancellables)

        if state.setupCompleted {
            if Relocator.shouldOffer && !LaunchOptions.skipRelocation { offerMoveToApplications() }
            // A newer script shipped with this build? Refresh the copy inside the extension quietly.
            state.checker.refreshLocal()
            if state.checker.scriptInstalled && !state.checker.scriptUpToDate { state.installScript(quiet: true) }
            if state.stayInMenuBar {
                // Later launches: no window, one word from VoiceOver, then wait in the menu bar.
                state.sayReady()
                if UserDefaults.standard.bool(forKey: PrefKey.startReadingOnLaunch) {
                    state.reader.start(announce: false)
                }
            } else {
                // Plain setup tool: show the status window; closing it quits.
                AppWindows.showMain()
            }
        } else {
            AppWindows.showMain()
        }
        state.updates.startAutomaticChecks()
    }

    /// With the status item, closing or minimizing windows never quits (Command+Q does).
    /// Without it, the app is a plain tool and quits together with its last window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !state.stayInMenuBar
    }

    /// Dock click or opening the app again shows the window. (The status item counts as a
    /// visible window, so the flag is not reliable here.)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !AppWindows.isMainVisible { AppWindows.showMain() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            URLCommands.handle(url, state: state)
        }
    }

    /// Quit safely: stop background reading and hand the page back to its live region.
    func applicationWillTerminate(_ notification: Notification) {
        state.reader.stop(announce: false)
        Log.info("Terminated")
    }

    // MARK: Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.addItem(withTitle: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let updates = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "u")
        updates.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(AppInfo.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addSubmenu(appMenu)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open \(AppInfo.name) Window", action: #selector(showMainWindow), keyEquivalent: "1")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addSubmenu(fileMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addSubmenu(editMenu)

        let actionsMenu = NSMenu(title: "Actions")
        actionsMenu.delegate = self
        actionsMuteItem = actionsMenu.addItem(withTitle: "Mute Subtitles", action: #selector(pageToggle), keyEquivalent: "m")
        actionsMuteItem?.keyEquivalentModifierMask = [.command, .shift]
        actionsBackgroundItem = actionsMenu.addItem(withTitle: "Speak in Background", action: #selector(toggleReading), keyEquivalent: "b")
        actionsBackgroundItem?.keyEquivalentModifierMask = [.command, .shift]
        actionsMenu.addItem(.separator())
        actionsMenu.addItem(withTitle: "Next Subtitle Language", action: #selector(pageLanguage), keyEquivalent: "")
        actionsMenu.addItem(withTitle: "Repeat Current Line", action: #selector(pageRepeat), keyEquivalent: "")
        actionsMenu.addItem(.separator())
        actionsMenu.addItem(withTitle: "Open Crunchyroll in Safari", action: #selector(openCrunchyroll), keyEquivalent: "")
        actionsMenu.addItem(withTitle: "Run Setup Assistant Again", action: #selector(rerunSetup), keyEquivalent: "")
        mainMenu.addSubmenu(actionsMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        mainMenu.addSubmenu(windowMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "\(AppInfo.name) on GitHub", action: #selector(openRepository), keyEquivalent: "?")
        helpMenu.addItem(withTitle: "Report a Problem…", action: #selector(openIssues), keyEquivalent: "")
        mainMenu.addSubmenu(helpMenu)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: AppInfo.name)
            button.setAccessibilityLabel(AppInfo.name)
            button.toolTip = AppInfo.name
        }
        let menu = NSMenu()
        menu.delegate = self
        channelMenuItem = menu.addItem(withTitle: "Now: checking…", action: nil, keyEquivalent: "")
        channelMenuItem?.isEnabled = false
        menu.addItem(.separator())
        muteMenuItem = menu.addItem(withTitle: "Mute Subtitles", action: #selector(pageToggle), keyEquivalent: "")
        backgroundMenuItem = menu.addItem(withTitle: "Speak in Background", action: #selector(toggleReading), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Next Subtitle Language", action: #selector(pageLanguage), keyEquivalent: "")
        menu.addItem(withTitle: "Repeat Current Line", action: #selector(pageRepeat), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Crunchyroll in Safari", action: #selector(openCrunchyroll), keyEquivalent: "")
        menu.addItem(withTitle: "Open \(AppInfo.name)", action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = menuItem.action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        }
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    /// Refreshes the dynamic items right before a menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        state.checker.probeScript()
        let muted = state.checker.pageReadingEnabled == false
        let muteTitle = muted ? "Unmute Subtitles" : "Mute Subtitles"
        let backgroundOn = state.reader.isRunning
        for item in [muteMenuItem, actionsMuteItem] { item?.title = muteTitle }
        for item in [backgroundMenuItem, actionsBackgroundItem] { item?.state = backgroundOn ? .on : .off }
        channelMenuItem?.title = "Now: \(state.channelDescription)"
    }

    // MARK: Actions

    @objc private func showAbout() { AppWindows.openAbout() }
    @objc private func showSettings() { AppWindows.openSettings() }
    @objc private func showMainWindow() { AppWindows.showMain() }
    @objc private func checkForUpdates() { Task { await state.updates.check(userInitiated: true) } }
    @objc private func toggleReading() { state.reader.toggle() }
    @objc private func pageToggle() { state.toggleMutePage() }
    @objc private func pageLanguage() { state.sendPageCommand("language", label: "the language command") }
    @objc private func pageRepeat() { state.sendPageCommand("repeat", label: "the repeat command") }
    @objc private func openCrunchyroll() { state.checker.openInSafari(AppInfo.crunchyrollURL) }
    @objc private func rerunSetup() { state.rerunSetup() }
    @objc private func openRepository() { NSWorkspace.shared.open(AppInfo.repositoryURL) }
    @objc private func openIssues() { NSWorkspace.shared.open(AppInfo.issuesURL) }

    private func offerMoveToApplications() {
        let alert = NSAlert()
        alert.messageText = "Move \(AppInfo.name) to the Applications folder?"
        alert.informativeText = "Running from the Applications folder keeps automatic updates and Launch at Login working reliably."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try Relocator.moveToApplications()
            } catch {
                NSAlert(error: error).runModal()
            }
        } else {
            UserDefaults.standard.set(true, forKey: PrefKey.declinedMoveToApplications)
        }
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
