import Foundation
import AppKit
import Combine

public struct GitHubRelease: Codable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let prerelease: Bool
    public let draft: Bool
    public let assets: [GitHubReleaseAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }
}

public struct GitHubReleaseAsset: Codable {
    public let name: String
    public let size: Int
    public let browserDownloadUrl: String
    public let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
        case contentType = "content_type"
    }
}

public enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, notes: String, downloadUrl: URL?, htmlUrl: URL)
    case downloading(progress: Double)
    case installing
    case failed(message: String)
}

public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()
    public let repoOwner = "timo-rst"
    public let repoName = "mac_customizer"
    @Published public var status: UpdateStatus = .idle
    @Published public var lastCheckedDate: Date?
    @Published public var autoCheckForUpdates: Bool {
        didSet { defaults.set(autoCheckForUpdates, forKey: "update_auto_check_enabled") }
    }
    @Published public var githubToken: String = "" {
        didSet {
            guard !loadingToken else { return }
            do {
                let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if token.isEmpty { try secrets.delete("github-token") }
                else {
                    let safeToken = try SecretMigration.validatedToken(token)
                    try secrets.write(Data(safeToken.utf8), account: "github-token")
                }
                defaults.removeObject(forKey: "update_github_token")
            } catch { status = .failed(message: error.localizedDescription) }
        }
    }
    @Published public var availableRelease: GitHubRelease?
    private let defaults: UserDefaults
    private let secrets: SecretStore
    private var loadingToken = false
    private var busy = false
    private var periodicCheckTimer: AnyCancellable?
    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2"
    }
    public init(defaults: UserDefaults = .standard, secrets: SecretStore = SecureFileSecretStore()) {
        self.defaults = defaults; self.secrets = secrets
        autoCheckForUpdates = defaults.object(forKey: "update_auto_check_enabled") as? Bool ?? true
        lastCheckedDate = defaults.object(forKey: "update_last_checked_date") as? Date
        loadingToken = true
        do { githubToken = try SecretMigration.token(defaults: defaults, secrets: secrets) }
        catch { /* token is optional for public releases */ }
        loadingToken = false
    }
    public func startAutoCheckIfEnabled() {
        do { try UpdateInstaller.acknowledgeLaunch(target: Bundle.main.bundleURL) }
        catch { status = .failed(message: "Update-Sicherung konnte nicht bestätigt werden: \(error.localizedDescription)") }
        guard autoCheckForUpdates else { return }
        periodicCheckTimer = Timer.publish(every: 12 * 3600, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            if self?.autoCheckForUpdates == true { self?.checkForUpdates(silent: true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.autoCheckForUpdates else { return }
            if let date = self.lastCheckedDate, (0..<21600).contains(Date().timeIntervalSince(date)) { return }
            self.checkForUpdates(silent: true)
        }
    }
    public func checkForUpdates(silent: Bool = false) {
        guard !busy else { return }
        busy = true
        if !silent { status = .checking }
        var request = URLRequest(url: UpdateURLPolicy.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Yeoman/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if !githubToken.isEmpty {
            do { request.setValue("Bearer " + (try SecretMigration.validatedToken(githubToken)), forHTTPHeaderField: "Authorization") }
            catch { busy = false; status = .failed(message: error.localizedDescription); return }
        }
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await UpdateDownload(limit: 1_048_576, apiRequest: true).fetch(request)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !release.draft, !release.prerelease, let remote = ReleaseVersion(release.tagName),
                      let current = ReleaseVersion(currentVersion) else { throw SecurityFailure.rejected("Ungültige Release-Version.") }
                lastCheckedDate = Date(); defaults.set(lastCheckedDate, forKey: "update_last_checked_date")
                availableRelease = release
                guard remote > current else { status = .upToDate; return }
                let asset = release.assets.first { $0.name == "Yeoman.zip" && $0.size > 0 && $0.size <= 128 * 1_048_576 }
                let url = asset.flatMap { URL(string: $0.browserDownloadUrl) }.flatMap { UpdateURLPolicy.asset($0) ? $0 : nil }
                let page = URL(string: release.htmlUrl).flatMap { UpdateURLPolicy.releasePage($0) ? $0 : nil }
                    ?? URL(string: "https://github.com/timo-rst/mac_customizer/releases")!
                status = .updateAvailable(version: release.tagName, notes: String((release.body ?? "").prefix(32768)), downloadUrl: url, htmlUrl: page)
            } catch { if !silent { status = .failed(message: error.localizedDescription) } }
        }
    }
    public static func isTrustedUpdateHost(_ url: URL) -> Bool { UpdateURLPolicy.asset(url) }
    public func downloadAndInstall(from url: URL) {
        guard !busy else { return }
        do { _ = try UpdateTrust.key() } catch { status = .failed(message: error.localizedDescription); return }
        guard UpdateURLPolicy.asset(url), url.lastPathComponent == "Yeoman.zip" else {
            status = .failed(message: "Nicht erlaubtes Updatearchiv."); return
        }
        busy = true; status = .downloading(progress: 0)
        Task { @MainActor in
            var staging: SecureDirectory?
            var handedOff = false
            defer {
                busy = false
                if !handedOff, let staging { try? FileManager.default.removeItem(at: staging.url) }
            }
            do {
                let key = try UpdateTrust.key()
                let manifestURL = url.deletingLastPathComponent().appendingPathComponent("Yeoman.update.json")
                let manifestData = try await UpdateDownload(limit: 32768, apiRequest: false).fetch(URLRequest(url: manifestURL))
                let signed = try JSONDecoder().decode(SignedUpdate.self, from: manifestData)
                let metadata = try signed.verified(key: key, current: currentVersion)
                guard ReleaseVersion(metadata.version) == ReleaseVersion(url.deletingLastPathComponent().lastPathComponent) else {
                    throw SecurityFailure.rejected("Release und signierte Version stimmen nicht überein.")
                }
                let archive = try await UpdateDownload(limit: metadata.size, apiRequest: false).fetch(URLRequest(url: url))
                try SignedUpdate.verifyArchive(archive, metadata: metadata)
                let directory = try SecureDirectory.temporary(); staging = directory
                try directory.write(archive, name: "update.zip")
                try directory.write(manifestData, name: "update.json")
                guard let identity = ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier) else {
                    throw SecurityFailure.rejected("Prozessidentität nicht verfügbar.")
                }
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/YeomanInstaller")
                guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                    throw SecurityFailure.rejected("Installer fehlt. Bitte ein vollständiges App-Bundle verwenden.")
                }
                status = .installing
                let process = Process()
                process.executableURL = helper
                process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                process.arguments = [directory.url.path, Bundle.main.bundleURL.path,
                                     try JSONEncoder().encode(identity).base64EncodedString()]
                try process.run()
                let deadline = ProcessInfo.processInfo.systemUptime + 40
                while !(try directory.exists("helper-ready")) {
                    guard process.isRunning else { throw SecurityFailure.rejected("Installer-Vorprüfung fehlgeschlagen; Yeoman bleibt geöffnet.") }
                    guard ProcessInfo.processInfo.systemUptime < deadline else {
                        process.terminate()
                        let stopDeadline = ProcessInfo.processInfo.systemUptime + 2
                        while process.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline {
                            try await Task.sleep(nanoseconds: 50_000_000)
                        }
                        // Preserve staging if a stuck owned helper may still be reading it.
                        handedOff = process.isRunning
                        throw SecurityFailure.rejected("Installer-Vorprüfung hat das Zeitlimit überschritten.")
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                handedOff = true
                NSApplication.shared.terminate(nil)
            } catch { status = .failed(message: error.localizedDescription) }
        }
    }
    public static func cleanVersionString(_ version: String) -> String {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.lowercased().hasPrefix("v") ? String(value.dropFirst()) : value
    }
    public static func isVersion(_ remote: String, newerThan current: String) -> Bool {
        guard let r = ReleaseVersion(remote), let c = ReleaseVersion(current) else { return false }
        return r > c
    }
}
