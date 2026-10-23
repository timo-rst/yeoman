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
    
    public init(module: ClipboardModule) {
        self.module = module
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
                            Toggle("Aufzeichnung pausieren", isOn: $monitor.isPaused)
                            TextField("Ausgeschlossene Bundle-IDs, durch Kommas getrennt", text: $monitor.excludedBundleIDs)
                            Toggle("Verlauf verschlüsselt auf diesem Mac speichern", isOn: Binding(get: { store.isPersistent }, set: { store.setPersistent($0) }))
                            if let error = store.storageError { Text(error).foregroundColor(.red).font(.caption) }
                            Text("Überwachung & Sicherheit")
                                .font(.headline)
                            
                            HStack(spacing: 6) {
                                Toggle("Passwörter und sensible Daten nicht speichern", isOn: $monitor.ignorePasswordManagers)
                                    .font(.subheadline)
                                InfoTooltip(text: "Kopierte Passwörter aus Passwort-Managern und Browser-Erweiterungen werden automatisch erkannt und vom Verlauf ausgeschlossen.")
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Maximale Anzahl gespeicherter Elemente:")
                                Spacer()
                                Picker("", selection: $store.maxItems) {
                                    Text("50 Einträge").tag(50)
                                    Text("100 Einträge").tag(100)
                                    Text("250 Einträge").tag(250)
                                    Text("500 Einträge").tag(500)
                                }
                                .frame(width: 150)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Verlauf verwalten")
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Aktuell gespeicherte Einträge: \(store.items.count)")
                                        .fontWeight(.medium)
                                    HStack(spacing: 8) {
                                        Text("\(store.items.filter { $0.type == .image }.count) Bilder")
                                        Text("•")
                                        Text("\(store.items.filter { $0.type != .image }.count) Texte")
                                        Text("•")
                                        Text("\(store.items.filter { $0.isPinned }.count) angepinnt")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Nicht angepinnte leeren") {
                                    store.clearUnpinned()
                                }
                                
                                Button("Alle löschen", role: .destructive) {
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
