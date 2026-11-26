import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

public struct TerminalSaverSettingsView: View {
    private static let previewPanelWidth: CGFloat = 400
    private static let previewPanelHeight: CGFloat = 225
    private static let inspectorControlWidth: CGFloat = 164
    private static let generalControlColumnWidth: CGFloat = 300

    @ObservedObject var module: TerminalSaverModule
    @ObservedObject var manager: TerminalSaverManager
    @ObservedObject var l10nObj = LocalizationManager.shared
    @State private var mediaSearchText: String = ""
    @State private var editingMediaName: String = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var scrollToMediaID: UUID?
    @State private var hoveredKeyTarget: TerminalSaverKeyCaptureController.Target?
    @StateObject private var keyCapture = TerminalSaverKeyCaptureController()
    @AppStorage("terminal_saver.scenes_expanded") private var isScenesExpanded: Bool = true
    @AppStorage("terminal_saver.custom_media_expanded") private var isCustomMediaExpanded: Bool = true

    public init(module: TerminalSaverModule) {
        self.module = module
        self.manager = module.manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            ModuleHeaderView(
                title: module.name,
                subtitle: l10n("terminal_saver.subtitle"),
                icon: "terminal",
                isEnabled: $module.isEnabled
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Pinned 16:9 Live Preview + Selected Clip/Scene Inspector
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.tv")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                    Text(l10n("terminal_saver.preview_header"))
                        .font(.headline)
                    Spacer()
                }

                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        TerminalASCIIPreviewView(model: manager.previewModel)
                            .frame(width: Self.previewPanelWidth, height: Self.previewPanelHeight)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.04, green: 0.05, blue: 0.06)))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )

                        if manager.isDecodingPreview {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(l10n("terminal_saver.loading_preview"))
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                        }
                    }
                    .frame(width: Self.previewPanelWidth, height: Self.previewPanelHeight)

                    selectedSourceInspector()
                        .padding(10)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: Self.previewPanelHeight,
                            maxHeight: Self.previewPanelHeight,
                            alignment: .topLeading
                        )
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .disabled(!module.isEnabled)
                        .opacity(module.isEnabled ? 1.0 : 0.6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = manager.lastError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: { manager.lastError = nil }) {
                                Image(systemName: "xmark")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
                    }

                    Group {
                        // Card 2: Scenes & Media Library
                        let activePool = manager.config.effectiveSelectedSources
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "photo.stack")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                Text(l10n("terminal_saver.media_header"))
                                    .font(.headline)
                                Spacer()
                                if manager.config.isShuffleActive {
                                    Text(String(format: l10n("terminal_saver.shuffle_active_badge"), activePool.count))
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                }
                            }

                            let selectedBuiltInCount = TerminalSaverBuiltInScene.allCases.filter {
                                activePool.contains(.builtIn($0))
                            }.count
                            let selectedCustomMediaCount = manager.config.mediaItems.filter {
                                activePool.contains(.media($0.id))
                            }.count

                            Divider()

                            sectionDisclosureHeader(
                                title: l10n("terminal_saver.builtin_scenes"),
                                isExpanded: $isScenesExpanded,
                                collapsedCount: "\(selectedBuiltInCount)/\(TerminalSaverBuiltInScene.allCases.count)",
                                fillWidth: true
                            )

                            if isScenesExpanded {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(TerminalSaverBuiltInScene.allCases) { scene in
                                        let source = TerminalSaverSource.builtIn(scene)
                                        builtInSceneTile(
                                            scene,
                                            isActive: activePool.contains(source),
                                            isInspected: manager.previewedSource == source
                                        )
                                    }
                                }
                            }

                            Divider()

                            HStack(spacing: 10) {
                                HStack(spacing: 6) {
                                    sectionDisclosureHeader(
                                        title: l10n("terminal_saver.custom_media"),
                                        isExpanded: $isCustomMediaExpanded,
                                        collapsedCount: manager.config.mediaItems.isEmpty
                                            ? nil
                                            : "\(selectedCustomMediaCount)/\(manager.config.mediaItems.count)",
                                        fillWidth: false
                                    )
                                    InfoTooltip(text: l10n("terminal_saver.custom_media_tooltip"))
                                }
                                Spacer()
                                if !manager.config.mediaItems.isEmpty && isCustomMediaExpanded {
                                    HStack(spacing: 5) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField(l10n("terminal_saver.search_media"), text: $mediaSearchText)
                                            .textFieldStyle(.plain)
                                            .font(.caption)
                                        if !mediaSearchText.isEmpty {
                                            Button {
                                                mediaSearchText = ""
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(width: 210)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                                    )
                                }
                                Button {
                                    openMediaPicker()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus.circle.fill")
                                        Text(l10n("terminal_saver.add_media"))
                                    }
                                    .fontWeight(.medium)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            if isCustomMediaExpanded {
                                let trimmedQuery = mediaSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                let filteredMediaItems = trimmedQuery.isEmpty
                                    ? manager.config.mediaItems
                                    : manager.config.mediaItems.filter {
                                        $0.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                                            || $0.fileExtension.localizedCaseInsensitiveContains(trimmedQuery)
                                    }
                                if manager.config.mediaItems.isEmpty {
                                    Text(l10n("terminal_saver.no_media_hint"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                } else if filteredMediaItems.isEmpty {
                                    Text(l10n("terminal_saver.no_search_results"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                } else {
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(filteredMediaItems) { item in
                                            let source = TerminalSaverSource.media(item.id)
                                            customMediaTile(
                                                item,
                                                isActive: activePool.contains(source),
                                                isInspected: manager.previewedSource == source
                                            )
                                            .id(item.id)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                        // Card 3: General Settings
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                Text(l10n("terminal_saver.general_header"))
                                    .font(.headline)
                            }

                            Divider()

                            HStack {
                                HStack(spacing: 6) {
                                    Text(l10n("terminal_saver.idle_timeout"))
                                        .font(.subheadline)
                                    InfoTooltip(text: l10n("terminal_saver.idle_timeout_tooltip"))
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Slider(
                                        value: Binding(
                                            get: { Double(manager.config.idleTimeoutSeconds) },
                                            set: { value in
                                                let step = 15.0
                                                let seconds = Int((value / step).rounded() * step)
                                                manager.updateConfig { $0.idleTimeoutSeconds = seconds }
                                            }
                                        ),
                                        in: Double(TerminalSaverPolicy.idleTimeoutRange.lowerBound)...Double(TerminalSaverPolicy.idleTimeoutRange.upperBound)
                                    )
                                    .controlSize(.small)
                                    Text(formattedTimeout(manager.config.idleTimeoutSeconds))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                        .frame(width: 52, alignment: .trailing)
                                }
                                .frame(width: Self.generalControlColumnWidth, height: 24)
                            }
                            .frame(minHeight: 24)

                            transitionAnimationRow(
                                title: l10n("terminal_saver.start_animation"),
                                instantTitle: l10n("terminal_saver.start_instant"),
                                selection: Binding(
                                    get: { manager.config.startAnimation },
                                    set: { val in
                                        manager.updateConfig { $0.startAnimation = val }
                                        if val != .instant {
                                            manager.triggerStartPreview()
                                        }
                                    }
                                ),
                                speed: Binding(
                                    get: { manager.config.startAnimationSpeed },
                                    set: { val in
                                        let snapped = (val * 10).rounded() / 10
                                        manager.updateConfig { $0.startAnimationSpeed = snapped }
                                    }
                                ),
                                isInstant: manager.config.startAnimation == .instant,
                                onSpeedCommit: { manager.triggerStartPreview() }
                            )

                            transitionAnimationRow(
                                title: l10n("terminal_saver.wake_animation"),
                                instantTitle: l10n("terminal_saver.wake_instant"),
                                selection: Binding(
                                    get: { manager.config.wakeAnimation },
                                    set: { val in
                                        manager.updateConfig { $0.wakeAnimation = val }
                                        if val != .instant {
                                            manager.triggerWakePreview()
                                        }
                                    }
                                ),
                                speed: Binding(
                                    get: { manager.config.wakeAnimationSpeed },
                                    set: { val in
                                        let snapped = (val * 10).rounded() / 10
                                        manager.updateConfig { $0.wakeAnimationSpeed = snapped }
                                    }
                                ),
                                isInstant: manager.config.wakeAnimation == .instant,
                                onSpeedCommit: { manager.triggerWakePreview() }
                            )

                            switchTransitionRow()

                            autoAdvanceControls()

                            navigationKeysRow()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                        // Card 4: Terminal & Shell Integration
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 6) {
                                Image(systemName: "apple.terminal")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                Text(l10n("terminal_saver.shells_header"))
                                    .font(.headline)
                                InfoTooltip(text: l10n("terminal_saver.shells_subtitle"))
                            }

                            Divider()

                            ForEach(TerminalShellTarget.allCases) { target in
                                let status = manager.shellStatuses[target]
                                let installed = status?.isInstalled ?? false
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(target.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(status?.configPath ?? "")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { installed },
                                        set: { enable in
                                            if enable {
                                                manager.installShell(target)
                                            } else {
                                                manager.uninstallShell(target)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                }
                            }

                            Divider()

                            HStack(spacing: 6) {
                                Toggle(l10n("terminal_saver.menubar_toggle"), isOn: $module.showsDedicatedStatusItem)
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .disabled(!module.isEnabled)
                    .opacity(module.isEnabled ? 1.0 : 0.6)
                }
                .padding(20)
            }
            .onChange(of: scrollToMediaID) { _, targetID in
                guard let targetID else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                    scrollToMediaID = nil
                }
            }
            }
        }
        .onAppear {
            syncEditingMediaName(for: manager.previewedSource)
            manager.startPreview()
            manager.refreshShellStatuses()
        }
        .onDisappear {
            if case .media(let id) = manager.previewedSource {
                commitMediaRename(for: id)
            }
            keyCapture.stop()
            manager.stopPreview()
        }
        .onChange(of: module.isEnabled) { _, enabled in
            if !enabled {
                keyCapture.stop()
            }
        }
        .onChange(of: manager.previewedSource) { oldSource, newSource in
            if case .media(let oldID) = oldSource, oldSource != newSource {
                commitMediaRename(for: oldID)
            }
            syncEditingMediaName(for: newSource)
        }
        .onChange(of: isRenameFieldFocused) { _, focused in
            if !focused, case .media(let id) = manager.previewedSource {
                commitMediaRename(for: id)
            }
        }
    }

    @ViewBuilder
    private func speedControl(
        speed: Binding<Double>,
        isInstant: Bool,
        onSpeedCommit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(
                value: Binding(
                    get: { TerminalSaverPolicy.speedSliderPosition(for: speed.wrappedValue) },
                    set: { pos in
                        speed.wrappedValue = TerminalSaverPolicy.speedFromSliderPosition(pos)
                    }
                ),
                in: -1.0...1.0,
                onEditingChanged: { editing in
                    if !editing && !isInstant {
                        onSpeedCommit()
                    }
                }
            )
            .controlSize(.small)
            Text(String(format: "%.1f×", speed.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(width: 152, height: 24)
        .disabled(isInstant)
        .opacity(isInstant ? 0.35 : 1.0)
        .help(l10n("terminal_saver.animation_speed_tooltip"))
        .accessibilityLabel(l10n("terminal_saver.animation_speed_tooltip"))
    }

    @ViewBuilder
    private func transitionAnimationRow(
        title: String,
        instantTitle: String,
        selection: Binding<TerminalWakeAnimation>,
        speed: Binding<Double>,
        isInstant: Bool,
        onSpeedCommit: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 12) {
                uniformMenuPicker(
                    title: title,
                    width: 136,
                    options: [
                        (l10n("terminal_saver.animation_random"), .random),
                        (l10n("terminal_saver.wake_glitch"), .glitch),
                        (l10n("terminal_saver.transition_swarm"), .swarm),
                        (l10n("terminal_saver.transition_decode"), .decode),
                        (l10n("terminal_saver.transition_morph"), .morph),
                        (l10n("terminal_saver.transition_shatter"), .shatter),
                        (l10n("terminal_saver.transition_rain"), .rain),
                        (l10n("terminal_saver.transition_ripple"), .ripple),
                        (l10n("terminal_saver.wake_dissolve"), .dissolve),
                        (l10n("terminal_saver.wake_cascade"), .cascade),
                        (l10n("terminal_saver.wake_curtain"), .curtain),
                        (l10n("terminal_saver.wake_iris"), .iris),
                        (instantTitle, .instant)
                    ],
                    selection: selection
                )

                speedControl(speed: speed, isInstant: isInstant, onSpeedCommit: onSpeedCommit)
            }
            .frame(width: Self.generalControlColumnWidth, height: 24)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func switchTransitionRow() -> some View {
        let isInstant = manager.config.transitionAnimation == .instant
        let title = l10n("terminal_saver.transition_animation")
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 12) {
                uniformMenuPicker(
                    title: title,
                    width: 136,
                    options: [
                        (l10n("terminal_saver.animation_random"), .random),
                        (l10n("terminal_saver.transition_glitch"), .glitch),
                        (l10n("terminal_saver.transition_swarm"), .swarm),
                        (l10n("terminal_saver.transition_decode"), .decode),
                        (l10n("terminal_saver.transition_morph"), .morph),
                        (l10n("terminal_saver.transition_shatter"), .shatter),
                        (l10n("terminal_saver.transition_rain"), .rain),
                        (l10n("terminal_saver.transition_ripple"), .ripple),
                        (l10n("terminal_saver.transition_slide"), .slide),
                        (l10n("terminal_saver.transition_dissolve"), .dissolve),
                        (l10n("terminal_saver.transition_wipe"), .wipe),
                        (l10n("terminal_saver.transition_instant"), .instant)
                    ],
                    selection: Binding(
                        get: { manager.config.transitionAnimation },
                        set: { val in
                            manager.updateConfig { $0.transitionAnimation = val }
                            if val != .instant {
                                manager.triggerTransitionPreview()
                            }
                        }
                    )
                )

                speedControl(
                    speed: Binding(
                        get: { manager.config.transitionAnimationSpeed },
                        set: { val in
                            let snapped = (val * 10).rounded() / 10
                            manager.updateConfig { $0.transitionAnimationSpeed = snapped }
                        }
                    ),
                    isInstant: isInstant,
                    onSpeedCommit: { manager.triggerTransitionPreview() }
                )
            }
            .frame(width: Self.generalControlColumnWidth, height: 24)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func autoAdvanceControls() -> some View {
        let settings = manager.config.autoAdvance
        let title = l10n("terminal_saver.auto_advance")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    InfoTooltip(text: l10n("terminal_saver.auto_advance_tooltip"))
                }
                Spacer()
                Toggle(title, isOn: Binding(
                    get: { manager.config.autoAdvance.mode == .time },
                    set: { enabled in manager.updateConfig { $0.autoAdvance.mode = enabled ? .time : .off } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if settings.mode == .time {
                let durationTitle = l10n("terminal_saver.auto_advance_duration")
                let duration = formattedTimeout(settings.durationSeconds)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(durationTitle)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Spacer()
                        Text(duration)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Stepper(durationTitle, value: Binding(
                            get: { manager.config.autoAdvance.durationSeconds },
                            set: { seconds in manager.updateConfig { $0.autoAdvance.durationSeconds = seconds } }
                        ), in: TerminalSaverPolicy.autoAdvanceDurationRange, step: 5)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityValue(duration)
                    }
                    .frame(minHeight: 24)

                    HStack(spacing: 8) {
                        Text(l10n("terminal_saver.auto_advance_cutoff"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Spacer()
                        uniformSegmentedPill(
                            width: Self.generalControlColumnWidth,
                            options: [
                                (l10n("terminal_saver.auto_advance_finish_loop"), TerminalSaverAutoAdvanceCutoff.finishLoop),
                                (l10n("terminal_saver.auto_advance_hard_cut"), TerminalSaverAutoAdvanceCutoff.hardCut)
                            ],
                            selection: Binding(
                                get: { manager.config.autoAdvance.cutoff },
                                set: { cutoff in manager.updateConfig { $0.autoAdvance.cutoff = cutoff } }
                            )
                        )
                    }
                    .frame(minHeight: 24)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 2)
                        .padding(.vertical, 3)
                }
                .padding(.leading, 10)
            }
        }
    }

    @ViewBuilder
    private func navigationKeysRow() -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(l10n("terminal_saver.navigation_keys"))
                    .font(.subheadline)
                InfoTooltip(text: l10n("terminal_saver.navigation_keys_tooltip"))
            }
            Spacer()
            HStack(spacing: 10) {
                keyCaptureButton(
                    target: .previous,
                    title: l10n("terminal_saver.nav_previous"),
                    key: manager.config.previousKey
                )
                keyCaptureButton(
                    target: .next,
                    title: l10n("terminal_saver.nav_next"),
                    key: manager.config.nextKey
                )
            }
            .frame(width: Self.generalControlColumnWidth, height: 26)
        }
        .frame(minHeight: 26)
    }

    @ViewBuilder
    private func keyCaptureButton(
        target: TerminalSaverKeyCaptureController.Target,
        title: String,
        key: TerminalSaverKey
    ) -> some View {
        let isRecording = keyCapture.recordingTarget == target
        let isHovered = hoveredKeyTarget == target
        let pillFill: Color = isRecording ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlColor)
        let borderOpacity: Double = isHovered ? 0.30 : 0.16
        let pillBorder: Color = isRecording ? Color.accentColor : Color.primary.opacity(borderOpacity)
        let borderWidth: CGFloat = isRecording ? 1.5 : 1

        Button {
            keyCapture.toggle(target) { capturedTarget, capturedKey in
                manager.updateConfig { cfg in
                    if capturedTarget == .previous {
                        if cfg.nextKey == capturedKey {
                            cfg.nextKey = cfg.previousKey
                        }
                        cfg.previousKey = capturedKey
                    } else {
                        if cfg.previousKey == capturedKey {
                            cfg.previousKey = cfg.nextKey
                        }
                        cfg.nextKey = capturedKey
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isRecording {
                    Text(l10n("terminal_saver.press_key"))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                } else {
                    keycapBadge(label: key.displayLabel)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(pillFill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillBorder, lineWidth: borderWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { hovering in
            hoveredKeyTarget = hovering ? target : (hoveredKeyTarget == target ? nil : hoveredKeyTarget)
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isRecording ? l10n("terminal_saver.press_key") : key.displayLabel)
    }

    @ViewBuilder
    private func keycapBadge(label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private func selectedSourceInspector() -> some View {
        switch manager.previewedSource {
        case .media(let id):
            if let item = manager.config.mediaItems.first(where: { $0.id == id }) {
                mediaInspector(item)
            } else {
                builtInSceneInspector(.bonfire)
            }
        case .builtIn(let scene):
            builtInSceneInspector(scene)
        }
    }

    private func mediaInspector(_ item: TerminalSaverMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(l10n("terminal_saver.rename_clip_placeholder"), text: $editingMediaName)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitMediaRename(for: item.id) }
                Text(item.fileExtension.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .frame(height: 22)

            Divider()

            renderStylePicker(selection: Binding<ASCIIRenderStyle?>(
                get: { item.style },
                set: { style in
                    guard let style else { return }
                    manager.updateMediaItem(id: item.id) { $0.style = style }
                }
            ))

            colorPresetPicker(selection: Binding(
                get: { item.colorPreset },
                set: { preset in manager.updateMediaItem(id: item.id) { $0.colorPreset = preset } }
            ))

            HStack {
                Text(l10n("terminal_saver.fit_mode"))
                    .font(.subheadline)
                Spacer()
                uniformSegmentedPill(
                    width: Self.inspectorControlWidth,
                    options: [
                        (l10n("terminal_saver.fit_contain"), ASCIIFitMode.contain),
                        (l10n("terminal_saver.fit_cover"), ASCIIFitMode.cover)
                    ],
                    selection: Binding(
                        get: { item.fitMode },
                        set: { val in manager.updateMediaItem(id: item.id) { $0.fitMode = val } }
                    )
                )
            }
            .frame(height: 24)

            if item.supportsAnimation {
                playbackSpeedSlider(speed: Binding(
                    get: { item.playbackSpeed },
                    set: { speed in manager.updateMediaItem(id: item.id) { $0.playbackSpeed = speed } }
                ))
                let loopTitle = l10n("terminal_saver.ping_pong_loop")
                HStack {
                    Text(loopTitle)
                        .font(.subheadline)
                        .accessibilityHidden(true)
                    Spacer()
                    Toggle(loopTitle, isOn: Binding(
                        get: { item.pingPongLoop },
                        set: { enabled in manager.updateMediaItem(id: item.id) { $0.pingPongLoop = enabled } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .frame(height: 24)
                .help(l10n("terminal_saver.ping_pong_loop_tooltip"))
            }

            HStack {
                HStack(spacing: 6) {
                    Text(l10n("terminal_saver.remove_background"))
                        .font(.subheadline)
                    InfoTooltip(text: l10n("terminal_saver.remove_background_tooltip"))
                }
                Spacer()
                if manager.processingCutoutMediaIDs.contains(item.id) {
                    ProgressView()
                        .controlSize(.mini)
                }
                Toggle("", isOn: Binding(
                    get: { item.removeBackground },
                    set: { val in manager.updateMediaItem(id: item.id) { $0.removeBackground = val } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .frame(height: 24)
            Spacer(minLength: 0)
        }
    }

    private func builtInSceneInspector(_ scene: TerminalSaverBuiltInScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(sceneTitle(scene))
                    .font(.subheadline.weight(.semibold))
            }

            Divider()

            if scene.supportsRenderStyle {
                renderStylePicker(selection: sceneSetting(scene, \.style), includesOriginal: true)
            }
            colorPresetPicker(selection: sceneSetting(scene, \.colorPreset))
            playbackSpeedSlider(speed: sceneSetting(scene, \.playbackSpeed))
            Spacer(minLength: 0)
        }
    }

    private func syncEditingMediaName(for source: TerminalSaverSource) {
        if case .media(let id) = source,
           let item = manager.config.mediaItems.first(where: { $0.id == id }) {
            editingMediaName = item.displayName
        } else {
            editingMediaName = ""
        }
    }

    private func commitMediaRename(for id: UUID) {
        guard let item = manager.config.mediaItems.first(where: { $0.id == id }) else { return }
        let sanitized = TerminalSaverMediaItem.sanitizedDisplayName(editingMediaName)
        editingMediaName = sanitized
        if sanitized != item.displayName {
            manager.renameMedia(id: id, displayName: sanitized)
        }
    }

    private func builtInSceneTile(_ scene: TerminalSaverBuiltInScene, isActive: Bool, isInspected: Bool) -> some View {
        let source = TerminalSaverSource.builtIn(scene)
        return HStack(spacing: 8) {
            Button {
                manager.previewSource(source)
            } label: {
                HStack(spacing: 8) {
                    Text(sceneTitle(scene))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()

            Toggle("", isOn: Binding(
                get: { isActive },
                set: { newValue in
                    if newValue != isActive {
                        manager.toggleSource(source)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isInspected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isInspected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isInspected ? 1.5 : 1)
        )
    }

    private func customMediaTile(_ item: TerminalSaverMediaItem, isActive: Bool, isInspected: Bool) -> some View {
        let source = TerminalSaverSource.media(item.id)
        return HStack(spacing: 8) {
            Button {
                manager.previewSource(source)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.kind == .video ? "film" : "photo")
                        .font(.caption)
                        .foregroundColor(isInspected ? .accentColor : .secondary)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(item.fileExtension.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()

            Toggle("", isOn: Binding(
                get: { isActive },
                set: { newValue in
                    if newValue != isActive {
                        manager.toggleSource(source)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(role: .destructive) {
                manager.deleteMedia(id: item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isInspected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isInspected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isInspected ? 1.5 : 1)
        )
    }

    private func sceneSetting<Value>(
        _ scene: TerminalSaverBuiltInScene,
        _ keyPath: WritableKeyPath<TerminalSaverSceneSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { manager.config[settingsFor: scene][keyPath: keyPath] },
            set: { value in
                if manager.previewedSource != .builtIn(scene) {
                    manager.previewSource(.builtIn(scene))
                }
                manager.updateConfig { $0[settingsFor: scene][keyPath: keyPath] = value }
            }
        )
    }

    private func uniformMenuPicker<T: Hashable>(
        title: String,
        width: CGFloat,
        options: [(label: String, value: T)],
        selection: Binding<T>
    ) -> some View {
        UniformPopUpButton(title: title, options: options, selection: selection)
            .frame(width: width, height: 24)
    }

    private func uniformSegmentedPill<T: Hashable>(
        width: CGFloat,
        options: [(label: String, value: T)],
        selection: Binding<T>
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection.wrappedValue == option.value
                Button {
                    selection.wrappedValue = option.value
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
        }
        .padding(2)
        .frame(width: width, height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    private func renderStylePicker(selection: Binding<ASCIIRenderStyle?>, includesOriginal: Bool = false) -> some View {
        var options: [(label: String, value: ASCIIRenderStyle?)] = []
        if includesOriginal {
            options.append((l10n("terminal_saver.color_original"), nil))
        }
        options.append(contentsOf: [
            (l10n("terminal_saver.style_filigree"), .filigree),
            (l10n("terminal_saver.style_ultrafine"), .ultraFine),
            (l10n("terminal_saver.style_dense"), .classicDense),
            (l10n("terminal_saver.style_unicode"), .unicodeStrokes)
        ])
        return HStack {
            Text(l10n("terminal_saver.render_style"))
                .font(.subheadline)
            Spacer()
            uniformMenuPicker(
                title: l10n("terminal_saver.render_style"),
                width: Self.inspectorControlWidth,
                options: options,
                selection: selection
            )
        }
        .frame(height: 24)
    }

    private func colorPresetPicker(selection: Binding<ASCIIColorPreset>) -> some View {
        HStack {
            Text(l10n("terminal_saver.color_preset"))
                .font(.subheadline)
            Spacer()
            uniformMenuPicker(
                title: l10n("terminal_saver.color_preset"),
                width: Self.inspectorControlWidth,
                options: [
                    (l10n("terminal_saver.color_original"), .original),
                    (l10n("terminal_saver.color_phosphor"), .phosphor),
                    (l10n("terminal_saver.color_amber"), .amber),
                    (l10n("terminal_saver.color_moonlit"), .moonlit),
                    (l10n("terminal_saver.color_bloodmoon"), .bloodMoon)
                ],
                selection: selection
            )
        }
        .frame(height: 24)
    }

    private func playbackSpeedSlider(speed: Binding<Double>) -> some View {
        HStack {
            Text(l10n("terminal_saver.playback_speed"))
                .font(.subheadline)
            Spacer()
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { TerminalSaverPolicy.speedSliderPosition(for: speed.wrappedValue) },
                    set: { speed.wrappedValue = TerminalSaverPolicy.speedFromSliderPosition($0) }
                ), in: -1.0...1.0)
                .controlSize(.small)
                .accessibilityLabel(l10n("terminal_saver.playback_speed"))
                .accessibilityValue(String(format: "%.1f×", speed.wrappedValue))
                Text(String(format: "%.1f×", speed.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(width: Self.inspectorControlWidth, height: 24)
        }
        .frame(height: 24)
    }

    private func sceneTitle(_ scene: TerminalSaverBuiltInScene) -> String {
        switch scene {
        case .bonfire: return l10n("terminal_saver.scene_bonfire")
        case .bouncingDVD: return l10n("terminal_saver.scene_bouncing_dvd")
        case .starfield: return l10n("terminal_saver.scene_starfield")
        case .windMeadow: return l10n("terminal_saver.scene_wind_meadow")
        case .matrix: return l10n("terminal_saver.scene_matrix")
        case .gameOfLife: return l10n("terminal_saver.scene_game_of_life")
        case .pipes: return l10n("terminal_saver.scene_pipes")
        case .spinningDonut: return l10n("terminal_saver.scene_spinning_donut")
        }
    }

    private func formattedTimeout(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let rem = seconds % 60
        return rem == 0 ? "\(mins)m" : "\(mins)m \(rem)s"
    }

    @ViewBuilder
    private func sectionDisclosureHeader(
        title: String,
        isExpanded: Binding<Bool>,
        collapsedCount: String?,
        fillWidth: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if !isExpanded.wrappedValue, let collapsedCount {
                    Text(collapsedCount)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                if fillWidth {
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }

    private func openMediaPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.gif, .png, .jpeg, .webP, .heic, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            if let importedID = manager.importMedia(urls: panel.urls) {
                mediaSearchText = ""
                isCustomMediaExpanded = true
                syncEditingMediaName(for: .media(importedID))
                scrollToMediaID = importedID
            }
        }
    }
}

private struct TerminalASCIIPreviewView: NSViewRepresentable {
    let model: TerminalSaverPreviewModel

    func makeNSView(context: Context) -> TerminalASCIIPreviewNSView {
        let view = TerminalASCIIPreviewNSView()
        view.asciiFrame = model.frame
        model.onFrameChanged = { [weak view] frame in
            view?.asciiFrame = frame
        }
        return view
    }

    func updateNSView(_ nsView: TerminalASCIIPreviewNSView, context: Context) {
        model.onFrameChanged = { [weak nsView] frame in
            nsView?.asciiFrame = frame
        }
        nsView.asciiFrame = model.frame
    }
}

private final class TerminalASCIIPreviewNSView: NSView {
    var asciiFrame: ASCIIFrame = ASCIIFrame(columns: 0, rows: 0) {
        didSet {
            if oldValue != asciiFrame {
                needsDisplay = true
            }
        }
    }

    private static let bgColor = NSColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1.0)
    private static let charWidthRatio: CGFloat = {
        let sample = NSAttributedString(
            string: "M",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10.0, weight: .regular)]
        )
        return max(0.45, sample.size().width / 10.0)
    }()

    private var cachedNSFont: NSFont?
    private var cachedCTFont: CTFont?
    private var cachedFontSize: CGFloat = 0
    private var cachedCellWidth: CGFloat = 0
    private var cachedAscent: CGFloat = 0
    private var cachedGlyphs: [Character: CGGlyph] = [:]

    override var isOpaque: Bool { true }
    override var isFlipped: Bool { true }

    private func ctFontAndMetrics(for fontSize: CGFloat) -> (nsFont: NSFont, ctFont: CTFont, cellWidth: CGFloat, ascent: CGFloat) {
        if let cachedNSFont, let cachedCTFont, abs(cachedFontSize - fontSize) <= 0.1 {
            return (cachedNSFont, cachedCTFont, cachedCellWidth, cachedAscent)
        }
        let nsFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let ctFont = nsFont as CTFont
        let ascent = CTFontGetAscent(ctFont)
        var mChar: UniChar = 0x4D
        var mGlyph: CGGlyph = 0
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(ctFont, &mChar, &mGlyph, 1) {
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &mGlyph, &advance, 1)
        }
        let cellWidth = max(fontSize * 0.45, advance.width > 0 ? advance.width : fontSize * Self.charWidthRatio)

        cachedNSFont = nsFont
        cachedCTFont = ctFont
        cachedFontSize = fontSize
        cachedCellWidth = cellWidth
        cachedAscent = ascent
        cachedGlyphs.removeAll(keepingCapacity: true)
        return (nsFont, ctFont, cellWidth, ascent)
    }

    private func glyph(for character: Character, font: CTFont) -> CGGlyph {
        if let cached = cachedGlyphs[character] {
            return cached
        }
        var result: CGGlyph = 0
        let utf16 = Array(character.utf16)
        if utf16.count == 1 {
            var codeUnit = utf16[0]
            var glyph: CGGlyph = 0
            if CTFontGetGlyphsForCharacters(font, &codeUnit, &glyph, 1) {
                result = glyph
            }
        }
        cachedGlyphs[character] = result
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.bgColor.setFill()
        dirtyRect.fill()

        guard asciiFrame.columns > 0, asciiFrame.rows > 0 else { return }
        let insetBounds = bounds.insetBy(dx: 8, dy: 6)
        guard insetBounds.width > 10, insetBounds.height > 10 else { return }

        let lineHeightFactor: CGFloat = 1.12
        let maxFontForHeight = insetBounds.height / (CGFloat(asciiFrame.rows) * lineHeightFactor)
        let maxFontForWidth = insetBounds.width / (CGFloat(asciiFrame.columns) * Self.charWidthRatio)
        let fontSize = max(5.5, min(maxFontForHeight, maxFontForWidth))
        let lineHeight = fontSize * lineHeightFactor

        let metrics = ctFontAndMetrics(for: fontSize)
        let cellWidth = metrics.cellWidth
        let drawnWidth = CGFloat(asciiFrame.columns) * cellWidth
        let drawnHeight = CGFloat(asciiFrame.rows) * lineHeight
        let drawOriginX = insetBounds.minX + max(0, (insetBounds.width - drawnWidth) / 2.0)
        let drawOriginY = insetBounds.minY + max(0, (insetBounds.height - drawnHeight) / 2.0)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Unflip into standard bottom-up Quartz coordinates so CTFontDrawGlyphs renders upright.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity

        var runGlyphs: [CGGlyph] = []
        var runPositions: [CGPoint] = []
        runGlyphs.reserveCapacity(asciiFrame.columns)
        runPositions.reserveCapacity(asciiFrame.columns)

        for y in 0..<asciiFrame.rows {
            let baselineY = bounds.height - (drawOriginY + CGFloat(y) * lineHeight + metrics.ascent)
            let rowStart = y * asciiFrame.columns
            var x = 0
            while x < asciiFrame.columns {
                let first = asciiFrame.cells[rowStart + x]
                if first.isBlank {
                    x += 1
                    continue
                }
                let r = first.red
                let g = first.green
                let b = first.blue
                let color = NSColor(
                    red: CGFloat(r) / 255.0,
                    green: CGFloat(g) / 255.0,
                    blue: CGFloat(b) / 255.0,
                    alpha: 1.0
                )

                runGlyphs.removeAll(keepingCapacity: true)
                runPositions.removeAll(keepingCapacity: true)

                var nextX = x
                while nextX < asciiFrame.columns {
                    let cell = asciiFrame.cells[rowStart + nextX]
                    guard !cell.isBlank, cell.red == r, cell.green == g, cell.blue == b else {
                        break
                    }
                    let posX = drawOriginX + CGFloat(nextX) * cellWidth
                    let glyphID = glyph(for: cell.character, font: metrics.ctFont)
                    if glyphID != 0 {
                        runGlyphs.append(glyphID)
                        runPositions.append(CGPoint(x: posX, y: baselineY))
                    } else {
                        let attr = NSAttributedString(
                            string: String(cell.character),
                            attributes: [.font: metrics.nsFont, .foregroundColor: color]
                        )
                        let line = CTLineCreateWithAttributedString(attr)
                        ctx.textPosition = CGPoint(x: posX, y: baselineY)
                        CTLineDraw(line, ctx)
                    }
                    nextX += 1
                }

                if !runGlyphs.isEmpty {
                    ctx.setFillColor(color.cgColor)
                    CTFontDrawGlyphs(metrics.ctFont, runGlyphs, runPositions, runGlyphs.count, ctx)
                }
                x = nextX
            }
        }
    }
}


private final class TerminalSaverKeyCaptureController: ObservableObject {
    enum Target: Equatable {
        case previous
        case next
    }

    @Published private(set) var recordingTarget: Target?
    private var monitor: Any?

    deinit {
        stop()
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if recordingTarget != nil {
            recordingTarget = nil
        }
    }

    func toggle(_ target: Target, onCapture: @escaping (Target, TerminalSaverKey) -> Void) {
        if recordingTarget == target {
            stop()
            return
        }
        stop()
        recordingTarget = target
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let activeTarget = self.recordingTarget else { return event }
            if event.keyCode == 53 {
                self.stop()
                return nil
            }
            if let mapped = Self.mapEvent(event) {
                self.stop()
                onCapture(activeTarget, mapped)
                return nil
            }
            NSSound.beep()
            return nil
        }
    }

    private static func mapEvent(_ event: NSEvent) -> TerminalSaverKey? {
        let disallowedMods: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(disallowedMods).isEmpty {
            return nil
        }
        switch event.keyCode {
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 126: return .upArrow
        case 125: return .downArrow
        case 116: return .pageUp
        case 121: return .pageDown
        case 48: return event.modifierFlags.contains(.shift) ? .shiftTab : .tab
        case 49: return .space
        case 36, 76, 51, 117: return nil
        default:
            let source = event.charactersIgnoringModifiers ?? event.characters ?? ""
            let scalars = Array(source.unicodeScalars)
            guard scalars.count == 1, let scalar = scalars.first,
                  scalar.value >= 0x21, scalar.value <= 0x7E else {
                return nil
            }
            return .character(String(scalar).lowercased())
        }
    }
}

private struct UniformPopUpButton<T: Hashable>: NSViewRepresentable {
    let title: String
    let options: [(label: String, value: T)]
    let selection: Binding<T>

    func makeCoordinator() -> Coordinator {
        Coordinator(options: options, selection: selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.controlSize = .regular
        popUp.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        popUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popUp.setAccessibilityLabel(title)
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.selectionDidChange(_:))
        sync(popUp, coordinator: context.coordinator)
        return popUp
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        context.coordinator.options = options
        context.coordinator.selection = selection
        nsView.setAccessibilityLabel(title)
        sync(nsView, coordinator: context.coordinator)
    }

    private func sync(_ popUp: NSPopUpButton, coordinator: Coordinator) {
        let labels = options.map(\.label)
        if popUp.itemTitles != labels {
            popUp.removeAllItems()
            popUp.addItems(withTitles: labels)
        }
        if let selectedIndex = options.firstIndex(where: { $0.value == selection.wrappedValue }),
           popUp.indexOfSelectedItem != selectedIndex {
            popUp.selectItem(at: selectedIndex)
        }
    }

    final class Coordinator: NSObject {
        var options: [(label: String, value: T)]
        var selection: Binding<T>

        init(options: [(label: String, value: T)], selection: Binding<T>) {
            self.options = options
            self.selection = selection
        }

        @objc func selectionDidChange(_ sender: NSPopUpButton) {
            let idx = sender.indexOfSelectedItem
            guard idx >= 0, idx < options.count else { return }
            selection.wrappedValue = options[idx].value
        }
    }
}
