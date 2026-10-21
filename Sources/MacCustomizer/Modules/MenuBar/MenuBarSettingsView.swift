import SwiftUI

public struct MenuBarSettingsView: View {
    @ObservedObject var spacingManager = MenuBarSpacingManager.shared
    @ObservedObject var displayManager = DisplayManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu Bar Optimizer")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Passe den Abstand und die Darstellung der Menüleisten-Symbole an (wie in Ice), optimiert für Multi-Monitor Setups.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Spacing Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Abstand-Presets")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        PresetButton(title: "Ultra-Kompakt", subtitle: "4 pt", isSelected: spacingManager.currentSpacing == 4) {
                            spacingManager.applyPreset(.ultraCompact)
                        }
                        
                        PresetButton(title: "Kompakt (Ice)", subtitle: "8 pt", isSelected: spacingManager.currentSpacing == 8) {
                            spacingManager.applyPreset(.compact)
                        }
                        
                        PresetButton(title: "Standard", subtitle: "16 pt (macOS)", isSelected: spacingManager.currentSpacing == 16) {
                            spacingManager.applyPreset(.standard)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Manual Fine-Tuning Slider
                VStack(alignment: .leading, spacing: 14) {
                    Text("Feinabstimmung (Pixel-genau)")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Symbol-Abstand (Spacing):")
                            Spacer()
                            Text("\(spacingManager.currentSpacing) pt")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Binding(
                            get: { Double(spacingManager.currentSpacing) },
                            set: { spacingManager.applySpacing(spacing: Int($0), selectionPadding: spacingManager.currentSelectionPadding) }
                        ), in: 0...24, step: 1)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Auswahl-Padding (Selection Padding):")
                            Spacer()
                            Text("\(spacingManager.currentSelectionPadding) pt")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                        Slider(value: Binding(
                            get: { Double(spacingManager.currentSelectionPadding) },
                            set: { spacingManager.applySpacing(spacing: spacingManager.currentSpacing, selectionPadding: Int($0)) }
                        ), in: 0...24, step: 1)
                    }
                    
                    Toggle("ControlCenter nach Änderung automatisch neu starten", isOn: $spacingManager.autoRestartControlCenter)
                        .font(.subheadline)
                    
                    HStack {
                        Button("ControlCenter jetzt neu starten") {
                            spacingManager.restartControlCenter()
                        }
                        
                        Spacer()
                        
                        Button("Auf macOS Standard zurücksetzen") {
                            spacingManager.resetToDefaults()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Multi-Display Status & Detection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "display.2")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                        Text("Multi-Monitor Status")
                            .font(.headline)
                        Spacer()
                        Text("\(displayManager.displays.count) Bildschirm(e) erkannt")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(displayManager.displays) { display in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(display.name)
                                        .fontWeight(.medium)
                                    if display.isMain {
                                        Text("Hauptbildschirm")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                            .foregroundColor(.accentColor)
                                    }
                                    if display.hasNotch {
                                        Text("Notch")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                                            .foregroundColor(.orange)
                                    }
                                }
                                Text("\(Int(display.frame.width)) x \(Int(display.frame.height)) @ \(Int(display.backingScaleFactor))x (Menüleiste: \(Int(display.menuBarHeight))pt)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
}

struct PresetButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
