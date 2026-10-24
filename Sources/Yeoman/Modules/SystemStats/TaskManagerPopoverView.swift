import SwiftUI
import AppKit

public struct TaskManagerPopoverView: View {
    @ObservedObject var provider = SystemMetricsProvider.shared
    @ObservedObject var l10nObj = LocalizationManager.shared
    @State private var hoveredPid: Int?
    @State private var killedPid: Int?
    @State private var isSearchExpanded: Bool = false
    @FocusState private var isSearchFocused: Bool
    private let pinPreference: PopoverPinPreference?
    
    public init(pinPreference: PopoverPinPreference? = nil) {
        self.pinPreference = pinPreference
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header: Hardware Overview Cards (Windows Task Manager Style)
            HStack(spacing: 8) {
                // CPU Card
                HardwareMetricCard(
                    title: "CPU",
                    value: "\(Int(provider.cpuUsagePercent))%",
                    subtitle: String(format: l10n("system_stats.cores_format"), ProcessInfo.processInfo.processorCount),
                    history: provider.cpuHistory,
                    accentColor: .blue
                )
                
                // RAM Card
                HardwareMetricCard(
                    title: "RAM",
                    value: "\(Int(provider.memoryUsagePercent))%",
                    subtitle: "\(String(format: "%.1f", provider.memoryUsedGB)) / \(String(format: "%.0f", provider.memoryTotalGB)) GB",
                    history: provider.ramHistory,
                    accentColor: .purple
                )
                
                // GPU Card
                HardwareMetricCard(
                    title: "GPU",
                    value: "\(Int(provider.gpuUsagePercent))%",
                    subtitle: l10n("system_stats.graphics_engine"),
                    history: provider.gpuHistory,
                    accentColor: .green
                )
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Search & Sort Bar (Dynamic Expandable Search)
            HStack(spacing: 8) {
                if isSearchExpanded || !provider.searchQuery.isEmpty {
                    // Expanded Search Bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        
                        TextField(l10n("system_stats.search_processes"), text: $provider.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($isSearchFocused)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                provider.searchQuery = ""
                                isSearchExpanded = false
                                isSearchFocused = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
                } else {
                    // Collapsed: Compact Magnifying Glass Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isSearchExpanded = true
                            isSearchFocused = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(l10n("system_stats.search_tooltip"))
                    
                    // Full-width Sort Picker
                    Picker("", selection: $provider.sortMode) {
                        ForEach(SystemMetricsProvider.TaskSortMode.allCases, id: \.self) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            
            Divider()
            
            if let error = provider.processError { Text(error).font(.caption).foregroundColor(.red) }
            // Column Headers
            HStack {
                Text(l10n("system_stats.col_process"))
                    .frame(minWidth: 160, alignment: .leading)
                Spacer()
                Text(l10n("system_stats.col_cpu"))
                    .frame(width: 55, alignment: .trailing)
                Text(l10n("system_stats.col_ram"))
                    .frame(width: 70, alignment: .trailing)
                Text(l10n("system_stats.col_action"))
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Process List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(provider.filteredProcesses.prefix(60)) { item in
                        TaskRowView(
                            item: item,
                            isHovered: hoveredPid == item.pid,
                            isJustKilled: killedPid == item.pid,
                            onKill: {
                                if provider.killProcess(pid: item.pid) { killedPid = item.pid }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    if killedPid == item.pid {
                                        killedPid = nil
                                    }
                                }
                            }
                        )
                        .onHover { isHovered in
                            if isHovered {
                                hoveredPid = item.pid
                            } else if hoveredPid == item.pid {
                                hoveredPid = nil
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 290)
            
            Divider()
            
            // Footer
            HStack {
                Text(String(format: l10n("system_stats.kill_hint"), provider.processes.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.doc.horizontal")
                        Text(l10n("system_stats.activity_monitor_short"))
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                if let pinPreference {
                    PopoverPinButton(preference: pinPreference)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 460, height: 495)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.controlActiveState, .active)
    }
}

// MARK: - Hardware Metric Card with Sparkline

struct HardwareMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let history: [Double]
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(accentColor)
            }
            
            // Sparkline Graph
            SparklineView(data: history, color: accentColor)
                .frame(height: 26)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

struct SparklineView: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let points = dataPoints(in: geo.size)
            if points.count > 1 {
                Path { path in
                    path.move(to: points[0])
                    for pt in points.dropFirst() {
                        path.addLine(to: pt)
                    }
                }
                .stroke(color, lineWidth: 1.5)
                
                // Subtle fill below curve
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    path.addLine(to: points[0])
                    for pt in points.dropFirst() {
                        path.addLine(to: pt)
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
        }
    }
    
    private func dataPoints(in size: CGSize) -> [CGPoint] {
        guard data.count > 1 else { return [] }
        let step = size.width / CGFloat(data.count - 1)
        return data.enumerated().map { index, val in
            let clamped = max(0.0, min(100.0, val))
            let y = size.height - (CGFloat(clamped / 100.0) * size.height)
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let item: ProcessTaskItem
    let isHovered: Bool
    let isJustKilled: Bool
    let onKill: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // App icon or generic gear
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                } else {
                    Image(systemName: item.isUserApp ? "app.dashed" : "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                }
            }
            
            // Name + PID
            VStack(alignment: .leading, spacing: 1) {
                if let widgetTitle = item.widgetTitle {
                    Text("Web Widget (\(widgetTitle))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text("PID \(item.pid)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 160, alignment: .leading)
            
            Spacer()
            
            // CPU %
            Text("\(String(format: "%.1f", item.cpuPercent))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(cpuColor(item.cpuPercent))
                .frame(width: 55, alignment: .trailing)
            
            // Memory MB
            Text(formatMemory(item.memoryMB))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            
            // Kill Action Button (Kompaktes X statt redundantem Text)
            Group {
                if isJustKilled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 22, height: 22)
                } else {
                    Button(action: onKill) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isHovered ? .white : .red.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(isHovered ? Color.red : Color.red.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(String(format: l10n("system_stats.kill_tooltip"), item.name))
                }
            }
            .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }
    
    private func cpuColor(_ cpu: Double) -> Color {
        if cpu > 35.0 { return .red }
        if cpu > 15.0 { return .orange }
        return .primary
    }
    
    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024.0 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return "\(Int(mb)) MB"
    }
}
