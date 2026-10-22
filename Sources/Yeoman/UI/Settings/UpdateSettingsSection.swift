import SwiftUI

public struct UpdateSettingsSection: View {
    @ObservedObject var updater = UpdateManager.shared
    @ObservedObject var l10n = LocalizationManager.shared
    public var isDetailedView: Bool = false
    
    public init(isDetailedView: Bool = false) {
        self.isDetailedView = isDetailedView
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text(l10n.localized("updates.title"))
                    .font(.headline)
                
                Spacer()
                
                // Status Badge
                badgeForCurrentStatus
            }
            
            Divider()
            
            // Auto-Check Toggle
            HStack(spacing: 6) {
                Toggle(l10n.localized("updates.auto_check"), isOn: $updater.autoCheckForUpdates)
                    .font(.subheadline)
                InfoTooltip(text: l10n.localized("updates.auto_check_tooltip"))
            }
            
            // Current Status & Last Checked Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    statusDescriptionView
                    
                    if let lastChecked = updater.lastCheckedDate {
                        Text("\(l10n.localized("updates.last_checked")) \(formattedDate(lastChecked))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer(minLength: 16)
                
                Button(action: {
                    updater.checkForUpdates(silent: false)
                }) {
                    HStack(spacing: 6) {
                        if case .checking = updater.status {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(l10n.localized("updates.check_button"))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(updater.status == .checking || isDownloadingOrInstalling)
            }
            
            // Update Available Action Card
            if case .updateAvailable(let version, let notes, let downloadUrl, let htmlUrl) = updater.status {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.yellow)
                        Text("\(l10n.localized("updates.available")) **\(version)**")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    if !notes.isEmpty {
                        ScrollView {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 100)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                    
                    HStack(spacing: 12) {
                        if let download = downloadUrl {
                            Button(l10n.localized("updates.install_button")) {
                                updater.downloadAndInstall(from: download)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Button(l10n.localized("updates.view_on_github")) {
                            NSWorkspace.shared.open(htmlUrl)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
            }
            
            // Download Progress
            if case .downloading(let progress) = updater.status {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Update wird heruntergeladen...")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: progress, total: 1.0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
            }
            
            // Installing indicator
            if case .installing = updater.status {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Update wird installiert & Yeoman neu gestartet...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
    
    private var isDownloadingOrInstalling: Bool {
        if case .downloading = updater.status { return true }
        if case .installing = updater.status { return true }
        return false
    }
    
    @ViewBuilder
    private var statusDescriptionView: some View {
        switch updater.status {
        case .idle:
            Text("\(l10n.localized("updates.current_version")) v\(updater.currentVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                
        case .checking:
            HStack(spacing: 6) {
                Text(l10n.localized("updates.checking"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(l10n.localized("updates.up_to_date")) (v\(updater.currentVersion))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
        case .updateAvailable(let version, _, _, _):
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.accentColor)
                Text("\(l10n.localized("updates.available")) \(version) (\(l10n.localized("updates.current_version")) v\(updater.currentVersion))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
        case .downloading:
            Text(l10n.localized("updates.downloading"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                
        case .installing:
            Text(l10n.localized("updates.downloading"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
    
    @ViewBuilder
    private var badgeForCurrentStatus: some View {
        switch updater.status {
        case .upToDate:
            Text("Aktuell")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.15)))
                .foregroundColor(.green)
                
        case .updateAvailable:
            Text("Neu")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                .foregroundColor(.accentColor)
                
        default:
            EmptyView()
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}
