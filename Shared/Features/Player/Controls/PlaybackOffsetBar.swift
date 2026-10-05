import SwiftUI

extension PlaybackOffsetKind {
    var title: String {
        switch self {
        case .audio: String(localized: "player.settings.sync.audio")
        case .subtitles: String(localized: "player.settings.sync.subtitles")
        }
    }

    var systemImage: String {
        switch self {
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        }
    }

    /// The value shown next to the menu entry: "Off" at zero.
    func menuValue(milliseconds: Int) -> String {
        milliseconds == 0
            ? String(localized: "player.settings.sync.off")
            : PlaybackOffsetFormatter.string(milliseconds: milliseconds)
    }

    func directionLabel(milliseconds: Int) -> String? {
        switch (self, milliseconds.signum()) {
        case (.audio, 1): String(localized: "player.settings.sync.audio.later")
        case (.audio, -1): String(localized: "player.settings.sync.audio.earlier")
        case (.subtitles, 1): String(localized: "player.settings.sync.subtitles.later")
        case (.subtitles, -1): String(localized: "player.settings.sync.subtitles.earlier")
        default: nil
        }
    }
}

extension PlaybackOffsetAvailability {
    var message: String? {
        switch self {
        case .available, .noSubtitleTrack: nil
        case .unavailableForStream: String(localized: "player.settings.sync.unavailable")
        case .burnedInSubtitles: String(localized: "player.settings.sync.subtitles.burnedIn")
        }
    }
}

/// An entry of the player menu that opens the sync bar.
struct PlaybackOffsetMenuItem: Hashable, Identifiable {
    let kind: PlaybackOffsetKind
    let milliseconds: Int
    let availability: PlaybackOffsetAvailability

    var id: PlaybackOffsetKind {
        kind
    }

    var value: String {
        kind.menuValue(milliseconds: milliseconds)
    }

    var isActive: Bool {
        milliseconds != 0
    }
}

extension PlayerController {
    func offsetMenuItem(_ kind: PlaybackOffsetKind, burnsSubtitles: Bool) -> PlaybackOffsetMenuItem {
        switch kind {
        case .audio:
            PlaybackOffsetMenuItem(
                kind: .audio,
                milliseconds: audioDelayMilliseconds,
                availability: audioDelayAvailability,
            )
        case .subtitles:
            PlaybackOffsetMenuItem(
                kind: .subtitles,
                milliseconds: subtitleDelayMilliseconds,
                availability: subtitleDelayAvailability(burnsSubtitles: burnsSubtitles),
            )
        }
    }

    func offsetMenuItems(burnsSubtitles: Bool) -> [PlaybackOffsetMenuItem] {
        [
            offsetMenuItem(.audio, burnsSubtitles: burnsSubtitles),
            offsetMenuItem(.subtitles, burnsSubtitles: burnsSubtitles),
        ]
    }
}

/// A dot on the control that leads to subtitle sync, while a subtitle offset is active.
struct PlaybackOffsetIndicator: View {
    var body: some View {
        Circle()
            .fill(Color.brandPrimary)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The sync bar wired to the player: audio writes the device-wide preference, subtitles stay in the session.
struct PlayerOffsetBar: View {
    @Environment(SettingsManager.self) private var settingsManager
    let controller: PlayerController
    let kind: PlaybackOffsetKind
    let burnsSubtitles: Bool
    let onDone: () -> Void

    var body: some View {
        PlaybackOffsetBar(
            kind: kind,
            milliseconds: milliseconds,
            isApplying: kind == .audio && controller.isApplyingAudioDelay,
            availability: availability,
            onStep: step(direction:coarse:),
            onReset: { setMilliseconds(0) },
            onDone: onDone,
        )
    }

    /// Top of the screen so the bar does not cover subtitles, unless subtitles are drawn at the top.
    static func alignment(for subtitlePosition: SubtitleVerticalPosition) -> Alignment {
        subtitlePosition == .top ? .bottom : .top
    }

    private var milliseconds: Int {
        switch kind {
        case .audio: controller.audioDelayMilliseconds
        case .subtitles: controller.subtitleDelayMilliseconds
        }
    }

    private var availability: PlaybackOffsetAvailability {
        switch kind {
        case .audio: controller.audioDelayAvailability
        case .subtitles: controller.subtitleDelayAvailability(burnsSubtitles: burnsSubtitles)
        }
    }

    private func step(direction: Int, coarse: Bool) {
        let stepped = kind.range.stepped(PlaybackOffset(milliseconds: milliseconds), by: direction, coarse: coarse)
        setMilliseconds(stepped.milliseconds)
    }

    private func setMilliseconds(_ value: Int) {
        switch kind {
        case .audio:
            controller.setAudioDelay(milliseconds: value)
            settingsManager.setAudioDelayMilliseconds(controller.audioDelayMilliseconds)
        case .subtitles:
            controller.setSubtitleDelay(milliseconds: value)
        }
    }
}

struct PlaybackOffsetBar: View {
    let kind: PlaybackOffsetKind
    let milliseconds: Int
    let isApplying: Bool
    let availability: PlaybackOffsetAvailability
    let onStep: (_ direction: Int, _ coarse: Bool) -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1),
            )
        #if !os(tvOS)
            // On tvOS the dark scheme already makes text white, and a forced white would stay white on
            // the light focused button background.
            .foregroundStyle(.white)
        #endif
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
            stackedRows
                .fixedSize()
        #else
            ViewThatFits(in: .horizontal) {
                singleRow
                stackedRows
            }
        #endif
    }

    private var singleRow: some View {
        HStack(spacing: spacing) {
            header
            stepper
            resetButton
            doneButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stackedRows: some View {
        VStack(spacing: rowSpacing) {
            HStack(spacing: spacing) {
                header
                Spacer(minLength: 0)
                resetButton
                doneButton
            }
            #if os(tvOS)
            // Up/down must reach the other row even when no control sits right above or below,
            // e.g. when the increase buttons are disabled at the maximum.
            .focusSection()
            #endif
            stepper
            #if os(tvOS)
                .focusSection()
            #endif
        }
    }

    private var header: some View {
        Label(kind.title, systemImage: kind.systemImage)
            .font(headerFont)
            .lineLimit(1)
    }

    private var stepper: some View {
        PlaybackOffsetStepper(
            kind: kind,
            milliseconds: milliseconds,
            caption: caption,
            isEnabled: availability.isAvailable,
            prefersInitialFocus: true,
            onStep: onStep,
        )
    }

    private var resetButton: some View {
        PlaybackOffsetResetButton(isEnabled: availability.isAvailable && milliseconds != 0, action: onReset)
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("common.actions.done")
                .foregroundStyle(.foreground)
        }
        .fontWeight(.semibold)
        #if !os(tvOS)
            .buttonStyle(.borderedProminent)
        #endif
    }

    private var caption: String? {
        if let message = availability.message {
            return message
        }
        if isApplying {
            return String(localized: "player.settings.sync.applying")
        }
        return kind.directionLabel(milliseconds: milliseconds)
    }

    private var spacing: CGFloat {
        #if os(tvOS)
            32
        #else
            14
        #endif
    }

    private var rowSpacing: CGFloat {
        #if os(tvOS)
            20
        #else
            10
        #endif
    }

    private var headerFont: Font {
        #if os(tvOS)
            .callout.weight(.semibold)
        #else
            .headline
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            36
        #else
            16
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            24
        #else
            10
        #endif
    }

    private var cornerRadius: CGFloat {
        #if os(tvOS)
            28
        #else
            18
        #endif
    }
}

/// `[−coarse] [−fine]  value  [+fine] [+coarse]`, shared by the player bar and the settings row, which
/// also puts the reset button at the end.
struct PlaybackOffsetStepper: View {
    let kind: PlaybackOffsetKind
    let milliseconds: Int
    var caption: String?
    var isEnabled = true
    var prefersInitialFocus = false
    /// tvOS settings pages track focus per control.
    var settingsFocusID: String?
    let onStep: (_ direction: Int, _ coarse: Bool) -> Void
    var onReset: (() -> Void)?

    #if os(tvOS)
        @FocusState private var focusedControl: PlaybackOffsetControl?
    #endif

    var body: some View {
        HStack(spacing: spacing) {
            stepButton(.coarseDecrease)
            stepButton(.fineDecrease)
            valueView
            stepButton(.fineIncrease)
            stepButton(.coarseIncrease)
            if let onReset {
                resetButton(action: onReset)
            }
        }
        #if os(tvOS)
        .onAppear {
            guard prefersInitialFocus else { return }
            DispatchQueue.main.async { focusedControl = .fineIncrease }
        }
        #endif
    }

    private var offset: PlaybackOffset {
        PlaybackOffset(milliseconds: milliseconds)
    }

    private var formattedValue: String {
        PlaybackOffsetFormatter.string(milliseconds: milliseconds)
    }

    private var valueView: some View {
        VStack(spacing: 2) {
            Text(formattedValue)
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(milliseconds == 0 ? .secondary : .primary)
                .lineLimit(1)
                .fixedSize()
            // Kept in the layout when empty so the buttons do not jump.
            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: valueWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(caption.map { "\(formattedValue), \($0)" } ?? formattedValue)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onStep(1, false)
            case .decrement: onStep(-1, false)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ control: PlaybackOffsetControl) -> some View {
        let stepMilliseconds = control.direction * kind.range.stepMilliseconds(coarse: control.isCoarse)
        let enabled = isEnabled && kind.range.canStep(offset, direction: control.direction)
        return PlaybackOffsetStepButton(
            title: PlaybackOffsetFormatter.stepLabel(milliseconds: stepMilliseconds, kind: kind),
            accessibilityLabel: kind.directionLabel(milliseconds: stepMilliseconds) ?? "",
            accessibilityValue: PlaybackOffsetFormatter.string(milliseconds: stepMilliseconds),
            isEnabled: enabled,
            action: { onStep(control.direction, control.isCoarse) },
        )
        #if os(tvOS)
        .modifier(PlaybackOffsetFocus(
            control: control,
            focusedControl: $focusedControl,
            settingsFocusID: settingsFocusID,
        ))
        #endif
    }

    private func resetButton(action: @escaping () -> Void) -> some View {
        PlaybackOffsetResetButton(isEnabled: isEnabled && milliseconds != 0, action: action)
        #if os(tvOS)
            .modifier(PlaybackOffsetFocus(
                control: .reset,
                focusedControl: $focusedControl,
                settingsFocusID: settingsFocusID,
            ))
        #endif
    }

    private var spacing: CGFloat {
        #if os(tvOS)
            20
        #else
            8
        #endif
    }

    private var valueWidth: CGFloat {
        #if os(tvOS)
            200
        #else
            96
        #endif
    }

    private var valueFont: Font {
        #if os(tvOS)
            .title3.weight(.semibold)
        #else
            .headline
        #endif
    }
}

struct PlaybackOffsetResetButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
                .foregroundStyle(.foreground)
            #if !os(tvOS)
                .frame(width: 36, height: 36)
            #endif
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(Text("player.settings.sync.reset"))
    }
}

enum PlaybackOffsetControl: String, Hashable {
    case coarseDecrease
    case fineDecrease
    case fineIncrease
    case coarseIncrease
    case reset

    var direction: Int {
        switch self {
        case .coarseDecrease, .fineDecrease: -1
        case .fineIncrease, .coarseIncrease: 1
        case .reset: 0
        }
    }

    var isCoarse: Bool {
        self == .coarseDecrease || self == .coarseIncrease
    }
}

#if os(tvOS)
    /// On a settings page the page owns focus; in the player the stepper does.
    private struct PlaybackOffsetFocus: ViewModifier {
        let control: PlaybackOffsetControl
        let focusedControl: FocusState<PlaybackOffsetControl?>.Binding
        let settingsFocusID: String?

        func body(content: Content) -> some View {
            if let settingsFocusID {
                content.settingsFocus(
                    "\(settingsFocusID).\(control.rawValue)",
                    exitsLeft: control == .coarseDecrease,
                )
            } else {
                content.focused(focusedControl, equals: control)
            }
        }
    }

    /// Steps once on press, then repeats while the remote's select button is held, faster and faster.
    private struct PlaybackOffsetStepButton: View {
        let title: String
        let accessibilityLabel: String
        let accessibilityValue: String
        let isEnabled: Bool
        let action: () -> Void

        @State private var repeatTask: Task<Void, Never>?

        var body: some View {
            // Stepping is driven by the press itself, so the release action stays empty.
            Button {} label: {
                Text(title)
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 72)
            }
            .buttonStyle(PlaybackOffsetRepeatButtonStyle { pressed in
                if pressed {
                    startIfNeeded()
                } else {
                    stop()
                }
            })
            .disabled(!isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    stop()
                }
            }
            .onDisappear(perform: stop)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAction {
                if isEnabled {
                    action()
                }
            }
        }

        private func startIfNeeded() {
            guard repeatTask == nil, isEnabled else { return }
            action()
            repeatTask = Task { @MainActor in
                var index = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: PlaybackOffsetRepeat.interval(beforeRepeat: index))
                    guard !Task.isCancelled else { return }
                    action()
                    index += 1
                }
            }
        }

        private func stop() {
            repeatTask?.cancel()
            repeatTask = nil
        }
    }

    /// The native style hides `isPressed`, so this one redraws the tvOS focus look itself.
    private struct PlaybackOffsetRepeatButtonStyle: ButtonStyle {
        let onPressChanged: (Bool) -> Void

        func makeBody(configuration: Configuration) -> some View {
            PlaybackOffsetRepeatButtonBody(configuration: configuration, onPressChanged: onPressChanged)
        }
    }

    private struct PlaybackOffsetRepeatButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let onPressChanged: (Bool) -> Void

        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.primary)
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(
                    isFocused ? Color.white : Color.primary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                )
                .scaleEffect(isFocused && !configuration.isPressed ? 1.1 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 14, y: 8)
                .opacity(isEnabled ? 1 : 0.35)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    onPressChanged(pressed)
                }
        }
    }
#else
    /// Steps once on press, then repeats while held, faster and faster.
    private struct PlaybackOffsetStepButton: View {
        let title: String
        let accessibilityLabel: String
        let accessibilityValue: String
        let isEnabled: Bool
        let action: () -> Void

        @State private var repeatTask: Task<Void, Never>?

        var body: some View {
            Text(title)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minWidth: minSize, minHeight: minSize)
                .background(
                    Color.primary.opacity(repeatTask == nil ? 0.12 : 0.28),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                )
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in startIfNeeded() }
                        .onEnded { _ in stop() },
                )
                .onChange(of: isEnabled) { _, enabled in
                    if !enabled {
                        stop()
                    }
                }
                .onDisappear(perform: stop)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    if isEnabled {
                        action()
                    }
                }
        }

        private var minSize: CGFloat {
            #if os(iOS)
                44
            #else
                30
            #endif
        }

        private func startIfNeeded() {
            guard repeatTask == nil, isEnabled else { return }
            action()
            repeatTask = Task { @MainActor in
                var index = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: PlaybackOffsetRepeat.interval(beforeRepeat: index))
                    guard !Task.isCancelled else { return }
                    action()
                    index += 1
                }
            }
        }

        private func stop() {
            repeatTask?.cancel()
            repeatTask = nil
        }
    }
#endif

/// "Audio offset" in Settings > Playback: the same four buttons, without the bar.
struct AudioDelaySettingsRow: View {
    @Environment(SettingsManager.self) private var settingsManager
    var settingsFocusID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.playback.audioDelay")
            PlaybackOffsetStepper(
                kind: .audio,
                milliseconds: settingsManager.playback.audioDelayMilliseconds,
                caption: PlaybackOffsetKind.audio.directionLabel(
                    milliseconds: settingsManager.playback.audioDelayMilliseconds,
                ),
                settingsFocusID: settingsFocusID,
                onStep: { direction, coarse in
                    let current = PlaybackOffset(milliseconds: settingsManager.playback.audioDelayMilliseconds)
                    let stepped = PlaybackOffsetRange.audio.stepped(current, by: direction, coarse: coarse)
                    settingsManager.setAudioDelayMilliseconds(stepped.milliseconds)
                },
                onReset: { settingsManager.setAudioDelayMilliseconds(0) },
            )
        }
    }
}
