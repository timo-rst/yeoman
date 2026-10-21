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
    @Published public var autoRestartControlCenter: Bool = false
    @Published public var perDisplayProfilesEnabled: Bool = false
    
    private let spacingKey = "NSStatusItemSpacing"
    private let paddingKey = "NSStatusItemSelectionPadding"
    
    public init() {
        readCurrentPreferences()
    }
    
    public func readCurrentPreferences() {
        if let val = getGlobalInt(key: spacingKey) {
            self.currentSpacing = val
        }
        if let val = getGlobalInt(key: paddingKey) {
            self.currentSelectionPadding = val
        }
    }
    
    public func applyPreset(_ profile: SpacingProfile) {
        applySpacing(spacing: profile.spacing, selectionPadding: profile.selectionPadding)
    }
    
    public func applySpacing(spacing: Int, selectionPadding: Int) {
        self.currentSpacing = spacing
        self.currentSelectionPadding = selectionPadding
        
        setGlobalInt(key: spacingKey, value: spacing)
        setGlobalInt(key: paddingKey, value: selectionPadding)
        
        if autoRestartControlCenter {
            restartControlCenter()
        }
    }
    
    public func resetToDefaults() {
        removeGlobalKey(key: spacingKey)
        removeGlobalKey(key: paddingKey)
        self.currentSpacing = 16
        self.currentSelectionPadding = 16
        
        if autoRestartControlCenter {
            restartControlCenter()
        }
    }
    
    public func restartControlCenter() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["ControlCenter"]
            try? process.run()
        }
    }
    
    // MARK: - Private CFPreferences / defaults access
    
    private func getGlobalInt(key: String) -> Int? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "read", "-globalDomain", key]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let intVal = Int(str) {
                    return intVal
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func setGlobalInt(key: String, value: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "write", "-globalDomain", key, "-int", "\(value)"]
        try? process.run()
        process.waitUntilExit()
    }
    
    private func removeGlobalKey(key: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "delete", "-globalDomain", key]
        try? process.run()
        process.waitUntilExit()
    }
}
