import SwiftUI
import AppKit

public struct MenuBarItemsView: View {
    @ObservedObject var scanner = MenuBarItemScanner.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header & Control Toolbar
            VStack(spacing: 12) {
                // Row 1: Section Title & Live Stats + Action Buttons
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menüleisten-Elemente & Icons")
                            .font(.headline)
                        
                        let activeCount = scanner.items.filter { $0.isVisibleInMenuBar }.count
                        Text("\(scanner.items.count) Symbole gefunden • \(activeCount) aktiv in der Menüleiste")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 16)
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            scanner.scanAll()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(scanner.isScanning ? 360 : 0))
                                    .animation(scanner.isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: scanner.isScanning)
                                Text("Neu scannen")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            scanner.openSystemControlCenterSettings()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                Text("Kontrollzentrum...")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                // Row 2: Filter Segmented Picker (left) + Spacer + Compact Search Bar (right)
                HStack(spacing: 12) {
                    Picker("", selection: $scanner.selectedFilter) {
                        ForEach(MenuBarItemType.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    
                    Spacer(minLength: 16)
                    
                    // Compact, native-feeling search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("Elemente suchen...", text: $scanner.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        
                        if !scanner.searchQuery.isEmpty {
                            Button(action: { scanner.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                            )
                    )
                }
                
                if scanner.hasPendingSystemReload {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("System-Symbole geändert. Klicke auf 'Übernehmen', um die Menüleiste zu aktualisieren:")
                            .font(.caption)
                        Spacer()
                        Button("Jetzt übernehmen") {
                            scanner.applySystemChanges()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // List of Detected Items
            if scanner.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Keine passenden Menüleisten-Elemente gefunden.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(scanner.filteredItems) { item in
                            MenuBarItemRow(item: item) { newValue in
                                scanner.toggleItemVisibility(id: item.id, enable: newValue)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

struct MenuBarItemRow: View {
    let item: MenuBarAppItem
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Group {
                if let appPath = item.appPath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else if item.sfSymbol == "NSBluetoothTemplate", let btImage = NSImage(named: NSImage.Name("NSBluetoothTemplate")) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(typeColor(item.type).opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(nsImage: btImage)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundColor(typeColor(item.type))
                    }
                } else if let symbol = item.sfSymbol {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(typeColor(item.type).opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: symbol)
                            .font(.system(size: 14))
                            .foregroundColor(typeColor(item.type))
                    }
                }
            }
            
            // Name & Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .fontWeight(.medium)
                        .font(.system(size: 13))
                    
                    Text(item.type.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(typeColor(item.type).opacity(0.18)))
                        .foregroundColor(typeColor(item.type))
                }
                
                HStack(spacing: 8) {
                    if let bundleId = item.bundleIdentifier {
                        Text(bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if item.type == .thirdParty {
                        Text(item.isRunning ? "• Läuft im Hintergrund" : "• Beendet")
                            .font(.caption2)
                            .foregroundColor(item.isRunning ? .green : .secondary)
                    }
                }
            }
            
            Spacer()
            
            // Status Tag
            Text(item.isVisibleInMenuBar ? "In Menüleiste" : "Ausgeblendet")
                .font(.caption)
                .foregroundColor(item.isVisibleInMenuBar ? .primary : .secondary)
                .frame(width: 90, alignment: .trailing)
            
            // Toggle Switch
            Toggle("", isOn: Binding(
                get: { item.isVisibleInMenuBar },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private func typeColor(_ type: MenuBarItemType) -> Color {
        switch type {
        case .system: return .blue
        case .thirdParty: return .purple
        case .internalModule: return .accentColor
        case .all: return .secondary
        }
    }
}
