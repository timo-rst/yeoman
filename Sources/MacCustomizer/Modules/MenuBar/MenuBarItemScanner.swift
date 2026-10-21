import AppKit
import Combine

public enum MenuBarItemType: String, CaseIterable, Codable {
    case all = "Alle"
    case system = "macOS System"
    case thirdParty = "Drittanbieter-Apps"
    case internalModule = "MacCustomizer"
}

public struct MenuBarAppItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: MenuBarItemType
    public let bundleIdentifier: String?
    public let appPath: String?
    public let sfSymbol: String?
    public var isVisibleInMenuBar: Bool
    public var isRunning: Bool
}

public final class MenuBarItemScanner: ObservableObject {
    public static let shared = MenuBarItemScanner()
    
    @Published public var items: [MenuBarAppItem] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedFilter: MenuBarItemType = .all
    @Published public var isScanning: Bool = false
    
    private let controlCenterDomain = "com.apple.controlcenter"
    
    public init() {
        scanAll()
    }
    
    public var filteredItems: [MenuBarAppItem] {
        var result = items
        
        if selectedFilter != .all {
            result = result.filter { $0.type == selectedFilter }
        }
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.bundleIdentifier?.lowercased().contains(query) ?? false)
            }
        }
        
        return result
    }
    
    public func scanAll() {
        isScanning = true
        var scanned: [MenuBarAppItem] = []
        
        // 1. macOS Control Center System Items
        scanned.append(contentsOf: scanSystemControlCenterItems())
        
        // 2. Installed & Running Third-Party Menu Bar Apps
        scanned.append(contentsOf: scanThirdPartyApps())
        
        // 3. Internal MacCustomizer Modules
        scanned.append(contentsOf: scanInternalModules())
        
        self.items = scanned
        self.isScanning = false
    }
    
    // MARK: - System Items
    
    private func scanSystemControlCenterItems() -> [MenuBarAppItem] {
        let prefs = readControlCenterPreferences()
        
        var list: [MenuBarAppItem] = []
        
        let systemItemsDefinition: [(id: String, name: String, symbol: String, defaultVisible: Bool)] = [
            ("Sound", "Ton / Lautstärke", "speaker.wave.3.fill", true),
            ("Bluetooth", "Bluetooth", "bluetooth", true),
            ("Battery", "Batterie", "battery.100", true),
            ("BatteryShowPercentage", "Batterie Prozentanzeige", "percent", true),
            ("AirDrop", "AirDrop", "airdrop", false),
            ("Display", "Bildschirmsynchronisierung", "display", false),
            ("StageManager", "Stage Manager", "rectangle.grid.1x2", false),
            ("NowPlaying", "Aktuelle Wiedergabe", "music.note", false),
            ("KeyboardBrightness", "Tastaturhelligkeit", "keyboard", false),
            ("Hearing", "Hörhilfen", "ear", false)
        ]
        
        for def in systemItemsDefinition {
            let val = prefs[def.id] as? Int
            // In ControlCenter prefs, 18 or 12 or 1 usually indicates visible in menu bar, 8 or 0 indicates hidden
            let isVisible: Bool
            if def.id == "BatteryShowPercentage" {
                isVisible = (val == 1)
            } else if let intVal = val {
                isVisible = (intVal == 18 || intVal == 12 || intVal == 2)
            } else {
                isVisible = def.defaultVisible
            }
            
            list.append(MenuBarAppItem(
                id: "system_\(def.id)",
                name: def.name,
                type: .system,
                bundleIdentifier: "com.apple.controlcenter.\(def.id)",
                appPath: nil,
                sfSymbol: def.symbol,
                isVisibleInMenuBar: isVisible,
                isRunning: true
            ))
        }
        
        return list
    }
    
    // MARK: - Third-Party Apps
    
    private func scanThirdPartyApps() -> [MenuBarAppItem] {
        let appDirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        var scannedApps: [MenuBarAppItem] = []
        var seenBundleIds = Set<String>()
        
        // Running accessory apps
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })
        
        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appPath = (dir as NSString).appendingPathComponent(item)
                let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
                
                guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { continue }
                
                let bundleId = dict["CFBundleIdentifier"] as? String ?? ""
                guard !bundleId.isEmpty && !seenBundleIds.contains(bundleId) else { continue }
                if bundleId == "de.trst.MacCustomizer" { continue } // skip self
                
                let lsUIElement = dict["LSUIElement"] as? Bool ?? false || (dict["LSUIElement"] as? String == "1")
                let name = dict["CFBundleDisplayName"] as? String ?? dict["CFBundleName"] as? String ?? (item as NSString).deletingPathExtension
                
                // Identify menu bar apps (LSUIElement or known utilities)
                let isKnownUtility = ["Clipy", "Stats", "Ice", "Magnet", "Rectangle", "Docker", "Scroll Reverser", "MenubarX"].contains(name)
                
                if lsUIElement || isKnownUtility {
                    seenBundleIds.insert(bundleId)
                    let isRunning = runningBundleIds.contains(bundleId)
                    
                    scannedApps.append(MenuBarAppItem(
                        id: "app_\(bundleId)",
                        name: name,
                        type: .thirdParty,
                        bundleIdentifier: bundleId,
                        appPath: appPath,
                        sfSymbol: "app.badge",
                        isVisibleInMenuBar: isRunning, // If running, it contributes a status item
                        isRunning: isRunning
                    ))
                }
            }
        }
        
        return scannedApps.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
    }
    
    // MARK: - Internal Modules
    
    private func scanInternalModules() -> [MenuBarAppItem] {
        let mm = ModuleManager.shared
        return [
            MenuBarAppItem(
                id: "module_clipboard",
                name: "Clippy (MacCustomizer Clipboard)",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.clipboard",
                appPath: nil,
                sfSymbol: "doc.on.clipboard",
                isVisibleInMenuBar: mm.clipboardModule.isEnabled && mm.clipboardModule.showsDedicatedStatusItem,
                isRunning: mm.clipboardModule.isEnabled
            ),
            MenuBarAppItem(
                id: "module_stats",
                name: "System Stats Monitor (MacCustomizer)",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.systemstats",
                appPath: nil,
                sfSymbol: "gauge.with.needle",
                isVisibleInMenuBar: mm.systemStatsModule.isEnabled && mm.systemStatsModule.showsDedicatedStatusItem,
                isRunning: mm.systemStatsModule.isEnabled
            ),
            MenuBarAppItem(
                id: "module_spacing",
                name: "Menüleisten-Optimizer Schnellwähler",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.menubar",
                appPath: nil,
                sfSymbol: "arrow.left.and.line.vertical.and.arrow.right",
                isVisibleInMenuBar: mm.menuBarModule.isEnabled && mm.menuBarModule.showsDedicatedStatusItem,
                isRunning: mm.menuBarModule.isEnabled
            ),
            MenuBarAppItem(
                id: "module_hub",
                name: "MacCustomizer Haupt-Launcher",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.hub",
                appPath: nil,
                sfSymbol: "slider.horizontal.3",
                isVisibleInMenuBar: StatusItemController.shared.showsMainStatusItem,
                isRunning: true
            )
        ]
    }
    
    // MARK: - Toggle Action
    
    public func toggleItemVisibility(id: String, enable: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        
        switch item.type {
        case .system:
            let rawKey = id.replacingOccurrences(of: "system_", with: "")
            setSystemItemVisibility(key: rawKey, enable: enable)
            items[idx].isVisibleInMenuBar = enable
            
        case .thirdParty:
            if let bundleId = item.bundleIdentifier {
                if enable {
                    launchApp(bundleId: bundleId, path: item.appPath)
                    items[idx].isVisibleInMenuBar = true
                    items[idx].isRunning = true
                } else {
                    terminateApp(bundleId: bundleId)
                    items[idx].isVisibleInMenuBar = false
                    items[idx].isRunning = false
                }
            }
            
        case .internalModule:
            let mm = ModuleManager.shared
            if id == "module_clipboard" {
                mm.clipboardModule.showsDedicatedStatusItem = enable
                items[idx].isVisibleInMenuBar = enable
            } else if id == "module_stats" {
                mm.systemStatsModule.showsDedicatedStatusItem = enable
                items[idx].isVisibleInMenuBar = enable
            } else if id == "module_spacing" {
                mm.menuBarModule.showsDedicatedStatusItem = enable
                items[idx].isVisibleInMenuBar = enable
            } else if id == "module_hub" {
                StatusItemController.shared.showsMainStatusItem = enable
                items[idx].isVisibleInMenuBar = enable
            }
            
        case .all:
            break
        }
        
        objectWillChange.send()
    }
    
    // MARK: - Helpers
    
    private func setSystemItemVisibility(key: String, enable: Bool) {
        let value: Int
        if key == "BatteryShowPercentage" {
            value = enable ? 1 : 0
        } else if key == "Battery" {
            value = enable ? 12 : 8
        } else {
            value = enable ? 18 : 8
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "write", controlCenterDomain, key, "-int", "\(value)"]
        try? process.run()
        process.waitUntilExit()
        
        MenuBarSpacingManager.shared.restartControlCenter()
    }
    
    private func launchApp(bundleId: String, path: String?) {
        if let path = path {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
    
    private func terminateApp(bundleId: String) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
        for app in apps {
            app.terminate()
        }
    }
    
    private func readControlCenterPreferences() -> [String: Any] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "export", controlCenterDomain, "-"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return plist
            }
        } catch {
            return [:]
        }
        return [:]
    }
}
