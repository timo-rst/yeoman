import SwiftUI

public protocol SubTabProtocol: Hashable, Identifiable {
    var title: String { get }
    var iconName: String { get }
}

public struct UnifiedSubTabBar<Tab: SubTabProtocol>: View {
    let tabs: [Tab]
    @Binding var selectedTab: Tab
    @Namespace private var tabAnimation
    @Environment(\.colorScheme) private var colorScheme
    
    public init(tabs: [Tab], selectedTab: Binding<Tab>) {
        self.tabs = tabs
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: tabAnimation
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 420)
        .frame(height: 34)
    }
}

private struct TabButton<Tab: SubTabProtocol>: View {
    let tab: Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? .primary : .secondary))
                
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 2, x: 0, y: 1)
                            .matchedGeometryEffect(id: "selectedSubTabHighlight", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
