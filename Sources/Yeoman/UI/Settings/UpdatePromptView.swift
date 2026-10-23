import SwiftUI
import AppKit

public struct UpdatePromptView: View {
    @ObservedObject var updater = UpdateManager.shared
    @ObservedObject var l10n = LocalizationManager.shared
    
    let version: String
    let notes: String
    let downloadUrl: URL?
    let htmlUrl: URL
    let onDismiss: () -> Void
    let onIgnore: () -> Void
    
    public init(
        version: String,
        notes: String,
        downloadUrl: URL?,
        htmlUrl: URL,
        onDismiss: @escaping () -> Void,
        onIgnore: @escaping () -> Void
    ) {
        self.version = version
        self.notes = notes
        self.downloadUrl = downloadUrl
        self.htmlUrl = htmlUrl
        self.onDismiss = onDismiss
        self.onIgnore = onIgnore
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(l10n.localized("updates.popup_title"))
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Text("v\(version)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundColor(.accentColor)
                    }
                    
                    Text("Yeoman **\(version)** ist verfügbar (installiert: \(updater.currentVersion)).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(l10n.localized("updates.popup_subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            
            Divider()
            
            // Release Notes Box
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.localized("updates.release_notes"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Keine weiteren Versionshinweise vorhanden." : notes)
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.primary.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // In-flight progress or error feedback
            if case .downloading(let progress) = updater.status {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(l10n.localized("updates.downloading")) (\(Int(progress * 100))%)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            } else if case .installing = updater.status {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("Update wird verifiziert und installiert...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            } else if case .failed(let msg) = updater.status {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // Footer Action Buttons
            HStack(spacing: 10) {
                Link(l10n.localized("updates.view_on_github"), destination: htmlUrl)
                    .font(.caption)
                
                Spacer()
                
                Button(l10n.localized("updates.remind_later")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
                
                Button(l10n.localized("updates.ignore_button")) {
                    onIgnore()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                
                if let download = downloadUrl {
                    Button(action: {
                        updater.downloadAndInstall(from: download)
                    }) {
                        HStack(spacing: 6) {
                            if isBusy {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(l10n.localized("updates.install_button"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 540)
    }
    
    private var isBusy: Bool {
        switch updater.status {
        case .downloading, .installing:
            return true
        default:
            return false
        }
    }
}

@MainActor
public final class UpdatePromptController: NSObject, NSWindowDelegate {
    public static let shared = UpdatePromptController()
    
    private var promptWindow: NSWindow?
    private var currentShownVersion: String?
    
    public override init() {
        super.init()
    }
    
    public func show(version: String, notes: String, downloadUrl: URL?, htmlUrl: URL) {
        if let window = promptWindow, window.isVisible, currentShownVersion == version {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        self.currentShownVersion = version
        let view = UpdatePromptView(
            version: version,
            notes: notes,
            downloadUrl: downloadUrl,
            htmlUrl: htmlUrl,
            onDismiss: { [weak self] in
                self?.close()
            },
            onIgnore: { [weak self] in
                UserDefaults.standard.set(version, forKey: "update_ignored_version")
                self?.close()
            }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yeoman Update"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        self.promptWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public func close() {
        promptWindow?.orderOut(nil)
        promptWindow = nil
    }
    
    public func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == promptWindow {
            promptWindow = nil
        }
    }
}
