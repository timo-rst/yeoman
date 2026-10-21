import SwiftUI

public struct ScrollReverserSettingsView: View {
    @ObservedObject var module: ScrollReverserModule
    @ObservedObject var manager = ScrollReverserManager.shared
    
    public init(module: ScrollReverserModule) {
        self.module = module
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Scroll Reverser (Maus & Trackpad)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Steuert die Scrollrichtung von Maus und Trackpad völlig unabhängig voneinander.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("Modul aktiv", isOn: $module.isEnabled)
                            .toggleStyle(.switch)
                    }
                }
                
                // Accessibility Permission Banner (if missing)
                if !manager.hasAccessibilityPermission {
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bedienungshilfen-Berechtigung erforderlich")
                                .fontWeight(.medium)
                            Text("macOS erfordert die Erlaubnis für Bedienungshilfen, damit MacCustomizer Scrollrad-Events abfangen und umkehren darf.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("In Systemeinstellungen öffnen") {
                            manager.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Card 1: Mouse Settings
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "computermouse")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                        Text("Maus (Klassisches Scrollrad)")
                            .font(.headline)
                    }
                    
                    Text("Gilt für herkömmliche USB-, Funk- und Bluetooth-Mäuse mit physischem Scrollrad.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    Toggle("Vertikales Scrollen umkehren (Klassisches Mausrad)", isOn: $manager.reverseMouseVertical)
                        .font(.subheadline)
                    
                    Text("Empfohlen: Aktiviert. Wenn macOS auf 'Natürliches Scrollen' steht, scrollt die Maus hiermit gewohnt nach unten, während das Trackpad natürlich bleibt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Horizontales Scrollen umkehren", isOn: $manager.reverseMouseHorizontal)
                        .font(.subheadline)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scrollrad-Schrittmultiplikator:")
                                .font(.subheadline)
                            Text("Erhöht die Scroll-Geschwindigkeit pro Mausrad-Rasterung.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $manager.mouseStepMultiplier) {
                            Text("1x (Standard)").tag(1)
                            Text("2x (Schneller)").tag(2)
                            Text("3x").tag(3)
                            Text("4x").tag(4)
                            Text("5x (Maximum)").tag(5)
                        }
                        .frame(width: 150)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Card 2: Trackpad Settings
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                        Text("Trackpad")
                            .font(.headline)
                    }
                    
                    Text("Gilt für das integrierte MacBook-Trackpad und Apple Magic Trackpad.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    Toggle("Vertikales Scrollen umkehren", isOn: $manager.reverseTrackpadVertical)
                        .font(.subheadline)
                    
                    Text("Empfohlen: Deaktiviert. Das Trackpad behält so das native macOS-Verhalten (Zwei-Finger-Wischgeste wie auf Touchscreens).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle("Horizontales Scrollen umkehren", isOn: $manager.reverseTrackpadHorizontal)
                        .font(.subheadline)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Card 3: Menu Bar Integration
                VStack(alignment: .leading, spacing: 14) {
                    Text("Menüleisten-Integration")
                        .font(.headline)
                    
                    Toggle("Eigenes Icon in der Menüleiste anzeigen (wie Pilotmoon Scroll Reverser)", isOn: $module.showsDedicatedStatusItem)
                        .font(.subheadline)
                    
                    Text("Zeigt ein separates Maus-Symbol in der Menüleiste an, über das du die Richtung per Klick umschalten kannst.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Card 4: Live Event Monitor & Diagnostics
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle()
                            .fill(manager.isRunning ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text("Live-Status & Diagnose")
                            .font(.headline)
                        Spacer()
                        Text(manager.isRunning ? "Aktiv & lauscht auf Scroll-Events" : "Angehalten")
                            .font(.caption)
                            .foregroundColor(manager.isRunning ? .green : .secondary)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zuletzt erkanntes Gerät:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(manager.lastEventDevice)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Aktion:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(manager.lastEventSummary)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
}
