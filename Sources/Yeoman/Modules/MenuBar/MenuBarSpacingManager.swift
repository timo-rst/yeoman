import AppKit
import ObjectiveC
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
    
    @Published public private(set) var currentSpacing: Int = 8
    @Published public private(set) var currentSelectionPadding: Int = 8
    @Published public private(set) var autoRestartControlCenter: Bool = true
    @Published public private(set) var isApplying: Bool = false
    @Published public private(set) var lastError: String?
    
    private let spacingKey = "NSStatusItemSpacing"
    private let paddingKey = "NSStatusItemSelectionPadding"
    
    private var debounceTimer: AnyCancellable?
    private static var isHookInstalled = false
    
    public init() {
        self.autoRestartControlCenter = UserDefaults.standard.object(forKey: "spacing_auto_restart_cc") as? Bool ?? true
        readCurrentPreferences()
        MenuBarSpacingManager.installAppKitSpacingHooks()
        if currentSpacing != 16 || currentSelectionPadding != 16 {
            applyInProcessPreferences(spacing: currentSpacing, padding: currentSelectionPadding)
        }
    }
    
    /// Swizzles AppKit NSSystemStatusBar/NSStatusBar contentPadding & backgroundSelectionInset
    /// so newly created NSStatusItems in this process dynamically use our active spacing/padding
    /// instead of the static value cached at AppKit initialization time.
    public static func installAppKitSpacingHooks() {
        guard !isHookInstalled else { return }
        isHookInstalled = true
        
        let paddingBlock: @convention(block) (AnyObject) -> CGFloat = { _ in
            return CGFloat(MenuBarSpacingManager.shared.currentSpacing)
        }
        let insetBlock: @convention(block) (AnyObject) -> NSSize = { _ in
            return NSSize(width: -CGFloat(MenuBarSpacingManager.shared.currentSelectionPadding), height: -1.0)
        }
        
        for className in ["NSSystemStatusBar", "NSStatusBar"] {
            guard let cls = NSClassFromString(className) else { continue }
            if let m = class_getInstanceMethod(cls, NSSelectorFromString("contentPadding")) {
                method_setImplementation(m, imp_implementationWithBlock(paddingBlock))
            }
            if let m = class_getInstanceMethod(cls, NSSelectorFromString("backgroundSelectionInset")) {
                method_setImplementation(m, imp_implementationWithBlock(insetBlock))
            }
        }
    }
    
    public func setAutoRestart(_ enabled: Bool) {
        self.autoRestartControlCenter = enabled
        UserDefaults.standard.set(enabled, forKey: "spacing_auto_restart_cc")
    }
    
    public func readCurrentPreferences() {
        if let val = getGlobalInt(key: spacingKey) {
            self.currentSpacing = min(24, max(0, val))
        } else if let localVal = UserDefaults.standard.object(forKey: spacingKey) as? Int {
            self.currentSpacing = min(24, max(0, localVal))
        } else {
            self.currentSpacing = 16
        }
        if let val = getGlobalInt(key: paddingKey) {
            self.currentSelectionPadding = min(24, max(0, val))
        } else if let localVal = UserDefaults.standard.object(forKey: paddingKey) as? Int {
            self.currentSelectionPadding = min(24, max(0, localVal))
        } else {
            self.currentSelectionPadding = 16
        }
    }
    
    public func applyPreset(_ profile: SpacingProfile) {
        debounceTimer?.cancel()
        let spacing = min(24, max(0, profile.spacing)), padding = min(24, max(0, profile.selectionPadding))
        self.currentSpacing = spacing
        self.currentSelectionPadding = padding
        commitSpacing(spacing: spacing, selectionPadding: padding, restartNow: true)
    }
    
    public func setSpacingDebounced(spacing: Int, selectionPadding: Int) {
        let spacing = min(24, max(0, spacing)), selectionPadding = min(24, max(0, selectionPadding))
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
        let spacing = min(24, max(0, spacing)), selectionPadding = min(24, max(0, selectionPadding))
        isApplying = true
        self.currentSpacing = spacing
        self.currentSelectionPadding = selectionPadding
        
        // 1. Immediately apply to in-process CFPreferences and UserDefaults
        applyInProcessPreferences(spacing: spacing, padding: selectionPadding)
        
        // 2. Immediately recreate all Yeoman menu bar status items live
        // Since contentPadding is hooked to currentSpacing, all newly created items immediately use the exact spacing!
        DispatchQueue.main.async {
            ModuleManager.shared.recreateAllStatusItems()
        }
        
        // 3. Persist system-wide and reload ControlCenter in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failure: Error?
            do {
                try self.writeKeys(spacing: spacing, padding: selectionPadding)
                if restartNow { try self.restartControlCenterProcess() }
            } catch { failure = error }
            
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.controlcenter.itemchanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            let errorMessage = failure?.localizedDescription
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                ModuleManager.shared.recreateAllStatusItems()
                self.lastError = errorMessage
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
        
        // 2. Immediately recreate all Yeoman menu bar status items live
        DispatchQueue.main.async {
            ModuleManager.shared.recreateAllStatusItems()
        }
        
        // 3. Clear system-wide defaults and reload ControlCenter
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failure: Error?
            do { try self.deleteKeys(); try self.restartControlCenterProcess() }
            catch { failure = error }
            
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.controlcenter.itemchanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            let errorMessage = failure?.localizedDescription
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                ModuleManager.shared.recreateAllStatusItems()
                self.lastError = errorMessage
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
            var failure: Error?
            do { try self?.restartControlCenterProcess() } catch { failure = error }
            let errorMessage = failure?.localizedDescription
            DispatchQueue.main.async {
                self?.lastError = errorMessage
                self?.isApplying = false
            }
        }
    }
    
    private func restartControlCenterProcess() throws {
        let result = try BoundedProcess.run("/usr/bin/killall", ["ControlCenter"], timeout: 3, limit: 16384)
        guard result.status == 0 else { throw SecurityFailure.rejected("ControlCenter konnte nicht neu gestartet werden.") }
    }
    
    // MARK: - Defaults access
    
    private func getGlobalInt(key: String) -> Int? {
        if let val = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int {
            return val
        }
        if let val = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? Int {
            return val
        }
        return nil
    }
    
    private func writeKeys(spacing: Int, padding: Int) throws {
        // Write to -currentHost -globalDomain
        try runDefaults(["-currentHost", "write", "-globalDomain", spacingKey, "-int", "\(spacing)"])
        try runDefaults(["-currentHost", "write", "-globalDomain", paddingKey, "-int", "\(padding)"])
        // Write to -g (NSGlobalDomain) for apps reading global domain
        try runDefaults(["write", "-g", spacingKey, "-int", "\(spacing)"])
        try runDefaults(["write", "-g", paddingKey, "-int", "\(padding)"])
    }
    
    private func deleteKeys() throws {
        try runDefaults(["-currentHost", "delete", "-globalDomain", spacingKey])
        try runDefaults(["-currentHost", "delete", "-globalDomain", paddingKey])
        try runDefaults(["delete", "-g", spacingKey])
        try runDefaults(["delete", "-g", paddingKey])
    }
    
    private func runDefaults(_ args: [String]) throws {
        let result = try BoundedProcess.run("/usr/bin/defaults", args, timeout: 3, limit: 16384)
        guard result.status == 0 else { throw SecurityFailure.rejected("Systemeinstellung konnte nicht geschrieben werden.") }
    }
}
