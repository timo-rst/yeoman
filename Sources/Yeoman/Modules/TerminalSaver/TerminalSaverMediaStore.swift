import Foundation
import Darwin

/// Descriptor-relative persistent storage for TerminalSaver configuration and imported media.
public final class TerminalSaverMediaStore {
    public static let shared = TerminalSaverMediaStore()

    private static let configFileName = "config.json"
    private static let rotationStateFileName = "rotation_state.json"
    private static let maxRotationStateBytes = 64 * 1024
    private let rootDirectoryURL: URL?

    public init(rootDirectoryURL: URL? = nil) {
        self.rootDirectoryURL = rootDirectoryURL
    }

    private func openDirectories() throws -> (moduleDir: SecureDirectory, mediaDir: SecureDirectory) {
        let baseURL: URL
        let useYeomanParent: Bool
        if let injected = rootDirectoryURL {
            baseURL = injected
            useYeomanParent = false
        } else if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = appSupport
            useYeomanParent = true
        } else {
            throw SecurityFailure.rejected("Application Support Verzeichnis nicht verfügbar.")
        }

        let boundary = try SecureDirectory.boundaryRoot(baseURL)
        let appDir = useYeomanParent ? try boundary.child("Yeoman", create: true) : boundary
        let moduleDir = try appDir.child("TerminalSaver", create: true)
        let mediaDir = try moduleDir.child("media", create: true)
        return (moduleDir, mediaDir)
    }

    public func loadConfig() throws -> TerminalSaverConfig {
        let (moduleDir, _) = try openDirectories()
        guard try moduleDir.exists(Self.configFileName) else {
            return TerminalSaverConfig()
        }
        let data = try moduleDir.read(Self.configFileName, limit: TerminalSaverPolicy.maxConfigBytes)
        let decoded = try JSONDecoder().decode(TerminalSaverConfig.self, from: data)
        return decoded.sanitized()
    }

    public func saveConfig(_ config: TerminalSaverConfig) throws {
        let (moduleDir, _) = try openDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config.sanitized())
        guard data.count <= TerminalSaverPolicy.maxConfigBytes else {
            throw SecurityFailure.rejected("Konfiguration überschreitet das zulässige Größenlimit.")
        }
        try moduleDir.write(data, name: Self.configFileName)
    }

    /// Starts a session and advances the persisted cursor in the same locked operation.
    public func startRotationSession(
        for pool: [TerminalSaverSource],
        previewing source: TerminalSaverSource? = nil
    ) -> (navigator: TerminalSaverSessionNavigator, savedState: TerminalSaverRotationState?) {
        guard Set(pool).count > 1 else {
            return (TerminalSaverSessionNavigator(pool: pool, initialSource: source), nil)
        }
        if source == nil, let session = try? withRotationLock({ directory in
            let navigator = TerminalSaverSessionNavigator(pool: pool, state: readRotationState(in: directory))
            do {
                try writeRotationState(navigator.state, in: directory)
                return (navigator, Optional(navigator.state))
            } catch {
                return (navigator, nil)
            }
        }) {
            return session
        }
        let directory = try? openDirectories().moduleDir
        let state = directory.flatMap { readRotationState(in: $0) }
        return (TerminalSaverSessionNavigator(pool: pool, state: state, initialSource: source), nil)
    }

    /// An older session may continue locally, but it cannot overwrite a newer saved cursor or order.
    public func saveRotationProgress(
        _ state: TerminalSaverRotationState,
        replacing expectedState: TerminalSaverRotationState
    ) -> Bool {
        (try? withRotationLock { directory in
            guard readRotationState(in: directory) == expectedState else { return false }
            try writeRotationState(state, in: directory)
            return true
        }) ?? false
    }

    /// Picks one animation and persists the cursor across invocations.
    public func nextSource(for pool: [TerminalSaverSource]) -> TerminalSaverSource {
        startRotationSession(for: pool).navigator.current
    }

    /// Persists a new shuffled order when the selection is explicitly reshuffled.
    public func reshuffleRotation(for pool: [TerminalSaverSource]) {
        try? withRotationLock { directory in
            var queue = TerminalSaverRotationQueue(pool: pool, state: readRotationState(in: directory))
            guard queue.poolCount > 1 else {
                if try directory.exists(Self.rotationStateFileName) {
                    try directory.remove(Self.rotationStateFileName)
                }
                return
            }
            queue.reshuffle()
            try writeRotationState(queue.state, in: directory)
        }
    }

    private func withRotationLock<T>(_ body: (SecureDirectory) throws -> T) throws -> T {
        let (directory, _) = try openDirectories()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.1
        while flock(directory.descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard (errno == EWOULDBLOCK || errno == EINTR), ProcessInfo.processInfo.systemUptime < deadline else {
                throw SecurityFailure.rejected("Terminal Saver rotation is busy")
            }
            usleep(1_000)
        }
        defer { _ = flock(directory.descriptor, LOCK_UN) }
        return try body(directory)
    }

    private func readRotationState(in directory: SecureDirectory) -> TerminalSaverRotationState? {
        guard let data = try? directory.read(Self.rotationStateFileName, limit: Self.maxRotationStateBytes) else {
            return nil
        }
        return try? JSONDecoder().decode(TerminalSaverRotationState.self, from: data)
    }

    private func writeRotationState(_ state: TerminalSaverRotationState, in directory: SecureDirectory) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= Self.maxRotationStateBytes else {
            throw SecurityFailure.rejected("Terminal Saver rotation exceeds its storage limit")
        }
        try directory.write(data, name: Self.rotationStateFileName)
    }

    public func importMedia(from externalURL: URL, currentConfig: TerminalSaverConfig) throws -> (config: TerminalSaverConfig, item: TerminalSaverMediaItem) {
        let sanitizedCurrent = currentConfig.sanitized()
        guard sanitizedCurrent.mediaItems.count < TerminalSaverPolicy.maxLibraryItems else {
            throw SecurityFailure.rejected("Maximale Anzahl von \(TerminalSaverPolicy.maxLibraryItems) Medien-Einträgen erreicht.")
        }
        guard let ext = TerminalSaverPolicy.normalizedExtension(externalURL.pathExtension) else {
            throw SecurityFailure.rejected("Dateityp wird nicht unterstützt.")
        }

        let limit = TerminalSaverPolicy.byteLimit(forExtension: ext)
        let data = try readUntrustedRegularFile(at: externalURL, limit: limit)
        try TerminalSaverMediaDecoder.validate(data: data, fileExtension: ext)

        let rawName = externalURL.deletingPathExtension().lastPathComponent
        let item = TerminalSaverMediaItem(
            displayName: rawName,
            fileExtension: ext,
            byteCount: data.count
        )

        let (_, mediaDir) = try openDirectories()
        try mediaDir.write(data, name: item.storedFileName)

        var updated = sanitizedCurrent
        updated.mediaItems.append(item)
        updated.selectedSource = .media(item.id)
        if !updated.selectedSources.contains(.media(item.id)) {
            updated.selectedSources.append(.media(item.id))
        }
        updated = updated.sanitized()

        do {
            try saveConfig(updated)
        } catch {
            try? mediaDir.remove(item.storedFileName)
            throw error
        }

        reshuffleRotation(for: updated.effectiveSelectedSources)
        return (updated, item)
    }

    public func readMediaData(for item: TerminalSaverMediaItem) throws -> Data {
        guard item.isValid else {
            throw SecurityFailure.rejected("Ungültiges Medien-Metadatenobjekt.")
        }
        let (_, mediaDir) = try openDirectories()
        let limit = TerminalSaverPolicy.byteLimit(forExtension: item.fileExtension)
        return try mediaDir.read(item.storedFileName, limit: limit)
    }

    public func mediaFileURL(for item: TerminalSaverMediaItem) throws -> URL {
        guard item.isValid else {
            throw SecurityFailure.rejected("Ungültiges Medien-Metadatenobjekt.")
        }
        let (_, mediaDir) = try openDirectories()
        guard try mediaDir.exists(item.storedFileName) else {
            throw SecurityFailure.rejected("Mediendatei nicht gefunden.")
        }
        return mediaDir.url.appendingPathComponent(item.storedFileName)
    }

    public func readCutoutData(for item: TerminalSaverMediaItem) throws -> Data {
        guard item.isValid else {
            throw SecurityFailure.rejected("Ungültiges Medien-Metadatenobjekt.")
        }
        let (_, mediaDir) = try openDirectories()
        return try mediaDir.read(item.cutoutCacheFileName, limit: TerminalSaverPolicy.maxImageBytes)
    }

    public func writeCutoutData(_ data: Data, for item: TerminalSaverMediaItem) throws {
        guard item.isValid else {
            throw SecurityFailure.rejected("Ungültiges Medien-Metadatenobjekt.")
        }
        guard !data.isEmpty, data.count <= TerminalSaverPolicy.maxImageBytes else {
            throw SecurityFailure.rejected("Cutout-Cache überschreitet das Größenlimit.")
        }
        let (_, mediaDir) = try openDirectories()
        try mediaDir.write(data, name: item.cutoutCacheFileName)
    }

    public func removeCutoutCache(for item: TerminalSaverMediaItem) {
        guard item.isValid, let (_, mediaDir) = try? openDirectories() else { return }
        try? mediaDir.remove(item.cutoutCacheFileName)
    }

    public func deleteMedia(id: UUID, currentConfig: TerminalSaverConfig) throws -> TerminalSaverConfig {
        let sanitizedCurrent = currentConfig.sanitized()
        guard let removedItem = sanitizedCurrent.mediaItems.first(where: { $0.id == id }) else {
            return sanitizedCurrent
        }

        var updated = sanitizedCurrent
        updated.mediaItems.removeAll(where: { $0.id == id })
        updated.selectedSources.removeAll(where: { $0 == .media(id) })
        if updated.selectedSource == .media(id) {
            if let next = updated.mediaItems.first {
                updated.selectedSource = .media(next.id)
            } else {
                updated.selectedSource = .builtIn(.bonfire)
            }
        }
        updated = updated.sanitized()

        // Commit updated config before removing media bytes.
        try saveConfig(updated)
        let (_, mediaDir) = try openDirectories()
        try? mediaDir.remove(removedItem.storedFileName)
        try? mediaDir.remove(removedItem.cutoutCacheFileName)
        return updated
    }

    private func readUntrustedRegularFile(at url: URL, limit: Int) throws -> Data {
        guard url.isFileURL else {
            throw SecurityFailure.rejected("Nur lokale Dateien können importiert werden.")
        }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw SecurityFailure.rejected("Datei konnte nicht sicher geöffnet werden (evtl. Symlink).")
        }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(),
              info.st_size > 0,
              info.st_size <= limit else {
            throw SecurityFailure.rejected("Datei ist kein regulärer Dateieintrag oder überschreitet das Größenlimit.")
        }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n == 0 { return data }
            if n < 0 {
                if errno == EINTR { continue }
                throw SecurityFailure.rejected("Lesefehler beim Importieren der Datei.")
            }
            guard n <= limit - data.count else {
                throw SecurityFailure.rejected("Datei überschreitet das maximale Größenlimit.")
            }
            data.append(buffer, count: n)
        }
    }
}
