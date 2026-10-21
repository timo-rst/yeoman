import Foundation
import Combine

public struct SpacingProfile: Codable, Equatable {
    public var spacing: Int
    public var selectionPadding: Int
    
    public static let standard = SpacingProfile(spacing: 16, selectionPadding: 16)
    public static let compact = SpacingProfile(spacing: 8, selectionPadding: 8)
    public static let ultraCompact = SpacingProfile(spacing: 4, selectionPadding: 4)
    public static let zero = SpacingProfile(spacing: 0, selectionPadding: 0)
}

public final class MenuBarSpacingManager: ObservableObject {
    public static let shared = MenuBarSpacingManager()
    
    @Published public var currentSpacing: Int = 8
    @Published public var currentSelectionPadding: Int = 8
    @Published public var autoRestartControlCenter: Bool = true
    @Published public var isApplying: Bool = false
    
    private let spacingKey = "NSStatusItemSpacing"
    private let paddingKey = "NSStatusItemSelectionPadding"
    
    private var debounceTimer: AnyCancellable?
    
    public init() {
        self.autoRestartControlCenter = UserDefaults.standard.object(forKey: "spacing_auto_restart_cc") as? Bool ?? true
        readCurrentPreferences()
        if currentSpacing != 16 || currentSelectionPadding != 16 {
            applyInProcessPreferences(spacing: currentSpacing, padding: currentSelectionPadding)
        }
    }
    
    public func setAutoRestart(_ enabled: Bool) {
        self.autoRestartControlCenter = enabled
        UserDefaults.standard.set(enabled, forKey: "spacing_auto_restart_cc")
    }
    
    public func readCurrentPreferences() {
        if let val = getGlobalInt(key: spacingKey) {
            self.currentSpacing = val
        } else if let localVal = UserDefaults.standard.object(forKey: spacingKey) as? Int {
            self.currentSpacing = localVal
        } else {
            self.currentSpacing = 16
        }
        if let val = getGlobalInt(key: paddingKey) {
            self.currentSelectionPadding = val
        } else if let localVal = UserDefaults.standard.object(forKey: paddingKey) as? Int {
            self.currentSelectionPadding = localVal
        } else {
            self.currentSelectionPadding = 16
        }
    }
    
    public func applyPreset(_ profile: SpacingProfile) {
        debounceTimer?.cancel()
        self.currentSpacing = profile.spacing
        self.currentSelectionPadding = profile.selectionPadding
        commitSpacing(spacing: profile.spacing, selectionPadding: profile.selectionPadding, restartNow: true)
    }
    
    public func setSpacingDebounced(spacing: Int, selectionPadding: Int) {
        self.currentSpacing = spacing
        self.currentSelectionPadding = selectionPadding
        
        debounceTimer?.cancel()
        debounceTimer = Just(())
            .delay(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self = self else { return }
                self.commitSpacing(spacing: spacing, selectionPadding: selectionPadding, restartNow: self.autoRestartControlCenter)
            }
    }
    
    public func commitSpacing(spacing: Int, selectionPadding: Int, restartNow: Bool) {
        isApplying = true
        
        // 1. Immediately apply to in-process CFPreferences and UserDefaults
        applyInProcessPreferences(spacing: spacing, padding: selectionPadding)
        
        // 2. Immediately recreate all MacCustomizer menu bar status items live
        ModuleManager.shared.recreateAllStatusItems()
        
        // 3. Persist system-wide and reload ControlCenter in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.writeKeys(spacing: spacing, padding: selectionPadding)
            
            if restartNow {
                self.restartControlCenterProcess()
            }
            
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.controlcenter.itemchanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            
            DispatchQueue.main.async {
                self.isApplying = false
            }
        }
    }
    
    public func resetToDefaults() {
        debounceTimer?.cancel()
        self.currentSpacing = 16
        self.currentSelectionPadding = 16
        isApplying = true
        
        // 1. Clear in-process CFPreferences and UserDefaults immediately
        clearInProcessPreferences()
        
        // 2. Immediately recreate all MacCustomizer menu bar status items
        ModuleManager.shared.recreateAllStatusItems()
        
        // 3. Clear system-wide defaults and reload ControlCenter
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.deleteKeys()
            self.restartControlCenterProcess()
            
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.controlcenter.itemchanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            
            DispatchQueue.main.async {
                self.isApplying = false
            }
        }
    }
    
    private func applyInProcessPreferences(spacing: Int, padding: Int) {
        let cfSpacing = spacing as CFNumber
        let cfPadding = padding as CFNumber
        
        CFPreferencesSetValue(spacingKey as CFString, cfSpacing, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(paddingKey as CFString, cfPadding, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        
        CFPreferencesSetValue(spacingKey as CFString, cfSpacing, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(paddingKey as CFString, cfPadding, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        CFPreferencesSetValue(spacingKey as CFString, cfSpacing, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(paddingKey as CFString, cfPadding, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        
        CFPreferencesSetValue(spacingKey as CFString, cfSpacing, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(paddingKey as CFString, cfPadding, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        UserDefaults.standard.set(spacing, forKey: spacingKey)
        UserDefaults.standard.set(padding, forKey: paddingKey)
        UserDefaults.standard.synchronize()
    }
    
    private func clearInProcessPreferences() {
        CFPreferencesSetValue(spacingKey as CFString, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(paddingKey as CFString, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        
        CFPreferencesSetValue(spacingKey as CFString, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(paddingKey as CFString, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        CFPreferencesSetValue(spacingKey as CFString, nil, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(paddingKey as CFString, nil, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        
        CFPreferencesSetValue(spacingKey as CFString, nil, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(paddingKey as CFString, nil, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        UserDefaults.standard.removeObject(forKey: spacingKey)
        UserDefaults.standard.removeObject(forKey: paddingKey)
        UserDefaults.standard.synchronize()
    }
    
    public func restartControlCenter() {
        isApplying = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.restartControlCenterProcess()
            DispatchQueue.main.async {
                self?.isApplying = false
            }
        }
    }
    
    private func restartControlCenterProcess() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["ControlCenter"]
        try? p.run()
        p.waitUntilExit()
    }
    
    // MARK: - Defaults access
    
    private func getGlobalInt(key: String) -> Int? {
        // Try -currentHost first
        let p1 = Process()
        let pipe1 = Pipe()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p1.arguments = ["-currentHost", "read", "-globalDomain", key]
        p1.standardOutput = pipe1
        p1.standardError = Pipe()
        if (try? p1.run()) != nil {
            p1.waitUntilExit()
            if p1.terminationStatus == 0 {
                let data = pipe1.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let val = Int(str) {
                    return val
                }
            }
        }
        
        // Try -g fallback
        let p2 = Process()
        let pipe2 = Pipe()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p2.arguments = ["read", "-g", key]
        p2.standardOutput = pipe2
        p2.standardError = Pipe()
        if (try? p2.run()) != nil {
            p2.waitUntilExit()
            if p2.terminationStatus == 0 {
                let data = pipe2.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let val = Int(str) {
                    return val
                }
            }
        }
        return nil
    }
    
    private func writeKeys(spacing: Int, padding: Int) {
        // Write to -currentHost -globalDomain
        runDefaults(["-currentHost", "write", "-globalDomain", spacingKey, "-int", "\(spacing)"])
        runDefaults(["-currentHost", "write", "-globalDomain", paddingKey, "-int", "\(padding)"])
        // Write to -g (NSGlobalDomain) for apps reading global domain
        runDefaults(["write", "-g", spacingKey, "-int", "\(spacing)"])
        runDefaults(["write", "-g", paddingKey, "-int", "\(padding)"])
    }
    
    private func deleteKeys() {
        runDefaults(["-currentHost", "delete", "-globalDomain", spacingKey])
        runDefaults(["-currentHost", "delete", "-globalDomain", paddingKey])
        runDefaults(["delete", "-g", spacingKey])
        runDefaults(["delete", "-g", paddingKey])
    }
    
    private func runDefaults(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }
}
