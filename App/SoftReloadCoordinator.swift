import AppKit
import Foundation

enum SoftReloadCoordinator {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let shutdownTimeout: TimeInterval = 3
    private static let launchTimeout: TimeInterval = 3

    struct RelaunchContext {
        let wasRunning: Bool
        let applicationURL: URL?
    }

    static func prepareForMutation(launchIfClosed: Bool = false) -> RelaunchContext {
        CodexAppearanceImporter.invalidateLiveBridgeCache()
        guard let runningCodex = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == codexBundleIdentifier }) else {
            return RelaunchContext(wasRunning: launchIfClosed, applicationURL: installedCodexURL())
        }
        let applicationURL = runningCodex.bundleURL ?? installedCodexURL()

        terminate(runningCodex)

        return RelaunchContext(wasRunning: true, applicationURL: applicationURL)
    }

    static func finishMutation(_ context: RelaunchContext, globalStateURL: URL) -> String {
        CodexAppearanceImporter.invalidateLiveBridgeCache()
        NSWorkspace.shared.noteFileSystemChanged(globalStateURL.path)

        guard context.wasRunning else {
            return "State written. Codex not running; no restart performed."
        }
        guard let applicationURL = context.applicationURL else {
            return "State written. Theme saved. Codex installation could not be found."
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if openApplication(at: applicationURL, configuration: configuration) {
            return "State written. Codex restarted."
        }

        return "State written. Theme saved. Automatic restart failed."
    }

    static func relaunchWithLiveBridge() -> String {
        CodexAppearanceImporter.invalidateLiveBridgeCache()
        let runningCodex = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == codexBundleIdentifier })
        let applicationURL = runningCodex?.bundleURL ?? installedCodexURL()
        if let runningCodex {
            terminate(runningCodex)
        }
        guard let applicationURL else {
            return "Codex live bridge relaunch failed. Codex installation could not be found."
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = ["--remote-debugging-port=9222"]
        if openApplication(at: applicationURL, configuration: configuration) {
            return "Codex relaunched with live bridge on 127.0.0.1:9222."
        }

        return "Codex live bridge relaunch failed."
    }

    static func startupLiveBridgeStatus() -> String {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == codexBundleIdentifier }) else {
            return "Live bridge idle. Codex is not running."
        }

        if CodexAppearanceImporter.isLiveBridgeAvailable() {
            return "Codex live bridge available."
        }

        return "Use live bridge to enable instant theme switching."
    }

    private static func waitForTermination(of app: NSRunningApplication) {
        let deadline = Date().addingTimeInterval(shutdownTimeout)
        while !app.isTerminated && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    private static func terminate(_ app: NSRunningApplication) {
        _ = app.terminate()
        waitForTermination(of: app)
        if !app.isTerminated {
            _ = app.forceTerminate()
            waitForTermination(of: app)
        }
    }

    private static func installedCodexURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: codexBundleIdentifier)
    }

    private static func openApplication(
        at applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) -> Bool {
        let result = WorkspaceLaunchResult()
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
            result.set(error == nil)
        }

        let deadline = Date().addingTimeInterval(launchTimeout)
        while result.get() == nil && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return result.get() ?? false
    }
}

private final class WorkspaceLaunchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?

    func set(_ value: Bool) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
