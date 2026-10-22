import SwiftUI

public struct ModuleHeaderView<ExtraContent: View>: View {
    public let title: String
    public let subtitle: String
    public let icon: String
    @Binding public var isEnabled: Bool
    public let extraContent: ExtraContent
    
    @ObservedObject private var l10n = LocalizationManager.shared
    
    public init(
        title: String,
        subtitle: String,
        icon: String,
        isEnabled: Binding<Bool>,
        @ViewBuilder extraContent: () -> ExtraContent = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._isEnabled = isEnabled
        self.extraContent = extraContent()
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isEnabled ? .accentColor : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Text(isEnabled ? l10n.localized("common.enabled") : l10n.localized("common.disabled"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isEnabled ? .primary : .secondary)
                    
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            
            if !isEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(l10n.localized("module.disabled_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }
            
            extraContent
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
