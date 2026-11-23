import AppKit
import ApplicationServices
import CodexThemeBarCore
import Foundation

enum CodexAppearanceImporter {
    private static let targetCache = DebuggerTargetCache()

    static func isLiveBridgeAvailable() -> Bool {
        targetCache.clear()
        return (try? debuggerTarget()) != nil
    }

    static func invalidateLiveBridgeCache() {
        targetCache.clear()
    }

    static func extractLiveTheme() throws -> ThemeFilePayload {
        let json = try evaluateWithRetry(extractScript())
        guard let data = json.data(using: .utf8) else {
            throw CodexAppearanceImporterError.debugBridgeFailed("Live theme extraction encoding failed.")
        }
        return try JSONDecoder().decode(ThemeFilePayload.self, from: data)
    }

    static func importTheme(_ payload: ThemeFilePayload, variant: ThemeVariant) throws {
        _ = try evaluateWithRetry(script(for: payload, variant: variant))
    }

    static func setAppearanceMode(_ mode: ApplyTarget) throws {
        let script = appearanceBridgeScript(
            """
          let bridge;
          try {
            bridge = await resolveAppearanceBridge();
          } catch (error) {
            throw new Error("__THEME_BAR_BRIDGE_UNAVAILABLE__" + String(error?.message ?? error));
          }
          const { appActionRegistry, context } = bridge;
          const setMode = appActionRegistry.get("app.appearance.set_mode");
          if (typeof setMode !== "function") throw new Error("Codex appearance mode action is unavailable.");
          await setMode({ type: "app.appearance.set_mode", mode: "\(mode.rawValue)" }, context);
          return "ok";
        """
        )
        _ = try evaluateWithRetry(script)
    }

    private static func debuggerTarget() throws -> DebuggerTarget {
        if let cachedTarget = targetCache.get() {
            return cachedTarget
        }
        guard let data = try? request(URL(string: "http://127.0.0.1:9222/json/list")!),
              let targets = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw CodexAppearanceImporterError.debugBridgeUnavailable
        }
        let rendererTargets = targets.filter(isCodexRenderer).filter(hasDebuggerURL)
        let target = rendererTargets.first(where: isMainCodexRenderer) ?? rendererTargets.first
        guard let target,
              let webSocketURLString = target["webSocketDebuggerUrl"] as? String,
              let webSocketURL = URL(string: webSocketURLString) else {
            throw CodexAppearanceImporterError.debugBridgeUnavailable
        }
        let debuggerTarget = DebuggerTarget(webSocketURL: webSocketURL)
        targetCache.set(debuggerTarget)
        return debuggerTarget
    }

    private static func isCodexRenderer(_ target: [String: Any]) -> Bool {
        let type = target["type"] as? String
        let url = target["url"] as? String ?? ""
        return type == "page" &&
            (url.hasPrefix("app://") || url.contains("codex")) &&
            !url.contains("initialRoute=%2Fhotkey-window")
    }

    private static func isMainCodexRenderer(_ target: [String: Any]) -> Bool {
        let url = target["url"] as? String ?? ""
        return url.contains("hostId=local") ||
            (url.hasPrefix("app://-/index.html") && !url.contains("initialRoute="))
    }

    private static func hasDebuggerURL(_ target: [String: Any]) -> Bool {
        guard let value = target["webSocketDebuggerUrl"] as? String else {
            return false
        }
        return URL(string: value) != nil
    }

    private static func request(_ url: URL) throws -> Data {
        let result = CallbackResult<Data>()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                result.set(.failure(error))
            } else if (response as? HTTPURLResponse)?.statusCode != 200 {
                result.set(.failure(CodexAppearanceImporterError.debugBridgeUnavailable))
            } else {
                result.set(.success(data ?? Data()))
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        guard let result = result.get() else {
            throw CodexAppearanceImporterError.debugBridgeUnavailable
        }
        return try result.get()
    }

    private static func evaluateString(_ expression: String, in target: DebuggerTarget) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let result = CallbackResult<String>()
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: target.webSocketURL)
        socket.resume()

        let message: [String: Any] = [
            "id": 1,
            "method": "Runtime.evaluate",
            "params": [
                "expression": expression,
                "awaitPromise": true,
                "returnByValue": true
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexAppearanceImporterError.debugBridgeFailed("Debugger command encoding failed.")
        }
        socket.send(.string(text)) { error in
            if let error {
                result.set(.failure(error))
                semaphore.signal()
                return
            }
            socket.receive { response in
                defer {
                    socket.cancel(with: .goingAway, reason: nil)
                    semaphore.signal()
                }
                switch response {
                case .failure(let error):
                    result.set(.failure(error))
                case .success(.string(let text)):
                    result.set(parseEvaluateResponse(text))
                case .success(.data(let data)):
                    result.set(parseEvaluateResponse(String(decoding: data, as: UTF8.self)))
                @unknown default:
                    result.set(.failure(CodexAppearanceImporterError.debugBridgeFailed("Unexpected debugger response.")))
                }
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        guard let result = result.get() else {
            throw CodexAppearanceImporterError.debugBridgeUnavailable
        }
        return try result.get()
    }

    private static func evaluateWithRetry(_ expression: String) throws -> String {
        let target = try debuggerTarget()
        do {
            return try evaluateString(expression, in: target)
        } catch {
            guard shouldRetryWithFreshTarget(after: error) else {
                throw error
            }
            targetCache.clear()
            let refreshedTarget = try debuggerTarget()
            do {
                return try evaluateString(expression, in: refreshedTarget)
            } catch let importerError as CodexAppearanceImporterError {
                throw importerError
            } catch {
                throw CodexAppearanceImporterError.debugBridgeUnavailable
            }
        }
    }

    private static func shouldRetryWithFreshTarget(after error: Error) -> Bool {
        if let importerError = error as? CodexAppearanceImporterError {
            switch importerError {
            case .debugBridgeUnavailable:
                return true
            case .invalidShareString, .debugBridgeFailed:
                return false
            }
        }
        return true
    }

    private static func parseEvaluateResponse(_ text: String) -> Result<String, Error> {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(CodexAppearanceImporterError.debugBridgeFailed("Invalid debugger response."))
        }
        if let error = root["error"] as? [String: Any] {
            return .failure(CodexAppearanceImporterError.debugBridgeFailed(error["message"] as? String ?? "Debugger error."))
        }
        if let result = root["result"] as? [String: Any],
           let exception = result["exceptionDetails"] as? [String: Any] {
            let detail = (exception["exception"] as? [String: Any])?["description"] as? String
                ?? exception["text"] as? String
                ?? "Renderer exception."
            if detail.contains("__THEME_BAR_BRIDGE_UNAVAILABLE__") {
                return .failure(CodexAppearanceImporterError.debugBridgeUnavailable)
            }
            return .failure(CodexAppearanceImporterError.debugBridgeFailed(detail))
        }
        if let result = root["result"] as? [String: Any],
           let value = result["result"] as? [String: Any],
           let string = value["value"] as? String {
            return .success(string)
        }
        return .success("ok")
    }

    private static func extractScript() -> String {
        appearanceBridgeScript(
            """
          let bridge;
          try {
            bridge = await resolveAppearanceBridge();
          } catch (error) {
            throw new Error("__THEME_BAR_BRIDGE_UNAVAILABLE__" + String(error?.message ?? error));
          }
          const { appActionRegistry, context } = bridge;
          const getAppearance = appActionRegistry.get("app.appearance.get");
          if (typeof getAppearance !== "function") throw new Error("Codex appearance reader is unavailable.");
          const appearance = await getAppearance({ type: "app.appearance.get" }, context);
          const variant = appearance?.mode === "dark" ? "dark" : "light";
          const theme = appearance?.themes?.[variant]?.chromeTheme;
          const codeThemeId = appearance?.themes?.[variant]?.codeThemeId;
          if (!theme || !codeThemeId) throw new Error("Current Codex theme is unavailable.");
          return JSON.stringify({ variant, codeThemeId, favorite: false, theme });
        """
        )
    }

    private static func script(for payload: ThemeFilePayload, variant: ThemeVariant) throws -> String {
        guard let codexPatch = payload.theme.codexPatchObject(),
              let themeData = try? JSONSerialization.data(withJSONObject: codexPatch, options: [.sortedKeys]),
              let themeJSON = String(data: themeData, encoding: .utf8),
              let codeThemeJSON = String(data: try JSONEncoder().encode(payload.codeThemeId), encoding: .utf8),
              let variantJSON = String(data: try JSONEncoder().encode(variant.rawValue), encoding: .utf8) else {
            throw CodexAppearanceImporterError.invalidShareString
        }

        return appearanceBridgeScript(
            """
          const theme = \(themeJSON);
          const codeThemeId = \(codeThemeJSON);
          const variant = \(variantJSON);
          let bridge;
          try {
            bridge = await resolveAppearanceBridge();
          } catch (error) {
            throw new Error("__THEME_BAR_BRIDGE_UNAVAILABLE__" + String(error?.message ?? error));
          }
          const { appActionRegistry, context } = bridge;
          const getAppearance = appActionRegistry.get("app.appearance.get");
          const setTheme = appActionRegistry.get("app.appearance.set_theme");
          const setMode = appActionRegistry.get("app.appearance.set_mode");
          if (typeof getAppearance !== "function" ||
              typeof setTheme !== "function" ||
              typeof setMode !== "function") {
            throw new Error("Codex appearance actions are unavailable.");
          }
          const appearance = await getAppearance({ type: "app.appearance.get" }, context);
          if (appearance?.themes?.[variant]?.codeThemeId !== codeThemeId) {
            await setTheme(
              { type: "app.appearance.set_theme", variant, theme: { kind: "preset", themeId: codeThemeId } },
              context
            );
          }
          await setTheme(
            { type: "app.appearance.set_theme", variant, theme: { kind: "custom", patch: theme } },
            context
          );
          await setMode({ type: "app.appearance.set_mode", mode: variant }, context);
          return "ok";
        """
        )
    }

    private static func appearanceBridgeScript(_ body: String) -> String {
        """
        (async () => {
          const cache = window.__themeBarAppearanceBridgeCache ??= {};
          const bridgeVersion = 3;
          if (cache.bridgeVersion !== bridgeVersion) {
            cache.bridgeVersion = bridgeVersion;
            cache.actionRegistryPromise = null;
          }
          const resolveActionRegistry = async () => {
            if (cache.actionRegistryPromise) {
              return cache.actionRegistryPromise;
            }
            cache.actionRegistryPromise = (async () => {
              const scriptSources = Array.from(document.querySelectorAll("script[src]"))
                .map((script) => script.src)
                .filter(Boolean);
              const indexSource =
                scriptSources.find((src) => /\\/assets\\/index-[^/]+\\.js$/.test(src)) ??
                scriptSources[0];
              if (!indexSource) throw new Error("Codex asset entrypoint is unavailable.");
              const indexText = await fetch(indexSource).then((response) => response.text());
              const assetNames = Array.from(
                new Set(
                  Array.from(indexText.matchAll(/(?:\\.\\/)?[A-Za-z0-9_-]+-[A-Za-z0-9_-]+\\.js/g))
                    .map((match) => match[0].replace(/^\\.\\//, ""))
                )
              );
              let actionModuleName =
                indexText.match(/(?:\\.\\/)?(register-app-actions-[A-Za-z0-9_-]+\\.js)/)?.[1] ?? null;
              for (const assetName of assetNames) {
                if (actionModuleName) break;
                let text = "";
                try {
                  text = await fetch("app://-/assets/" + assetName).then((response) => response.text());
                } catch {
                  continue;
                }
                actionModuleName =
                  text.match(/(?:\\.\\/)?(register-app-actions-[A-Za-z0-9_-]+\\.js)/)?.[1] ?? null;
              }
              if (!actionModuleName) {
                throw new Error("Codex appearance action module is unavailable.");
              }
              const module = await import("app://-/assets/" + actionModuleName);
              const appActionRegistry = module.appActionRegistry;
              if (!appActionRegistry || typeof appActionRegistry.get !== "function") {
                throw new Error("Codex app action registry is unavailable.");
              }
              return appActionRegistry;
            })();
            try {
              return await cache.actionRegistryPromise;
            } catch (error) {
              cache.actionRegistryPromise = null;
              throw error;
            }
          };

          const resolveAppearanceBridge = async () => {
            const root = window.__codexRoot?._internalRoot?.current;
            if (!root) throw new Error("Codex React root is unavailable.");
            const seen = new Set();
            const queue = [root];
            while (queue.length) {
              const node = queue.shift();
              if (!node || typeof node !== "object" || seen.has(node)) continue;
              seen.add(node);
              if (node.queryClient &&
                  typeof node.queryClient.getQueryData === "function" &&
                  typeof node.queryClient.setQueryData === "function" &&
                  typeof node.queryClient.invalidateQueries === "function") {
                return {
                  appActionRegistry: await resolveActionRegistry(),
                  context: { scope: node, queryClient: node.queryClient }
                };
              }
              for (const key of ["child", "sibling", "return", "memoizedState", "memoizedProps", "stateNode", "dependencies", "updateQueue", "next", "current", "value"]) {
                const value = node[key];
                if (!value) continue;
                if (Array.isArray(value)) queue.push(...value);
                else if (typeof value === "object") queue.push(value);
              }
            }
            throw new Error("Codex query client is unavailable.");
          };

        \(body)
        })()
        """
    }
}

enum CodexAccessibilityCancellationReason: Equatable, Sendable {
    case superseded
    case userInterrupted
}

final class CodexAccessibilityOperation: @unchecked Sendable {
    private static let observedEventTypes: [CGEventType] = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .keyDown,
        .scrollWheel
    ]

    private let lock = NSLock()
    private let initialEventCounts: [(CGEventType, UInt32)]
    private var storedCancellationReason: CodexAccessibilityCancellationReason?

    init() {
        initialEventCounts = Self.observedEventTypes.map { eventType in
            (
                eventType,
                CGEventSource.counterForEventType(.hidSystemState, eventType: eventType)
            )
        }
    }

    @discardableResult
    func cancel(_ reason: CodexAccessibilityCancellationReason) -> CodexAccessibilityCancellationReason {
        lock.lock()
        defer { lock.unlock() }
        let effectiveReason = storedCancellationReason ?? reason
        storedCancellationReason = effectiveReason
        return effectiveReason
    }

    var cancellationReason: CodexAccessibilityCancellationReason? {
        lock.lock()
        let existingReason = storedCancellationReason
        lock.unlock()
        if let existingReason {
            return existingReason
        }

        let didReceiveUserInput = initialEventCounts.contains { eventType, initialCount in
            CGEventSource.counterForEventType(.hidSystemState, eventType: eventType) != initialCount
        }
        if didReceiveUserInput {
            return cancel(.userInterrupted)
        }
        return nil
    }
}

enum CodexAccessibilityImportResult: Sendable {
    case applied(restoreWarning: String?)
    case cancelled(CodexAccessibilityCancellationReason)
    case failed(String)
}

enum CodexAccessibilityImporter {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let timeout: TimeInterval = 30

    @MainActor
    static func runningCodex() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            application.bundleIdentifier == codexBundleIdentifier
        }
    }

    static func isTrusted() -> Bool {
        // Accessibility is the permission required to inspect and drive Codex.
        // Post-event access is a separate, optional capability used only when
        // Chromium ignores an AXPress/AXValue action. Treating it as part of
        // the trust gate caused a second system permission prompt for users
        // who had already granted Codex ThemeWurx control of Codex.
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }

    static func setAppearanceMode(
        _ mode: ApplyTarget,
        processIdentifier: pid_t,
        stateURL: URL,
        backupURL: URL,
        operation: CodexAccessibilityOperation
    ) async -> CodexAccessibilityImportResult {
        await Task.detached(priority: .userInitiated) {
            runSetAppearanceMode(mode, processIdentifier: processIdentifier, stateURL: stateURL, backupURL: backupURL, operation: operation)
        }.value
    }

    private static func runSetAppearanceMode(
        _ mode: ApplyTarget,
        processIdentifier: pid_t,
        stateURL: URL,
        backupURL: URL,
        operation: CodexAccessibilityOperation
    ) -> CodexAccessibilityImportResult {
        do {
            guard let eventSource = CGEventSource(stateID: .privateState) else {
                throw CodexAccessibilityImporterError.actionFailed("Create automation event source")
            }
            let root = AXUIElementCreateApplication(processIdentifier)
            let deadline = Date().addingTimeInterval(timeout)
            let name = mode == .light ? "Light" : "Dark"
            try waitForActiveCodex(processIdentifier, deadline: deadline, operation: operation)
            let previousView = try selectAppearanceMode(name, root: root, source: eventSource, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
            let stateStore = CodexGlobalStateStore(stateURL: stateURL, backupURL: backupURL)
            try waitUntil(deadline: deadline, operation: operation, waitingFor: "Codex to save the appearance mode") {
                (try? stateStore.loadSnapshot().appearanceTheme) == mode.rawValue
            }
            let warning = restorePreviousView(root: root, startedInSettings: previousView.startedInSettings, originalSettingsSection: previousView.originalSettingsSection, source: eventSource, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
            return .applied(restoreWarning: warning)
        } catch let cancellation as AccessibilityCancellationError {
            return .cancelled(cancellation.reason)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func importTheme(
        _ payload: ThemeFilePayload,
        processIdentifier: pid_t,
        operation: CodexAccessibilityOperation
    ) async -> CodexAccessibilityImportResult {
        await Task.detached(priority: .userInitiated) {
            runImport(payload, processIdentifier: processIdentifier, operation: operation)
        }.value
    }

    private static func runImport(
        _ payload: ThemeFilePayload,
        processIdentifier: pid_t,
        operation: CodexAccessibilityOperation
    ) -> CodexAccessibilityImportResult {
        do {
            let shareString = try ThemeShareString.encode(payload)
            guard let eventSource = CGEventSource(stateID: .privateState) else {
                throw CodexAccessibilityImporterError.actionFailed("Create automation event source")
            }
            let root = AXUIElementCreateApplication(processIdentifier)
            let deadline = Date().addingTimeInterval(timeout)
            let variantName = payload.variant == .light ? "Light" : "Dark"

            try waitForActiveCodex(processIdentifier, deadline: deadline, operation: operation)
            try checkCancellation(operation)
            // Close an existing import before selecting the requested mode.
            for openVariant in ["Light", "Dark"] {
                if findElement(
                    in: root,
                    role: kAXTextFieldRole,
                    description: "\(openVariant) theme share string"
                ) != nil {
                    let cancelButton = try requiredElement(
                        in: root,
                        role: kAXButtonRole,
                        title: "Cancel",
                        deadline: deadline,
                        operation: operation
                    )
                    try activateWebControl(cancelButton, named: "Cancel stale theme import", source: eventSource, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
                    try waitUntil(deadline: deadline, operation: operation, waitingFor: "the stale import dialog to close") {
                        findElement(
                            in: root,
                            role: kAXTextFieldRole,
                            description: "\(openVariant) theme share string"
                        ) == nil
                    }
                }
            }
            let previousView = try selectAppearanceMode(variantName, root: root, source: eventSource, processIdentifier: processIdentifier, deadline: deadline, operation: operation)

            let importButton = try requiredElement(
                in: root,
                role: kAXPopUpButtonRole,
                description: "Import \(variantName) theme",
                deadline: deadline,
                operation: operation
            )
            try activateWebControl(importButton, named: "Import \(variantName) theme", source: eventSource, processIdentifier: processIdentifier, deadline: deadline, operation: operation)

            let shareField = try requiredElement(
                in: root,
                role: kAXTextFieldRole,
                description: "\(variantName) theme share string",
                deadline: deadline,
                operation: operation
            )
            try typeValue(
                shareString,
                into: shareField,
                source: eventSource,
                named: "\(variantName) theme share string",
                processIdentifier: processIdentifier,
                deadline: deadline,
                operation: operation
            )

            let submitButton = try requiredElement(
                in: root,
                role: kAXButtonRole,
                title: "Import theme",
                deadline: deadline,
                operation: operation
            )
            try waitUntil(deadline: deadline, operation: operation, waitingFor: "the Import theme button to become enabled") {
                attributeValue(of: submitButton, attribute: kAXEnabledAttribute) as? Bool == true
            }
            try activateWebControl(submitButton, named: "Import theme", source: eventSource, processIdentifier: processIdentifier, deadline: deadline, operation: operation)

            try waitUntil(deadline: deadline, operation: operation, waitingFor: "the import dialog to close") {
                findElement(
                    in: root,
                    role: kAXTextFieldRole,
                    description: "\(variantName) theme share string"
                ) == nil
            }
            let restoreWarning = restorePreviousView(
                root: root,
                startedInSettings: previousView.startedInSettings,
                originalSettingsSection: previousView.originalSettingsSection,
                source: eventSource,
                processIdentifier: processIdentifier,
                deadline: deadline,
                operation: operation
            )
            return .applied(restoreWarning: restoreWarning)
        } catch let cancellation as AccessibilityCancellationError {
            return .cancelled(cancellation.reason)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func selectAppearanceMode(
        _ name: String,
        root: AXUIElement,
        source: CGEventSource,
        processIdentifier: pid_t,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) throws -> (startedInSettings: Bool, originalSettingsSection: String?) {
        let startedInSettings = findElement(in: root, role: kAXGroupRole, description: "Settings") != nil
        let originalSettingsSection = startedInSettings ? selectedSettingsSection(in: root) : nil
        if !startedInSettings {
            let settingsItem = try requiredElement(in: root, role: kAXMenuItemRole, title: "Settings…", deadline: deadline, operation: operation)
            try performPress(settingsItem, named: "Settings")
        }
        try waitForActiveCodex(processIdentifier, deadline: deadline, operation: operation)
        let appearanceButton = try requiredElement(in: root, role: kAXButtonRole, description: "Appearance", deadline: deadline, operation: operation)
        try activateWebControl(appearanceButton, named: "Appearance", source: source, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
        let modeButton = try requiredElement(in: root, role: kAXRadioButtonRole, description: name, deadline: deadline, operation: operation)
        try activateWebControl(modeButton, named: "\(name) appearance mode", source: source, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
        return (startedInSettings, originalSettingsSection)
    }

    private static func restorePreviousView(
        root: AXUIElement,
        startedInSettings: Bool,
        originalSettingsSection: String?,
        source: CGEventSource,
        processIdentifier: pid_t,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) -> String? {
        do {
            if startedInSettings {
                guard let originalSettingsSection else {
                    return "The previous Codex settings section could not be determined."
                }
                guard originalSettingsSection != "Appearance" else {
                    return nil
                }
                let originalSectionButton = try requiredElement(
                    in: root,
                    role: kAXButtonRole,
                    description: originalSettingsSection,
                    deadline: deadline,
                    operation: operation
                )
                try activateWebControl(originalSectionButton, named: originalSettingsSection, source: source, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
            } else {
                let closeButton = try requiredElement(
                    in: root,
                    role: kAXButtonRole,
                    description: "Close dialog",
                    deadline: deadline,
                    operation: operation
                )
                try activateWebControl(closeButton, named: "Close settings", source: source, processIdentifier: processIdentifier, deadline: deadline, operation: operation)
                try waitUntil(deadline: deadline, operation: operation, waitingFor: "Settings to close") {
                    findElement(in: root, role: kAXGroupRole, description: "Settings") == nil
                }
            }
            return nil
        } catch let cancellation as AccessibilityCancellationError {
            if cancellation.reason != .superseded {
                return "Previous Codex view was not restored because the operation was interrupted."
            }
            return nil
        } catch {
            return "The previous Codex view could not be restored."
        }
    }

    private static func selectedSettingsSection(in root: AXUIElement) -> String? {
        guard let settings = findElement(
            in: root,
            role: kAXGroupRole,
            description: "Settings"
        ) else {
            return nil
        }
        return findElement(in: settings) { element in
            guard stringValue(of: element, attribute: kAXRoleAttribute) == kAXHeadingRole else {
                return false
            }
            let name = stringValue(of: element, attribute: kAXTitleAttribute)
            return !name.isEmpty && findElement(in: settings, role: kAXButtonRole, description: name) != nil
        }.map { stringValue(of: $0, attribute: kAXTitleAttribute) }
    }

    private static func requiredElement(
        in root: AXUIElement,
        role: String? = nil,
        title: String? = nil,
        description: String? = nil,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) throws -> AXUIElement {
        while Date() < deadline {
            try checkCancellation(operation)
            if let element = findElement(in: root, role: role, title: title, description: description) {
                return element
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw CodexAccessibilityImporterError.controlUnavailable(description ?? title ?? role ?? "control")
    }

    private static func waitForActiveCodex(
        _ processIdentifier: pid_t,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) throws {
        try waitUntil(deadline: deadline, operation: operation, waitingFor: "Codex to become active") {
            NSRunningApplication(processIdentifier: processIdentifier)?.isActive == true
        }
    }

    private static func waitUntil(
        deadline: Date,
        operation: CodexAccessibilityOperation,
        waitingFor: String,
        condition: () -> Bool
    ) throws {
        while Date() < deadline {
            try checkCancellation(operation)
            if condition() {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw CodexAccessibilityImporterError.timedOut(waitingFor)
    }

    private static func checkCancellation(_ operation: CodexAccessibilityOperation) throws {
        if let reason = operation.cancellationReason {
            throw AccessibilityCancellationError(reason: reason)
        }
    }

    private static func performPress(_ element: AXUIElement, named name: String) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw CodexAccessibilityImporterError.actionFailed(name)
        }
    }

    private static func activateWebControl(
        _ element: AXUIElement,
        named name: String,
        source: CGEventSource,
        processIdentifier: pid_t,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) throws {
        guard CGPreflightPostEventAccess() else {
            try checkCancellation(operation)
            try performPress(element, named: name)
            return
        }
        // Chromium can acknowledge AXPress without invoking the web button.
        // Focus and keyboard activation exercise its normal input handler.
        try focus(element, named: name, deadline: deadline, operation: operation)
        try checkCancellation(operation)
        let key: CGKeyCode = stringValue(of: element, attribute: kAXRoleAttribute) == "AXLink" ? 36 : 49
        try postKey(virtualKey: key, source: source, processIdentifier: processIdentifier, named: name)
    }

    private static func focus(
        _ element: AXUIElement,
        named name: String,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) throws {
        try checkCancellation(operation)
        guard AXUIElementSetAttributeValue(
            element, kAXFocusedAttribute as CFString, kCFBooleanTrue
        ) == .success else {
            throw CodexAccessibilityImporterError.actionFailed("Focus \(name)")
        }
        try waitUntil(deadline: deadline, operation: operation, waitingFor: "focus on \(name)") {
            attributeValue(of: element, attribute: kAXFocusedAttribute) as? Bool == true
        }
    }

    private static func typeValue(
        _ value: String,
        into element: AXUIElement,
        source: CGEventSource,
        named name: String,
        processIdentifier: pid_t,
        deadline: Date,
        operation: CodexAccessibilityOperation
    ) throws {
        if !CGPreflightPostEventAccess() {
            try checkCancellation(operation)
            guard AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                value as CFTypeRef
            ) == .success else {
                throw CodexAccessibilityImporterError.actionFailed("Type \(name)")
            }
            try waitUntil(deadline: deadline, operation: operation, waitingFor: "the theme share string to be entered") {
                stringValue(of: element, attribute: kAXValueAttribute) == value
            }
            return
        }

        try focus(element, named: name, deadline: deadline, operation: operation)

        try checkCancellation(operation)
        let pasteboard = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
        var injectedChangeCount: Int?
        defer {
            if injectedChangeCount == nil || pasteboard.changeCount == injectedChangeCount {
                pasteboard.clearContents()
                if !savedItems.isEmpty {
                    pasteboard.writeObjects(savedItems as [NSPasteboardWriting])
                }
            }
        }

        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else {
            throw CodexAccessibilityImporterError.actionFailed(name)
        }
        injectedChangeCount = pasteboard.changeCount

        try postKey(
            virtualKey: 0,
            flags: .maskCommand,
            source: source,
            processIdentifier: processIdentifier,
            named: name
        )
        try postKey(
            virtualKey: 9,
            flags: .maskCommand,
            source: source,
            processIdentifier: processIdentifier,
            named: name
        )

        try waitUntil(deadline: deadline, operation: operation, waitingFor: "the theme share string to be pasted") {
            stringValue(of: element, attribute: kAXValueAttribute) == value
        }
    }

    private static func postKey(
        virtualKey: CGKeyCode,
        flags: CGEventFlags = [],
        source: CGEventSource,
        processIdentifier: pid_t,
        named name: String
    ) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            throw CodexAccessibilityImporterError.actionFailed(name)
        }
        guard NSRunningApplication(processIdentifier: processIdentifier)?.isActive == true else {
            throw CodexAccessibilityImporterError.actionFailed("\(name): Codex is no longer active")
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }

    private static func findElement(
        in root: AXUIElement,
        role: String? = nil,
        title: String? = nil,
        description: String? = nil
    ) -> AXUIElement? {
        findElement(in: root) { element in
            (role == nil || stringValue(of: element, attribute: kAXRoleAttribute) == role) &&
                (title == nil || stringValue(of: element, attribute: kAXTitleAttribute) == title) &&
                (description == nil ||
                    stringValue(of: element, attribute: kAXDescriptionAttribute) == description ||
                    stringValue(of: element, attribute: kAXTitleAttribute) == description)
        }
    }

    private static func findElement(
        in root: AXUIElement,
        depth: Int = 0,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard depth <= 30 else { return nil }
        if predicate(root) {
            return root
        }
        guard let children = attributeValue(of: root, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = findElement(
                in: child,
                depth: depth + 1,
                matching: predicate
            ) {
                return match
            }
        }
        return nil
    }

    private static func attributeValue(of element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }

    private static func stringValue(of element: AXUIElement, attribute: String) -> String {
        attributeValue(of: element, attribute: attribute) as? String ?? ""
    }

}

private struct AccessibilityCancellationError: Error {
    let reason: CodexAccessibilityCancellationReason
}

private enum CodexAccessibilityImporterError: LocalizedError {
    case actionFailed(String)
    case controlUnavailable(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .actionFailed(let control):
            return "Codex Accessibility action failed for \(control)."
        case .controlUnavailable(let control):
            return "Codex Accessibility control is unavailable: \(control)."
        case .timedOut(let condition):
            return "Codex Accessibility timed out waiting for \(condition)."
        }
    }
}

private final class CallbackResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private final class DebuggerTargetCache: @unchecked Sendable {
    private let lock = NSLock()
    private var target: DebuggerTarget?

    func get() -> DebuggerTarget? {
        lock.lock()
        defer { lock.unlock() }
        return target
    }

    func set(_ target: DebuggerTarget) {
        lock.lock()
        self.target = target
        lock.unlock()
    }

    func clear() {
        lock.lock()
        target = nil
        lock.unlock()
    }
}

private struct DebuggerTarget {
    let webSocketURL: URL
}

enum CodexAppearanceImporterError: LocalizedError {
    case invalidShareString
    case debugBridgeUnavailable
    case debugBridgeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidShareString:
            return "Theme share string is invalid."
        case .debugBridgeUnavailable:
            return "Codex live bridge is unavailable. Relaunch Codex once with --remote-debugging-port=9222."
        case .debugBridgeFailed(let message):
            return "Codex live bridge failed: \(message)"
        }
    }
}
