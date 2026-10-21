import SwiftUI

public struct MenuBarStatsWidgetView: View {
    @ObservedObject var provider = SystemMetricsProvider.shared
    @ObservedObject var module = ModuleManager.shared.systemStatsModule
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            // CPU
            if module.showCPU {
                MetricItemView(
                    label: "CPU",
                    value: "\(Int(provider.cpuUsagePercent))%",
                    color: .blue,
                    showLabel: module.showLabels,
                    showPercentage: module.showPercentage,
                    showGraph: module.showGraphs,
                    useBackground: module.useSubtleBackground
                ) {
                    MiniSparkline(data: provider.cpuHistory, color: .blue)
                        .frame(width: 22, height: 12)
                }
            }
            
            // RAM
            if module.showRAM {
                MetricItemView(
                    label: "RAM",
                    value: "\(Int(provider.memoryUsagePercent))%",
                    color: .purple,
                    showLabel: module.showLabels,
                    showPercentage: module.showPercentage,
                    showGraph: module.showGraphs,
                    useBackground: module.useSubtleBackground
                ) {
                    MiniBarGauge(percent: provider.memoryUsagePercent, color: .purple)
                        .frame(width: 20, height: 10)
                }
            }
            
            // GPU
            if module.showGPU {
                MetricItemView(
                    label: "GPU",
                    value: "\(Int(provider.gpuUsagePercent))%",
                    color: .green,
                    showLabel: module.showLabels,
                    showPercentage: module.showPercentage,
                    showGraph: module.showGraphs,
                    useBackground: module.useSubtleBackground
                ) {
                    MiniSparkline(data: provider.gpuHistory, color: .green)
                        .frame(width: 22, height: 12)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
    }
}

struct MetricItemView<Content: View>: View {
    let label: String
    let value: String
    let color: Color
    let showLabel: Bool
    let showPercentage: Bool
    let showGraph: Bool
    let useBackground: Bool
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack(spacing: 3) {
            if showLabel {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
            }
            
            if showPercentage {
                Text(value)
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            
            if showGraph {
                content()
            }
        }
        .padding(.horizontal, useBackground ? 5 : 2)
        .padding(.vertical, useBackground ? 2 : 0)
        .background(
            Group {
                if useBackground {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))
                }
            }
        )
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
                    // Subtle transparent gradient under line
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
                    
                    // Crisp stroke
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
