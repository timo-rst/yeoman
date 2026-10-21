import SwiftUI
import AppKit

public struct MenuBarItemsView: View {
    @ObservedObject var scanner = MenuBarItemScanner.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Menüleisten-Elemente & Icons")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Verwalte alle Symbole der Menüleiste. Wähle Systemelemente oder Drittanbieter-Apps per Klick zu oder ab.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        scanner.scanAll()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(scanner.isScanning ? 360 : 0))
                                .animation(scanner.isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: scanner.isScanning)
                            Text("Neu scannen")
                        }
                    }
                }
                
                // Search and Filter Bar
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Elemente durchsuchen...", text: $scanner.searchQuery)
                            .textFieldStyle(.plain)
                        
                        if !scanner.searchQuery.isEmpty {
                            Button(action: { scanner.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    
                    Picker("", selection: $scanner.selectedFilter) {
                        ForEach(MenuBarItemType.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                
                if scanner.hasPendingSystemReload {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("System-Symbole geändert. Klicke auf 'Übernehmen', wenn du mit allen Einstellungen fertig bist:")
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
            .padding(20)
            
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
            
            Divider()
            
            // Summary Footer
            HStack {
                let activeCount = scanner.items.filter { $0.isVisibleInMenuBar }.count
                Text("\(scanner.items.count) Menüleisten-fähige Apps/Elemente gefunden • \(activeCount) aktuell aktiv")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Änderungen an System-Elementen werden sofort über ControlCenter übernommen.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }
}

struct MenuBarItemRow: View {
    let item: MenuBarAppItem
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Group {
                if let appPath = item.appPath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else if let symbol = item.sfSymbol {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(typeColor(item.type).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundColor(typeColor(item.type))
                    }
                }
            }
            
            // Name & Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .fontWeight(.medium)
                        .font(.system(size: 14))
                    
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
                .frame(width: 100, alignment: .trailing)
            
            // Toggle Switch
            Toggle("", isOn: Binding(
                get: { item.isVisibleInMenuBar },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(12)
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
