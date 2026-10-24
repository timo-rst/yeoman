import AppKit
import SwiftUI

/// Persisted pin state shared by a module's settings and its live popover.
public final class PopoverPinPreference: ObservableObject {
    @Published public var isPinned: Bool {
        didSet {
            guard isPinned != oldValue else { return }
            defaults.set(isPinned, forKey: storageKey)
        }
    }

    public var popoverBehavior: NSPopover.Behavior {
        isPinned ? .applicationDefined : .transient
    }

    private let storageKey: String
    private let defaults: UserDefaults

    public init(storageKey: String, defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
        self.isPinned = defaults.object(forKey: storageKey) as? Bool ?? false
    }
}

public struct PopoverPinButton: View {
    @ObservedObject private var preference: PopoverPinPreference

    public init(preference: PopoverPinPreference) {
        self.preference = preference
    }

    public var body: some View {
        Button {
            preference.isPinned.toggle()
        } label: {
            Image(systemName: preference.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(preference.isPinned ? .accentColor : .secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preference.isPinned ? l10n("common.unpin_window") : l10n("common.pin_window"))
        .accessibilityLabel(preference.isPinned ? l10n("common.unpin_window") : l10n("common.pin_window"))
    }
}
