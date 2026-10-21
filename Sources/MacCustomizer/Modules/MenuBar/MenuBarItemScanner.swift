import AppKit
import Combine

public enum MenuBarItemType: String, CaseIterable, Codable {
    case all = "Alle"
    case system = "macOS System"
    case thirdParty = "Drittanbieter"
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
        // Asynchronously populate initial items without blocking singleton creation or re-entering runloops
        DispatchQueue.main.async { [weak self] in
            self?.scanAll()
        }
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
        guard !isScanning else { return }
        isScanning = true
        
        // Scan internal in-memory modules on current thread safely
        let internalItems = scanInternalModules()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var scanned: [MenuBarAppItem] = []
            
            // 1. macOS Control Center System Items (uses native CFPreferences, zero sub-processes)
            scanned.append(contentsOf: self.scanSystemControlCenterItems())
            
            // 2. Installed & Running Third-Party Menu Bar Apps (filesystem scan)
            scanned.append(contentsOf: self.scanThirdPartyApps())
            
            // 3. Internal MacCustomizer Modules
            scanned.append(contentsOf: internalItems)
            
            DispatchQueue.main.async {
                self.items = scanned
                self.isScanning = false
            }
        }
    }
    
    // MARK: - System Items
    
    private func scanSystemControlCenterItems() -> [MenuBarAppItem] {
        let prefs = readControlCenterPreferences()
        
        var list: [MenuBarAppItem] = []
        
        let systemItemsDefinition: [(id: String, name: String, symbol: String, defaultVisible: Bool)] = [
            ("Sound", "Ton / Lautstärke", "speaker.wave.3.fill", true),
            ("Bluetooth", "Bluetooth", "NSBluetoothTemplate", true),
            ("Battery", "Batterie", "battery.100", true),
            ("BatteryShowPercentage", "Batterie Prozentanzeige", "percent", true),
            ("AirDrop", "AirDrop", "dot.radiowaves.left.and.right", false),
            ("Display", "Bildschirmsynchronisierung", "display", false),
            ("StageManager", "Stage Manager", "rectangle.grid.1x2", false),
            ("NowPlaying", "Aktuelle Wiedergabe", "music.note", false),
            ("KeyboardBrightness", "Tastaturhelligkeit", "keyboard", false),
            ("Hearing", "Hörhilfen", "ear", false)
        ]
        
        for def in systemItemsDefinition {
            let val = prefs[def.id] as? Int
            // In ControlCenter prefs, 18 or 2 indicates visible in menu bar, 8 indicates hidden
            let isVisible: Bool
            if def.id == "BatteryShowPercentage" {
                if let boolVal = prefs[def.id] as? Bool {
                    isVisible = boolVal
                } else if let intVal = val {
                    isVisible = (intVal == 1)
                } else {
                    isVisible = def.defaultVisible
                }
            } else if let intVal = val {
                isVisible = (intVal == 18 || intVal == 2)
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
                let isKnownUtility = ["Magnet", "Rectangle", "Docker", "Alfred", "Raycast", "Slack"].contains(name)
                
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
        var list: [MenuBarAppItem] = [
            MenuBarAppItem(
                id: "module_clipboard",
                name: "Zwischenablage",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.clipboard",
                appPath: nil,
                sfSymbol: "doc.on.clipboard",
                isVisibleInMenuBar: mm.clipboardModule.isEnabled && mm.clipboardModule.showsDedicatedStatusItem,
                isRunning: mm.clipboardModule.isEnabled
            ),
            MenuBarAppItem(
                id: "module_stats",
                name: "System-Monitor",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.systemstats",
                appPath: nil,
                sfSymbol: "gauge.with.needle",
                isVisibleInMenuBar: mm.systemStatsModule.isEnabled && mm.systemStatsModule.showsDedicatedStatusItem,
                isRunning: mm.systemStatsModule.isEnabled
            ),
            MenuBarAppItem(
                id: "module_spacing",
                name: "Menüleisten-Abstände",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.menubar",
                appPath: nil,
                sfSymbol: "arrow.left.and.line.vertical.and.arrow.right",
                isVisibleInMenuBar: mm.menuBarModule.isEnabled && mm.menuBarModule.showsDedicatedStatusItem,
                isRunning: mm.menuBarModule.isEnabled
            ),
            MenuBarAppItem(
                id: "module_hub",
                name: "MacCustomizer Menü",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.hub",
                appPath: nil,
                sfSymbol: "slider.horizontal.3",
                isVisibleInMenuBar: StatusItemController.shared.showsMainStatusItem,
                isRunning: true
            ),
            MenuBarAppItem(
                id: "module_scrollreverser",
                name: "Scroll-Richtung (Maus)",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.scrollreverser",
                appPath: nil,
                sfSymbol: "computermouse",
                isVisibleInMenuBar: mm.scrollReverserModule.isEnabled && mm.scrollReverserModule.showsDedicatedStatusItem,
                isRunning: mm.scrollReverserModule.isEnabled
            )
        ]
        
        // Include individual Web-Widgets
        for widget in mm.webPanelModule.widgets {
            list.append(MenuBarAppItem(
                id: "web_widget_\(widget.id.uuidString)",
                name: "\(widget.title) (Web-Widget)",
                type: .internalModule,
                bundleIdentifier: "de.trst.MacCustomizer.webwidget.\(widget.id.uuidString)",
                appPath: nil,
                sfSymbol: widget.iconName.isEmpty ? "globe" : widget.iconName,
                isVisibleInMenuBar: mm.webPanelModule.isEnabled && mm.webPanelModule.showsDedicatedStatusItem && widget.isEnabled,
                isRunning: mm.webPanelModule.isEnabled && widget.isEnabled
            ))
        }
        
        return list
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
            } else if id == "module_scrollreverser" {
                mm.scrollReverserModule.showsDedicatedStatusItem = enable
                items[idx].isVisibleInMenuBar = enable
            } else if id.hasPrefix("web_widget_") {
                let uuidStr = id.replacingOccurrences(of: "web_widget_", with: "")
                if let uuid = UUID(uuidString: uuidStr) {
                    mm.webPanelModule.toggleWidget(id: uuid, isEnabled: enable)
                    items[idx].isVisibleInMenuBar = enable
                }
            }
            mm.recreateAllStatusItems()
            
        case .all:
            break
        }
        
        objectWillChange.send()
    }
    
    @Published public var hasPendingSystemReload: Bool = false
    private var reloadWorkItem: DispatchWorkItem?
    
    // MARK: - Helpers
    
    private func setSystemItemVisibility(key: String, enable: Bool) {
        if key == "BatteryShowPercentage" {
            CFPreferencesSetValue(key as CFString, (enable ? true : false) as CFPropertyList, controlCenterDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        } else {
            let value = enable ? 18 : 8
            CFPreferencesSetValue(key as CFString, value as CFPropertyList, controlCenterDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(controlCenterDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        
        // Post distributed notifications to ControlCenter quietly
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.controlcenter.itemchanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.systemuiserver.itemchanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        self.hasPendingSystemReload = true
    }
    
    public func scheduleSystemReload() {
        self.hasPendingSystemReload = true
    }
    
    public func applySystemChanges() {
        reloadWorkItem?.cancel()
        MenuBarSpacingManager.shared.restartControlCenter()
        self.hasPendingSystemReload = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scanAll()
            ModuleManager.shared.ensureAllStatusItemsVisible()
        }
    }
    
    public func openSystemControlCenterSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
        NSWorkspace.shared.open(url)
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
        var dict: [String: Any] = [:]
        let keys = [
            "Sound", "Bluetooth", "Battery", "BatteryShowPercentage",
            "AirDrop", "Display", "StageManager", "NowPlaying",
            "KeyboardBrightness", "Hearing"
        ]
        for key in keys {
            if let val = CFPreferencesCopyValue(key as CFString, controlCenterDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) {
                dict[key] = val
            }
        }
        return dict
    }
}
