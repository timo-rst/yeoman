import Foundation
import Darwin

public enum TerminalShellTarget: String, Codable, CaseIterable, Identifiable {
    case zsh
    case bash
    case fish
    case tmux

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zsh: return "Zsh"
        case .bash: return "Bash"
        case .fish: return "Fish"
        case .tmux: return "tmux"
        }
    }
}

public struct TerminalShellStatus: Equatable {
    public let target: TerminalShellTarget
    public let isInstalled: Bool
    public let configPath: String

    public init(target: TerminalShellTarget, isInstalled: Bool, configPath: String) {
        self.target = target
        self.isInstalled = isInstalled
        self.configPath = configPath
    }
}

/// Safe managed-block installer/uninstaller for Zsh, Bash, Fish, and tmux.
public enum TerminalSaverShellIntegrator {
    public static let startMarker = "# >>> Yeoman Terminal Saver >>>"
    public static let endMarker = "# <<< Yeoman Terminal Saver <<<"
    private static let maxConfigFileBytes = 2 * 1_048_576

    public static func configURL(for target: TerminalShellTarget, homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch target {
        case .zsh:
            return homeDirectoryURL.appendingPathComponent(".zshrc")
        case .bash:
            return homeDirectoryURL.appendingPathComponent(".bashrc")
        case .fish:
            return homeDirectoryURL
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("fish", isDirectory: true)
                .appendingPathComponent("conf.d", isDirectory: true)
                .appendingPathComponent("yeoman_terminal_saver.fish")
        case .tmux:
            return homeDirectoryURL.appendingPathComponent(".tmux.conf")
        }
    }

    public static func snippet(for target: TerminalShellTarget, helperPath: String, timeoutSeconds: Int) throws -> String {
        let cleanHelper = helperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHelper.isEmpty,
              cleanHelper.hasPrefix("/"),
              !cleanHelper.contains("'"),
              !cleanHelper.contains("\""),
              !cleanHelper.contains("\n"),
              !cleanHelper.contains("\r"),
              !cleanHelper.utf8.contains(0) else {
            throw SecurityFailure.rejected("Ungültiger Helper-Pfad für Shell-Integration.")
        }

        let timeout = TerminalSaverPolicy.clamp(timeoutSeconds, TerminalSaverPolicy.idleTimeoutRange)
        let body: String

        switch target {
        case .zsh:
            body = """
            TMOUT=\(timeout)
            TRAPALRM() {
                if [[ -t 0 && -t 1 && -z "${YEOMAN_SAVER_DISABLE:-}" && -x '\(cleanHelper)' ]]; then
                    '\(cleanHelper)' --run --source zsh
                    if whence zle >/dev/null 2>&1 && zle; then
                        zle reset-prompt
                    fi
                fi
            }
            """
        case .bash:
            body = """
            __yeoman_saver_pid=""
            __yeoman_saver_cancel() {
                if [[ -n "${__yeoman_saver_pid:-}" ]]; then
                    kill "${__yeoman_saver_pid}" 2>/dev/null || true
                    wait "${__yeoman_saver_pid}" 2>/dev/null || true
                    __yeoman_saver_pid=""
                fi
            }
            __yeoman_saver_run() {
                __yeoman_saver_cancel
                if [[ -t 0 && -t 1 && -z "${YEOMAN_SAVER_DISABLE:-}" && -x '\(cleanHelper)' ]]; then
                    '\(cleanHelper)' --run --source bash
                fi
            }
            __yeoman_saver_arm() {
                __yeoman_saver_cancel
                if [[ -t 0 && -t 1 && -z "${YEOMAN_SAVER_DISABLE:-}" && -x '\(cleanHelper)' ]]; then
                    (sleep \(timeout) && kill -USR1 $$ 2>/dev/null) &
                    __yeoman_saver_pid=$!
                    disown "${__yeoman_saver_pid}" 2>/dev/null || true
                fi
            }
            trap '__yeoman_saver_run' USR1
            trap '__yeoman_saver_cancel' DEBUG EXIT
            if [[ "${PROMPT_COMMAND:-}" != *"__yeoman_saver_arm"* ]]; then
                PROMPT_COMMAND="__yeoman_saver_arm${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
            fi
            """
        case .fish:
            body = """
            set -g __yeoman_saver_pid ""
            function __yeoman_saver_cancel --on-event fish_preexec --on-event fish_exit
                if test -n "$__yeoman_saver_pid"
                    kill $__yeoman_saver_pid 2>/dev/null; or true
                    set -g __yeoman_saver_pid ""
                end
            end
            function __yeoman_saver_run --on-signal USR1
                __yeoman_saver_cancel
                if isatty stdin; and isatty stdout; and not set -q YEOMAN_SAVER_DISABLE; and test -x '\(cleanHelper)'
                    '\(cleanHelper)' --run --source fish
                    commandline -f repaint 2>/dev/null; or true
                end
            end
            function __yeoman_saver_arm --on-event fish_prompt
                __yeoman_saver_cancel
                if isatty stdin; and isatty stdout; and not set -q YEOMAN_SAVER_DISABLE; and test -x '\(cleanHelper)'
                    sh -c "sleep \(timeout) && kill -USR1 $fish_pid 2>/dev/null" &
                    set -g __yeoman_saver_pid $last_pid
                end
            end
            """
        case .tmux:
            body = """
            set -g lock-after-time \(timeout)
            set -g lock-command "'\(cleanHelper)' --run --source tmux"
            """
        }

        return "\(startMarker)\n\(body)\n\(endMarker)"
    }

    public static func hasManagedBlock(in content: String) -> Bool {
        guard let startRange = content.range(of: startMarker),
              let endRange = content.range(of: endMarker),
              startRange.upperBound <= endRange.lowerBound else {
            return false
        }
        return true
    }

    public static func upsertManagedBlock(in existing: String, block: String) -> String {
        if let startRange = existing.range(of: startMarker),
           let endRange = existing.range(of: endMarker),
           startRange.lowerBound <= endRange.lowerBound {
            var updated = existing
            updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: block)
            return updated
        }

        if existing.isEmpty {
            return block + "\n"
        }
        let separator = existing.hasSuffix("\n") ? "\n" : "\n\n"
        return existing + separator + block + "\n"
    }

    public static func removeManagedBlock(from existing: String) -> String {
        guard let startRange = existing.range(of: startMarker),
              let endRange = existing.range(of: endMarker),
              startRange.lowerBound <= endRange.lowerBound else {
            return existing
        }

        var lower = startRange.lowerBound
        var upper = endRange.upperBound

        // Consume trailing newline if present.
        if upper < existing.endIndex, existing[upper] == "\n" {
            upper = existing.index(after: upper)
        }
        // Consume preceding blank separator line if we appended after content.
        while lower > existing.startIndex {
            let prev = existing.index(before: lower)
            if existing[prev] == "\n" {
                lower = prev
            } else {
                break
            }
        }
        // Preserve a single newline separator between before and after if both exist.
        var result = existing
        result.removeSubrange(lower..<upper)
        if !result.isEmpty && !result.hasSuffix("\n") && upper == existing.endIndex && lower > existing.startIndex {
            result.append("\n")
        }
        return result
    }

    public static func status(for target: TerminalShellTarget, homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> TerminalShellStatus {
        let url = configURL(for: target, homeDirectoryURL: homeDirectoryURL)
        guard let content = try? readRegularConfigIfExists(at: url) else {
            return TerminalShellStatus(target: target, isInstalled: false, configPath: url.path)
        }
        return TerminalShellStatus(target: target, isInstalled: hasManagedBlock(in: content), configPath: url.path)
    }

    public static func install(
        target: TerminalShellTarget,
        helperPath: String,
        timeoutSeconds: Int,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let block = try snippet(for: target, helperPath: helperPath, timeoutSeconds: timeoutSeconds)
        let url = configURL(for: target, homeDirectoryURL: homeDirectoryURL)

        if target == .fish {
            try ensureSafeDirectoryChain(url.deletingLastPathComponent(), stoppingAt: homeDirectoryURL)
            let data = Data((block + "\n").utf8)
            try atomicWriteConfig(data, to: url, mode: 0o644)
            return
        }

        let existing = try readRegularConfigIfExists(at: url) ?? ""
        if !existing.isEmpty {
            createOneTimeBackupIfMissing(for: url, content: existing)
        }
        let updated = upsertManagedBlock(in: existing, block: block)
        try atomicWriteConfig(Data(updated.utf8), to: url, mode: 0o644)
    }

    public static func uninstall(
        target: TerminalShellTarget,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let url = configURL(for: target, homeDirectoryURL: homeDirectoryURL)
        if target == .fish {
            var st = stat()
            guard Darwin.lstat(url.path, &st) == 0 else {
                if errno == ENOENT { return }
                throw SecurityFailure.rejected("Fish-Konfiguration konnte nicht geprüft werden.")
            }
            guard (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == geteuid() else {
                throw SecurityFailure.rejected("Fish-Datei ist kein regulärer Benutzereintrag.")
            }
            guard Darwin.unlink(url.path) == 0 else {
                throw SecurityFailure.rejected("Fish-Konfiguration konnte nicht entfernt werden.")
            }
            return
        }

        guard let existing = try readRegularConfigIfExists(at: url),
              hasManagedBlock(in: existing) else {
            return
        }
        let cleaned = removeManagedBlock(from: existing)
        try atomicWriteConfig(Data(cleaned.utf8), to: url, mode: 0o644)
    }

    public static func syncInstalledTargets(
        helperPath: String,
        timeoutSeconds: Int,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        for target in TerminalShellTarget.allCases {
            if status(for: target, homeDirectoryURL: homeDirectoryURL).isInstalled {
                try install(target: target, helperPath: helperPath, timeoutSeconds: timeoutSeconds, homeDirectoryURL: homeDirectoryURL)
            }
        }
    }

    private static func readRegularConfigIfExists(at url: URL) throws -> String? {
        var st = stat()
        if Darwin.lstat(url.path, &st) != 0 {
            if errno == ENOENT { return nil }
            throw SecurityFailure.rejected("Konfigurationsdatei konnte nicht geprüft werden.")
        }
        guard (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == geteuid() else {
            throw SecurityFailure.rejected("Konfigurationsdatei ist ein Symlink oder kein regulärer Dateieintrag.")
        }
        guard st.st_size >= 0, st.st_size <= maxConfigFileBytes else {
            throw SecurityFailure.rejected("Konfigurationsdatei überschreitet das maximale Größenlimit.")
        }

        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw SecurityFailure.rejected("Konfigurationsdatei konnte nicht geöffnet werden.")
        }
        defer { Darwin.close(fd) }

        var data = Data()
        data.reserveCapacity(Int(st.st_size))
        var buf = [UInt8](repeating: 0, count: 16384)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR { continue }
                throw SecurityFailure.rejected("Lesefehler in Konfigurationsdatei.")
            }
            guard n <= maxConfigFileBytes - data.count else {
                throw SecurityFailure.rejected("Konfigurationsdatei überschreitet das Limit.")
            }
            data.append(buf, count: n)
        }

        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw SecurityFailure.rejected("Konfigurationsdatei enthält ungültiges UTF-8 oder NUL-Bytes.")
        }
        return text
    }

    private static func ensureSafeDirectoryChain(_ dirURL: URL, stoppingAt rootURL: URL) throws {
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        var current = dirURL.standardizedFileURL
        let stop = rootURL.standardizedFileURL
        while current.path.count >= stop.path.count {
            var st = stat()
            guard Darwin.lstat(current.path, &st) == 0,
                  (st.st_mode & S_IFMT) == S_IFDIR,
                  st.st_uid == geteuid() else {
                throw SecurityFailure.rejected("Unsicheres Konfigurationsverzeichnis.")
            }
            if current.path == stop.path { break }
            current = current.deletingLastPathComponent()
        }
    }

    private static func createOneTimeBackupIfMissing(for url: URL, content: String) {
        let backupPath = url.path + ".yeoman.bak"
        let fd = Darwin.open(backupPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return } // Never overwrite existing backup.
        defer { Darwin.close(fd) }
        let data = Data(content.utf8)
        _ = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress, raw.count > 0 else { return 0 }
            return Darwin.write(fd, base, raw.count)
        }
        _ = fsync(fd)
    }

    private static func atomicWriteConfig(_ data: Data, to url: URL, mode: mode_t) throws {
        var existingMode = mode
        var st = stat()
        if Darwin.lstat(url.path, &st) == 0 {
            guard (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == geteuid() else {
                throw SecurityFailure.rejected("Zieldatei ist kein regulärer Dateieintrag.")
            }
            existingMode = st.st_mode & 0o777
        }

        let parent = url.deletingLastPathComponent()
        let tempURL = parent.appendingPathComponent(".\(url.lastPathComponent).yeoman-tmp-\(UUID().uuidString)")
        let fd = Darwin.open(tempURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, existingMode)
        guard fd >= 0 else {
            throw SecurityFailure.rejected("Temporäre Konfigurationsdatei konnte nicht erstellt werden.")
        }
        var committed = false
        defer {
            Darwin.close(fd)
            if !committed { _ = Darwin.unlink(tempURL.path) }
        }

        try data.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: written), raw.count - written)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw SecurityFailure.rejected("Schreibfehler in Konfigurationsdatei.") }
                written += n
            }
        }
        _ = fchmod(fd, existingMode)
        guard fsync(fd) == 0, Darwin.rename(tempURL.path, url.path) == 0 else {
            throw SecurityFailure.rejected("Konfigurationsdatei konnte nicht atomar ersetzt werden.")
        }
        committed = true
    }
}
