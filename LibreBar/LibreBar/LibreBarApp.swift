import SwiftUI
import Combine
import UserNotifications

@main
struct LibreBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var glucose: GlucoseManager!
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeychainHelper.migrateIfNeeded()
        glucose = GlucoseManager()

        UNUserNotificationCenter.current().delegate = self
        AlertManager.shared.registerCategories()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateLabel()

        popover = NSPopover()
        popover.contentSize = NSSize(width: Theme.popoverWidth, height: Theme.popoverHeight)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(glucose: glucose))

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        glucose.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateLabel() }
            }
            .store(in: &cancellables)

        HotkeyManager.shared.onTrigger = { [weak self] in
            DispatchQueue.main.async { self?.togglePopover() }
        }
        HotkeyManager.shared.register()

        UpdateChecker.shared.checkForUpdates(silent: true)
        UpdateChecker.shared.scheduleDailyCheck()

        maybeShowOnboarding()
    }

    private func maybeShowOnboarding() {
        let defaults = UserDefaults.standard
        let key = "onboarding_complete"
        if defaults.bool(forKey: key) { return }

        let hasLibre = !glucose.email.isEmpty && KeychainHelper.load(account: "libre_password") != nil
        let hasNightscout = glucose.isNightscout && !glucose.nightscoutURL.isEmpty

        // Existing configured users: mark complete without interrupting them.
        if hasLibre || hasNightscout {
            defaults.set(true, forKey: key)
            return
        }

        OnboardingWindowController.shared.show(glucose: glucose) {
            defaults.set(true, forKey: key)
        }
    }

    // MARK: - Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let actionID = response.actionIdentifier
        await MainActor.run {
            switch actionID {
            case AlertManager.snoozeActionID:
                AlertManager.shared.snooze()
            case AlertManager.openActionID, UNNotificationDefaultActionIdentifier:
                self.showPopover()
            default:
                break
            }
        }
    }

    func updateLabel() {
        guard let button = statusItem.button else { return }

        let renderer = ImageRenderer(content: MenuBarLabelView(glucose: glucose))
        renderer.scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        if let image = renderer.nsImage {
            image.isTemplate = false
            button.title = ""
            button.image = image
        } else {
            button.image = nil
            button.title = "--"
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(glucose: GlucoseManager) {
        if let window, window.isVisible {
            window.setContentSize(NSSize(
                width: SettingsWindowMetrics.width,
                height: SettingsWindowMetrics.height
            ))
            positionWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(glucose: glucose)
        let hostingView = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingView)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.titlebarAppearsTransparent = false
        let size = NSSize(
            width: SettingsWindowMetrics.width,
            height: SettingsWindowMetrics.height
        )
        window.setContentSize(size)
        window.minSize = NSSize(width: 620, height: 560)
        positionWindow(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func positionWindow(_ window: NSWindow) {
        window.center()
    }
}

class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show(glucose: GlucoseManager, onComplete: @escaping () -> Void) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(glucose: glucose) { [weak self] in
            onComplete()
            self?.window?.close()
            self?.window = nil
        }
        let hostingView = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingView)
        window.title = "Welcome to LibreBar"
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

