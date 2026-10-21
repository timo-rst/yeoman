import SwiftUI

public struct StatsWidgetWidthKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct MenuBarStatsWidgetView: View {
    @ObservedObject var provider = SystemMetricsProvider.shared
    @ObservedObject var module = ModuleManager.shared.systemStatsModule
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: module.useSubtleBackground ? 5 : 4) {
            // CPU
            if module.showCPU {
                CompactMetricItemView(
                    label: "CPU",
                    value: "\(Int(provider.cpuUsagePercent))%",
                    percent: provider.cpuUsagePercent,
                    color: .blue,
                    showLabel: module.showLabels,
                    showPercentage: module.showPercentage,
                    showGraph: module.showGraphs,
                    layoutMode: module.layoutMode,
                    graphStyle: module.graphStyle,
                    history: provider.cpuHistory,
                    useBackground: module.useSubtleBackground
                )
            }
            
            // RAM
            if module.showRAM {
                CompactMetricItemView(
                    label: "RAM",
                    value: "\(Int(provider.memoryUsagePercent))%",
                    percent: provider.memoryUsagePercent,
                    color: .purple,
                    showLabel: module.showLabels,
                    showPercentage: module.showPercentage,
                    showGraph: module.showGraphs,
                    layoutMode: module.layoutMode,
                    graphStyle: module.graphStyle,
                    history: provider.ramHistory,
                    useBackground: module.useSubtleBackground
                )
            }
            
            // GPU
            if module.showGPU {
                CompactMetricItemView(
                    label: "GPU",
                    value: "\(Int(provider.gpuUsagePercent))%",
                    percent: provider.gpuUsagePercent,
                    color: .green,
                    showLabel: module.showLabels,
                    showPercentage: module.showPercentage,
                    showGraph: module.showGraphs,
                    layoutMode: module.layoutMode,
                    graphStyle: module.graphStyle,
                    history: provider.gpuHistory,
                    useBackground: module.useSubtleBackground
                )
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 22)
        .fixedSize()
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: StatsWidgetWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(StatsWidgetWidthKey.self) { newWidth in
            if newWidth > 10 {
                module.updateStatusItemWidth(newWidth)
            }
        }
    }
}

struct CompactMetricItemView: View {
    let label: String
    let value: String
    let percent: Double
    let color: Color
    let showLabel: Bool
    let showPercentage: Bool
    let showGraph: Bool
    let layoutMode: StatsLayoutMode
    let graphStyle: StatsGraphStyle
    let history: [Double]
    let useBackground: Bool
    
    var body: some View {
        Group {
            if layoutMode == .vertical {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .padding(.horizontal, useBackground ? 4 : 2)
        .padding(.vertical, useBackground ? 1.5 : 0)
        .background(
            Group {
                if useBackground {
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(Color.primary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4.5)
                                .stroke(color.opacity(0.35), lineWidth: 0.5)
                        )
                }
            }
        )
    }
    
    // VERTICAL LAYOUT (Stats / iStat Menus style: compact stacked text)
    private var verticalLayout: some View {
        HStack(spacing: 3) {
            // Text stack: Label on top, Value below
            VStack(alignment: .trailing, spacing: -1) {
                if showLabel {
                    Text(label)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(color)
                        .lineLimit(1)
                }
                if showPercentage {
                    Text(value)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            
            // Visual indicator
            if showGraph && graphStyle != .none {
                if graphStyle == .miniBar {
                    // Vertical fill bar gauge
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 4.5, height: 16)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color)
                            .frame(width: 4.5, height: max(2.0, 16.0 * CGFloat(min(100.0, max(0.0, percent)) / 100.0)))
                    }
                } else {
                    // Mini sparkline graph
                    MiniSparkline(data: history, color: color)
                        .frame(width: 18, height: 13)
                }
            }
        }
    }
    
    // HORIZONTAL LAYOUT
    private var horizontalLayout: some View {
        HStack(spacing: 3) {
            if showLabel {
                Text(label)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(color)
            }
            if showPercentage {
                Text(value)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            if showGraph && graphStyle != .none {
                if graphStyle == .miniBar {
                    MiniBarGauge(percent: percent, color: color)
                        .frame(width: 16, height: 9)
                } else {
                    MiniSparkline(data: history, color: color)
                        .frame(width: 20, height: 11)
                }
            }
        }
    }
}

struct MiniSparkline: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if data.count > 1 {
                ZStack {
                    Path { path in
                        let step = w / CGFloat(data.count - 1)
                        path.move(to: CGPoint(x: 0, y: h))
                        let firstY = h - (CGFloat(min(100.0, max(0.0, data[0])) / 100.0) * h)
                        path.addLine(to: CGPoint(x: 0, y: firstY))
                        for (i, val) in data.enumerated().dropFirst() {
                            let y = h - (CGFloat(min(100.0, max(0.0, val)) / 100.0) * h)
                            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.4), color.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    
                    Path { path in
                        let step = w / CGFloat(data.count - 1)
                        let firstY = h - (CGFloat(min(100.0, max(0.0, data[0])) / 100.0) * h)
                        path.move(to: CGPoint(x: 0, y: firstY))
                        for (i, val) in data.enumerated().dropFirst() {
                            let y = h - (CGFloat(min(100.0, max(0.0, val)) / 100.0) * h)
                            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
    }
}

struct MiniBarGauge: View {
    let percent: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let fillW = max(2.0, geo.size.width * CGFloat(min(100.0, max(0.0, percent)) / 100.0))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillW, height: max(2, geo.size.height - 2))
                    .padding(.leading, 1)
            }
        }
    }
}
