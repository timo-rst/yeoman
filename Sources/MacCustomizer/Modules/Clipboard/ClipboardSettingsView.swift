import SwiftUI

public struct ClipboardSettingsView: View {
    @ObservedObject var module: ClipboardModule
    @ObservedObject var store = ClipboardHistoryStore.shared
    @ObservedObject var monitor = ClipboardMonitor.shared
    
    enum SettingsSubTab: String, CaseIterable {
        case history = "Inhalte & Verlauf"
        case options = "Optionen & Sicherheit"
    }
    
    @State private var selectedTab: SettingsSubTab = .history
    
    public init(module: ClipboardModule) {
        self.module = module
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clipboard Manager (Clippy)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Verlauf kopierter Texte, Links, Snippets und Fotos mit Kategorien und Suchfunktion.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Toggle("", isOn: $module.isEnabled)
                        .toggleStyle(.switch)
                }
                
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsSubTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            if selectedTab == .history {
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
                        // Menüleisten-Option
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Menüleisten-Integration")
                                .font(.headline)
                            
                            Toggle("Eigenes Icon in der Menüleiste anzeigen (wie Clippy / Maccy)", isOn: $module.showsDedicatedStatusItem)
                                .font(.subheadline)
                            
                            Text("Zeigt ein separates Zwischenablagen-Symbol in der Menüleiste an. Ein Klick darauf öffnet direkt das Popup mit Verlauf, Tabs (inkl. Fotos) und Suchfeld.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Überwachung & Sicherheit")
                                .font(.headline)
                            
                            Toggle("Passwort-Manager ignorieren (1Password, Bitwarden, KeePass etc.)", isOn: $monitor.ignorePasswordManagers)
                                .font(.subheadline)
                            
                            Text("Passwörter und temporäre Zwischenablagen werden automatisch erkannt und nicht im Verlauf gespeichert.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
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
    }
}
