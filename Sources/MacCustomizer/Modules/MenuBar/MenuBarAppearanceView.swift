import SwiftUI

public struct MenuBarAppearanceView: View {
    @ObservedObject var appearance = MenuBarAppearanceManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menüleisten-Design & Styling")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Gestalte den Hintergrund der Menüleiste wie in Ice: Transparent (Wallpaper sichtbar), Split-Capsules, Frosted Glass oder Farbverläufe.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Master Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Individuelles Menüleisten-Styling aktivieren")
                            .fontWeight(.medium)
                        Text("Rendert eine hardwarebeschleunigte Overlay-Struktur für die Menüleiste auf allen Bildschirmen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $appearance.isEnabled)
                        .toggleStyle(.switch)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Style Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Design-Presets")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        AppearancePresetCard(
                            title: "Transparent",
                            subtitle: "Desktop-Wallpaper pur sichtbar",
                            icon: "eye.slash",
                            isSelected: appearance.style == .transparent
                        ) {
                            appearance.applyPreset(.transparentWallpaper)
                        }
                        
                        AppearancePresetCard(
                            title: "Ice Split-Capsule",
                            subtitle: "Getrennte schwebende Kapseln",
                            icon: "capsule",
                            isSelected: appearance.shape == .split
                        ) {
                            appearance.applyPreset(.iceSplit)
                        }
                        
                        AppearancePresetCard(
                            title: "Modern Floating Bar",
                            subtitle: "Elegante schwebende Milchglas-Leiste",
                            icon: "rectangle.roundedtop",
                            isSelected: appearance.shape == .floating && appearance.style == .glassBlur
                        ) {
                            appearance.applyPreset(.modernFloating)
                        }
                        
                        AppearancePresetCard(
                            title: "Aurora Gradient",
                            subtitle: "Vibranter Farbverlauf (Lila/Blau)",
                            icon: "paintpalette",
                            isSelected: appearance.style == .gradient
                        ) {
                            appearance.applyPreset(.auroraGradient)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Shape & Layout
                VStack(alignment: .leading, spacing: 14) {
                    Text("Form & Struktur")
                        .font(.headline)
                    
                    Picker("Form der Leiste:", selection: $appearance.shape) {
                        ForEach(MenuBarShape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Hintergrund-Stil:", selection: $appearance.style) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if appearance.shape == .split {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Dynamische Kapsel-Anpassung (Feder-Animation)", isOn: $appearance.isDynamicSplitWidth)
                                .fontWeight(.medium)
                            Text("Passt die Kapselbreiten automatisch per Feder-Animation an die Menüeinträge der aktiven App (links: \(Int(appearance.dynamicLeftWidth)) pt) und an die Menüleisten-Icons (rechts: \(Int(appearance.dynamicRightWidth)) pt) an.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                
                // Fine Tuning Sliders
                VStack(alignment: .leading, spacing: 14) {
                    Text("Feinabstimmung")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Deckkraft / Tönung:")
                            Spacer()
                            Text("\(Int(appearance.opacity * 100))%")
                                .monospacedDigit()
                        }
                        Slider(value: $appearance.opacity, in: 0.0...1.0, step: 0.05)
                    }
                    
                    if appearance.shape != .full {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Eckenabrundung (Corner Radius):")
                                Spacer()
                                Text("\(Int(appearance.cornerRadius)) pt")
                                    .monospacedDigit()
                            }
                            Slider(value: $appearance.cornerRadius, in: 0...18, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Schwebender Abstand (Padding):")
                                Spacer()
                                Text("\(Int(appearance.insetPadding)) pt")
                                    .monospacedDigit()
                            }
                            Slider(value: $appearance.insetPadding, in: 0...10, step: 1)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Toggle("Feiner Glaskanten-Rahmen (Border)", isOn: $appearance.hasBorder)
                        Spacer()
                        Toggle("Subtiler Schattenwurf (Shadow)", isOn: $appearance.hasShadow)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
}

struct AppearancePresetCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .font(.system(size: 13))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
