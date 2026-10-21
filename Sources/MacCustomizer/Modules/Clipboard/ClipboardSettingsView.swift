import SwiftUI

public struct ClipboardSettingsView: View {
    @ObservedObject var module: ClipboardModule
    @ObservedObject var store = ClipboardHistoryStore.shared
    @ObservedObject var monitor = ClipboardMonitor.shared
    
    public init(module: ClipboardModule) {
        self.module = module
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clipboard Manager (Clippy)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Behalte den Überblick über kopierte Texte, Links und Snippets mit Suchfunktion und Pinning.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Menüleisten-Option
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Integration")
                        .font(.headline)
                    
                    Toggle("Eigenes Icon in der Menüleiste anzeigen (wie Clippy / Maccy)", isOn: $module.showsDedicatedStatusItem)
                        .font(.subheadline)
                    
                    Text("Zeigt ein separates Zwischenablagen-Symbol in der Menüleiste an. Ein Klick darauf öffnet direkt das Popup mit Verlauf und Suchfeld.")
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
                            Text("\(store.items.filter { $0.isPinned }.count) angepinnt")
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
