import Foundation
import Darwin

private struct FileChangeSignature: Equatable {
    let exists: Bool
    let size: UInt64
    let modifiedAt: Date?
}

public final class FileWatchdog: @unchecked Sendable {
    private enum WatchKind {
        case file
        case directory
    }

    private let url: URL
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var watchKind: WatchKind = .file
    private var isRunning = false
    private var isReinstallScheduled = false
    private var signature: FileChangeSignature?

    public init(
        url: URL,
        queue: DispatchQueue = DispatchQueue(label: "local.codex.theme-bar.watchdog"),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    public func start() {
        performOnQueue {
            guard !isRunning else { return }
            isRunning = true
            signature = currentSignature()
            if !installWatch() {
                isRunning = false
            }
        }
    }

    public func stop() {
        performOnQueue {
            isRunning = false
            closeWatch()
        }
    }

    private func performOnQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func currentSignature() -> FileChangeSignature {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else {
            return FileChangeSignature(exists: false, size: 0, modifiedAt: nil)
        }

        let size = attrs[.size] as? UInt64 ?? 0
        let modifiedAt = attrs[.modificationDate] as? Date
        return FileChangeSignature(exists: true, size: size, modifiedAt: modifiedAt)
    }

    private func installWatch() -> Bool {
        if installFileWatch() {
            return true
        }

        return installDirectoryWatch()
    }

    private func installFileWatch() -> Bool {
        let fd = Self.openDescriptor(at: url.path)
        guard fd >= 0 else { return false }
        watchKind = .file
        installSource(descriptor: fd, eventMask: [.write, .delete, .rename, .revoke, .attrib, .extend, .link])
        return true
    }

    private func installDirectoryWatch() -> Bool {
        let directoryPath = url.deletingLastPathComponent().path
        let fd = Self.openDescriptor(at: directoryPath)
        guard fd >= 0 else { return false }
        watchKind = .directory
        installSource(descriptor: fd, eventMask: [.write, .delete, .rename, .revoke, .attrib, .extend, .link])
        return true
    }

    private func installSource(descriptor: Int32, eventMask: DispatchSource.FileSystemEvent) {
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: eventMask, queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.handleWatchEvent(source.data)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    private func handleWatchEvent(_ events: DispatchSource.FileSystemEvent) {
        let newSignature = currentSignature()
        let signatureChanged = newSignature != signature
        let pathChanged = events.contains(.delete) || events.contains(.rename) || events.contains(.revoke)

        if signatureChanged || pathChanged {
            signature = newSignature
            let callback = onChange
            DispatchQueue.main.async {
                callback()
            }
        }

        if watchKind == .file {
            if pathChanged {
                scheduleReinstall()
            }
            return
        }

        if signatureChanged {
            scheduleReinstall()
        }
    }

    private func scheduleReinstall() {
        guard !isReinstallScheduled else { return }
        isReinstallScheduled = true
        queue.async { [weak self] in
            self?.reinstallWatch()
        }
    }

    private func reinstallWatch() {
        defer { isReinstallScheduled = false }
        guard isRunning else { return }
        closeWatch()
        signature = currentSignature()
        if !installWatch() {
            isRunning = false
        }
    }

    private func closeWatch() {
        isReinstallScheduled = false
        source?.cancel()
        source = nil
    }

    private static func openDescriptor(at path: String) -> Int32 {
        path.withCString { open($0, O_EVTONLY) }
    }
}
