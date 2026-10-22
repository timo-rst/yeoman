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
    
    // Repository information
    public let repoOwner = "timo-rst"
    public let repoName = "mac_customizer"
    
    // Published UI state
    @Published public var status: UpdateStatus = .idle
    @Published public var lastCheckedDate: Date? {
        didSet {
            if let date = lastCheckedDate {
                UserDefaults.standard.set(date, forKey: "update_last_checked_date")
            }
        }
    }
    
    @Published public var autoCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckForUpdates, forKey: "update_auto_check_enabled")
        }
    }
    
    @Published public var githubToken: String {
        didSet {
            let trimmed = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: "update_github_token")
            } else {
                UserDefaults.standard.set(trimmed, forKey: "update_github_token")
            }
        }
    }
    
    @Published public var availableRelease: GitHubRelease?
    
    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var periodicCheckTimer: AnyCancellable?
    
    public var currentVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return version
        }
        return "0.2.0"
    }
    
    private init() {
        self.autoCheckForUpdates = UserDefaults.standard.object(forKey: "update_auto_check_enabled") as? Bool ?? true
        self.lastCheckedDate = UserDefaults.standard.object(forKey: "update_last_checked_date") as? Date
        self.githubToken = UserDefaults.standard.string(forKey: "update_github_token") ?? ""
        
        setupPeriodicCheck()
    }
    
    // MARK: - Auto-Check Scheduling
    
    public func startAutoCheckIfEnabled() {
        guard autoCheckForUpdates else { return }
        // Delay initial check slightly so app startup remains instant
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.autoCheckForUpdates else { return }
            
            // Only check if last check was more than 6 hours ago
            if let last = self.lastCheckedDate, Date().timeIntervalSince(last) < 6 * 3600 {
                return
            }
            self.checkForUpdates(silent: true)
        }
    }
    
    private func setupPeriodicCheck() {
        // Run check timer every 12 hours
        periodicCheckTimer = Timer.publish(every: 12 * 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.autoCheckForUpdates else { return }
                self.checkForUpdates(silent: true)
            }
    }
    
    // MARK: - Check for Updates
    
    public func checkForUpdates(silent: Bool = false) {
        if !silent {
            self.status = .checking
        }
        
        let endpointString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: endpointString) else {
            if !silent {
                self.status = .failed(message: "Ungültige Update-URL")
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Yeoman/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lastCheckedDate = Date()
                
                if let error = error {
                    if !silent {
                        self.status = .failed(message: error.localizedDescription)
                    }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 404 {
                        if !silent {
                            self.status = .failed(message: "Keine Releases gefunden (Repository evtl. privat oder noch kein Release veröffentlicht).")
                        }
                        return
                    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        if !silent {
                            self.status = .failed(message: "GitHub API Zugriff verweigert (Status \(httpResponse.statusCode)).")
                        }
                        return
                    } else if httpResponse.statusCode != 200 {
                        if !silent {
                            self.status = .failed(message: "GitHub meldete Fehler (Status \(httpResponse.statusCode)).")
                        }
                        return
                    }
                }
                
                guard let data = data else {
                    if !silent {
                        self.status = .failed(message: "Keine Daten von GitHub empfangen.")
                    }
                    return
                }
                
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    self.availableRelease = release
                    
                    let remoteVersion = self.cleanVersionString(release.tagName)
                    let current = self.cleanVersionString(self.currentVersion)
                    
                    if self.isVersion(remoteVersion, newerThan: current) {
                        let downloadUrl = release.assets.first(where: {
                            $0.name.hasSuffix(".zip") || $0.name.hasSuffix(".dmg")
                        }).flatMap { URL(string: $0.browserDownloadUrl) }
                        
                        let htmlUrl = URL(string: release.htmlUrl) ?? URL(string: "https://github.com/\(self.repoOwner)/\(self.repoName)")!
                        let notes = release.body ?? release.name ?? "Neue Version verfügbar."
                        
                        self.status = .updateAvailable(
                            version: release.tagName,
                            notes: notes,
                            downloadUrl: downloadUrl,
                            htmlUrl: htmlUrl
                        )
                    } else {
                        self.status = .upToDate
                    }
                } catch {
                    if !silent {
                        self.status = .failed(message: "Fehler beim Parsen der Release-Daten: \(error.localizedDescription)")
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Download & Install
    
    public func downloadAndInstall(from downloadUrl: URL) {
        // Enforce secure HTTPS protocol
        guard downloadUrl.scheme?.lowercased() == "https" else {
            self.status = .failed(message: "Sicherheitsprüfung fehlgeschlagen: Unsichere Download-URL (nur HTTPS erlaubt).")
            return
        }
        
        // Whitelist verified GitHub release distribution hosts
        let trustedHosts = [
            "github.com",
            "api.github.com",
            "objects.githubusercontent.com",
            "github-releases.githubusercontent.com",
            "github-production-release-asset-2e65be.s3.amazonaws.com"
        ]
        
        guard let host = downloadUrl.host?.lowercased(),
              trustedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            self.status = .failed(message: "Sicherheitsprüfung fehlgeschlagen: Nicht autorisierter Download-Host (\(downloadUrl.host ?? "unbekannt")).")
            return
        }
        
        self.status = .downloading(progress: 0.0)
        
        let session = URLSession(configuration: .default)
        downloadTask = session.downloadTask(with: downloadUrl) { [weak self] tempLocalUrl, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.status = .failed(message: "Download fehlgeschlagen: \(error.localizedDescription)")
                    return
                }
                
                guard let tempLocalUrl = tempLocalUrl else {
                    self.status = .failed(message: "Download-Datei konnte nicht gespeichert werden.")
                    return
                }
                
                self.installDownloadedArchive(from: tempLocalUrl)
            }
        }
        
        observation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                if case .downloading = self?.status {
                    self?.status = .downloading(progress: progress.fractionCompleted)
                }
            }
        }
        
        downloadTask?.resume()
    }
    
    private func installDownloadedArchive(from localZipUrl: URL) {
        self.status = .installing
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            let extractDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            
            do {
                try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
                
                // Unpack with ditto (native macOS archive extractor preserving permissions and symlinks)
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", localZipUrl.path, extractDir.path]
                try ditto.run()
                ditto.waitUntilExit()
                
                // Find Yeoman.app inside extracted directory
                let contents = try fileManager.contentsOfDirectory(atPath: extractDir.path)
                var newAppPath: String?
                
                if let appName = contents.first(where: { $0.hasSuffix(".app") }) {
                    newAppPath = (extractDir.path as NSString).appendingPathComponent(appName)
                } else {
                    // Check subfolders
                    for sub in contents {
                        let subPath = (extractDir.path as NSString).appendingPathComponent(sub)
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue {
                            if let inner = try? fileManager.contentsOfDirectory(atPath: subPath),
                               let found = inner.first(where: { $0.hasSuffix(".app") }) {
                                newAppPath = (subPath as NSString).appendingPathComponent(found)
                                break
                            }
                        }
                    }
                }
                
                guard let validNewAppPath = newAppPath else {
                    DispatchQueue.main.async {
                        self.status = .failed(message: "Das Archiv enthielt keine gültige Yeoman.app.")
                    }
                    return
                }
                
                // Verify bundle identifier of the extracted app before applying
                guard let bundle = Bundle(path: validNewAppPath),
                      bundle.bundleIdentifier == "de.trst.Yeoman" || bundle.bundleIdentifier == "de.trst.MacCustomizer" || bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    DispatchQueue.main.async {
                        self.status = .failed(message: "Sicherheitsprüfung fehlgeschlagen: Die extrahierte App besitzt keine gültige Yeoman Bundle-ID.")
                    }
                    return
                }
                
                // Remove quarantine attribute
                let xattr = Process()
                xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattr.arguments = ["-cr", validNewAppPath]
                try? xattr.run()
                xattr.waitUntilExit()
                
                let targetBundlePath = Bundle.main.bundleURL.path
                let currentPid = ProcessInfo.processInfo.processIdentifier
                
                // Create a standalone relaunch script taking arguments safely without shell string interpolation
                let updateScriptPath = fileManager.temporaryDirectory.appendingPathComponent("yeoman_update.sh").path
                let scriptContent = """
                #!/bin/bash
                PID="$1"
                NEW_APP="$2"
                TARGET_BUNDLE="$3"
                EXTRACT_DIR="$4"

                while kill -0 "$PID" 2>/dev/null; do
                    sleep 0.2
                done

                rm -rf "$TARGET_BUNDLE"
                cp -R "$NEW_APP" "$TARGET_BUNDLE"
                xattr -cr "$TARGET_BUNDLE"
                open "$TARGET_BUNDLE"
                rm -rf "$EXTRACT_DIR"
                rm -f "$0"
                """
                
                try scriptContent.write(toFile: updateScriptPath, atomically: true, encoding: .utf8)
                
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["700", updateScriptPath]
                try? chmod.run()
                chmod.waitUntilExit()
                
                // Launch the update script detached with safe positional parameters
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/bash")
                relaunch.arguments = [updateScriptPath, "\(currentPid)", validNewAppPath, targetBundlePath, extractDir.path]
                try relaunch.run()
                
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.status = .failed(message: "Installation fehlgeschlagen: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Version Comparison
    
    private func cleanVersionString(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased().hasPrefix("v") {
            v.removeFirst()
        }
        return v
    }
    
    private func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteComponents.count, currentComponents.count)
        for i in 0..<maxCount {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let c = i < currentComponents.count ? currentComponents[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
