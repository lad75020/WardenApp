import Foundation

enum AppShellTestSupport {
    static func makeDefaults() -> UserDefaults {
        let suiteName = "WardenTests.AppShell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
