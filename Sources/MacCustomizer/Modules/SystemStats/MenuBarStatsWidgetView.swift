import SwiftUI

public struct MenuBarStatsWidgetView: View {
    @ObservedObject var provider = SystemMetricsProvider.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 5) {
            // GPU Pill
            MetricPill(title: "GPU", value: "\(Int(provider.gpuUsagePercent))%", color: .green) {
                MiniSparkline(data: provider.gpuHistory, color: .green)
                    .frame(width: 20, height: 11)
            }
            
            // RAM Pill
            MetricPill(title: "RAM", value: "\(Int(provider.memoryUsagePercent))%", color: .purple) {
                MiniBarGauge(percent: provider.memoryUsagePercent, color: .purple)
                    .frame(width: 20, height: 9)
            }
            
            // CPU Pill
            MetricPill(title: "CPU", value: "\(Int(provider.cpuUsagePercent))%", color: .blue) {
                MiniSparkline(data: provider.cpuHistory, color: .blue)
                    .frame(width: 20, height: 11)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(height: 22)
    }
}

struct MetricPill<Content: View>: View {
    let title: String
    let value: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: -1) {
                Text(title)
                    .font(.system(size: 6.5, weight: .heavy))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 7.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            content()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.2), lineWidth: 0.6)
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
                    // Shaded gradient under curve for high contrast
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
                    .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    
                    // Main line stroke
                    Path { path in
                        let step = w / CGFloat(data.count - 1)
                        let firstY = h - (CGFloat(min(100.0, max(0.0, data[0])) / 100.0) * h)
                        path.move(to: CGPoint(x: 0, y: firstY))
                        for (i, val) in data.enumerated().dropFirst() {
                            let y = h - (CGFloat(min(100.0, max(0.0, val)) / 100.0) * h)
                            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                }
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
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
            let fillW = max(3.0, geo.size.width * CGFloat(min(100.0, max(0.0, percent)) / 100.0))
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.12))
                
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                
                // Value Fill
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillW, height: max(2, geo.size.height - 2))
                    .padding(.leading, 1)
            }
        }
    }
}
