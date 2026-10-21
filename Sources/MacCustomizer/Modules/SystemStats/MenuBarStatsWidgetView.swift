import SwiftUI

public struct MenuBarStatsWidgetView: View {
    @ObservedObject var provider = SystemMetricsProvider.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            // GPU
            HStack(spacing: 3) {
                VStack(spacing: 0) {
                    Text("G")
                    Text("P")
                    Text("U")
                }
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.secondary)
                
                Text("\(Int(provider.gpuUsagePercent))%")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                
                MiniSparkline(data: provider.gpuHistory, color: .green)
                    .frame(width: 20, height: 12)
            }
            
            // RAM
            HStack(spacing: 3) {
                VStack(spacing: 0) {
                    Text("R")
                    Text("A")
                    Text("M")
                }
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.secondary)
                
                Text("\(Int(provider.memoryUsagePercent))%")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                
                MiniBarGauge(percent: provider.memoryUsagePercent, color: .purple)
                    .frame(width: 22, height: 10)
            }
            
            // CPU
            HStack(spacing: 3) {
                VStack(spacing: 0) {
                    Text("C")
                    Text("P")
                    Text("U")
                }
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.secondary)
                
                Text("\(Int(provider.cpuUsagePercent))%")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                
                MiniSparkline(data: provider.cpuHistory, color: .blue)
                    .frame(width: 20, height: 12)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
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
                Path { path in
                    let step = w / CGFloat(data.count - 1)
                    let firstY = h - (CGFloat(min(100.0, max(0.0, data[0])) / 100.0) * h)
                    path.move(to: CGPoint(x: 0, y: firstY))
                    for (i, val) in data.enumerated().dropFirst() {
                        let y = h - (CGFloat(min(100.0, max(0.0, val)) / 100.0) * h)
                        path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
                    }
                }
                .stroke(color, lineWidth: 1.2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
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
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillW, height: geo.size.height - 2)
                    .padding(.leading, 1)
            }
        }
    }
}
