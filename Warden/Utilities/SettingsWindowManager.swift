import Foundation
import SwiftUI
import CoreData
import AppKit

/// Keeps App Shell UI-test preference changes out of the user's application domain.
/// Production always uses the standard application defaults.
enum AppShellPreferenceStore {
    private static let suiteEnvironmentKey = "WARDEN_APP_SHELL_UI_TEST_DEFAULTS_SUITE"
    private static let resetEnvironmentKey = "WARDEN_APP_SHELL_UI_TEST_RESET_DEFAULTS"

    static let defaults: UserDefaults = {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains("-AppShellUITestMode"),
              let suiteName = processInfo.environment[suiteEnvironmentKey],
              let testDefaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }

        if processInfo.environment[resetEnvironmentKey] == "1" {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        return testDefaults
    }()
}

@MainActor
final class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    
    private var settingsWindow: NSWindow?
    private var windowDelegate: SettingsWindowDelegate?
    private var appearanceObserver: NSKeyValueObservation?
    
    private init() {
        // Observe UserDefaults changes for color scheme
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func userDefaultsDidChange() {
        updateWindowAppearance()
    }
    
    private func updateWindowAppearance() {
        guard let window = settingsWindow else { return }
        
        let preferredColorSchemeRaw = AppShellPreferenceStore.defaults.integer(forKey: "preferredColorScheme")
        
        switch preferredColorSchemeRaw {
        case 1: // Light
            window.appearance = NSAppearance(named: .aqua)
        case 2: // Dark
            window.appearance = NSAppearance(named: .darkAqua)
        default: // System (0)
            window.appearance = nil
        }
    }
    
    func openSettingsWindow() {
        // Keep one owner even when the window is miniaturized or temporarily ordered out.
        if let existingWindow = settingsWindow {
            existingWindow.deminiaturize(nil)
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Get the current color scheme preference
        let preferredColorSchemeRaw = AppShellPreferenceStore.defaults.integer(forKey: "preferredColorScheme")
        let colorScheme: ColorScheme? = {
            switch preferredColorSchemeRaw {
            case 1: return .light
            case 2: return .dark
            default: return nil
            }
        }()
        
        // Create the settings view with required environment objects and color scheme
        let settingsView = SettingsView()
            .environmentObject(ChatStore(persistenceController: PersistenceController.shared))
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .preferredColorScheme(colorScheme)
        
        // Create and configure the window with no title bar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(rootView: settingsView)
        window.identifier = NSUserInterfaceItemIdentifier("settings.window")
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        // Set empty title to work with hiddenTitleBar appearance
        window.title = ""
        
        // Apply initial appearance
        switch preferredColorSchemeRaw {
        case 1:
            window.appearance = NSAppearance(named: .aqua)
        case 2:
            window.appearance = NSAppearance(named: .darkAqua)
        default:
            window.appearance = nil
        }
        
        // Create and set delegate
        let delegate = SettingsWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            self?.windowDelegate = nil
        }
        
        window.delegate = delegate
        
        // Store references
        self.settingsWindow = window
        self.windowDelegate = delegate
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeSettingsWindow() {
        settingsWindow?.close()
        settingsWindow = nil
        windowDelegate = nil
    }
}

// MARK: - Window Delegate
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowClose: () -> Void
    
    init(onWindowClose: @escaping () -> Void) {
        self.onWindowClose = onWindowClose
    }
    
    func windowWillClose(_ notification: Notification) {
        onWindowClose()
    }
}
