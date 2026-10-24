import SwiftUI

public enum ClipboardSubTab: String, CaseIterable, Identifiable, SubTabProtocol {
    case history = "history"
    case options = "options"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .history: return l10n("clipboard.subtab_history")
        case .options: return l10n("clipboard.subtab_options")
        }
    }
    
    public var iconName: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .options: return "slider.horizontal.3"
        }
    }
}

public struct ClipboardSettingsView: View {
    @ObservedObject var module: ClipboardModule
    @ObservedObject var store = ClipboardHistoryStore.shared
    @ObservedObject var monitor = ClipboardMonitor.shared
    @ObservedObject var l10nObj = LocalizationManager.shared
    @ObservedObject private var popoverPin: PopoverPinPreference
    
    public init(module: ClipboardModule) {
        self.module = module
        self._popoverPin = ObservedObject(wrappedValue: module.popoverPin)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header & Sub-Navigation
            VStack(spacing: 14) {
                ModuleHeaderView(
                    title: l10n("tab.clipboard"),
                    subtitle: l10n("clipboard.subtitle"),
                    icon: "doc.on.clipboard",
                    isEnabled: $module.isEnabled
                )
                
                // Unified sub-menu switcher for this module
                UnifiedSubTabBar(
                    tabs: ClipboardSubTab.allCases,
                    selectedTab: $module.activeSubTab
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            Group {
                if module.activeSubTab == .history {
                // Live Clipboard Browser (Full View)
                HStack(spacing: 0) {
                    Spacer()
                    ClipboardView()
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .padding(16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Settings & Options View
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(l10n("clipboard.pause_recording"), isOn: $monitor.isPaused)
                            Toggle(l10n("common.keep_window_pinned"), isOn: $popoverPin.isPinned)
                            TextField(l10n("clipboard.excluded_bundle_ids"), text: $monitor.excludedBundleIDs)
                            Toggle(l10n("clipboard.save_encrypted"), isOn: Binding(get: { store.isPersistent }, set: { store.setPersistent($0) }))
                            if let error = store.storageError { Text(error).foregroundColor(.red).font(.caption) }
                            Text(l10n("clipboard.options_monitoring_title"))
                                .font(.headline)
                            
                            HStack(spacing: 6) {
                                Toggle(l10n("clipboard.ignore_passwords"), isOn: $monitor.ignorePasswordManagers)
                                    .font(.subheadline)
                                InfoTooltip(text: l10n("clipboard.ignore_passwords_tooltip"))
                            }
                            
                            Divider()
                            
                            HStack {
                                Text(l10n("clipboard.options_max_items"))
                                Spacer()
                                Picker("", selection: $store.maxItems) {
                                    Text(String(format: l10n("clipboard.options_items_count_format"), 50)).tag(50)
                                    Text(String(format: l10n("clipboard.options_items_count_format"), 100)).tag(100)
                                    Text(String(format: l10n("clipboard.options_items_count_format"), 250)).tag(250)
                                    Text(String(format: l10n("clipboard.options_items_count_format"), 500)).tag(500)
                                }
                                .frame(width: 150)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            Text(l10n("clipboard.options_manage_title"))
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: l10n("clipboard.options_current_items_format"), store.items.count))
                                        .fontWeight(.medium)
                                    HStack(spacing: 8) {
                                        Text(String(format: l10n("clipboard.options_images_format"), store.items.filter { $0.type == .image }.count))
                                        Text("•")
                                        Text(String(format: l10n("clipboard.options_texts_format"), store.items.filter { $0.type != .image }.count))
                                        Text("•")
                                        Text(String(format: l10n("clipboard.options_pinned_format"), store.items.filter { $0.isPinned }.count))
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(l10n("clipboard.clear_unpinned")) {
                                    store.clearUnpinned()
                                }
                                
                                Button(l10n("clipboard.clear_all"), role: .destructive) {
                                    store.clearAll()
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .padding(20)
                }
            }
            }
            .disabled(!module.isEnabled)
            .opacity(module.isEnabled ? 1.0 : 0.6)
        }
    }
}
