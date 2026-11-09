import SwiftUI

/// Left and right change the focused setting in place, so the subtitles beside the panel update without a submenu.
struct PlayerSubtitleAppearanceView: View {
    /// Width the settings panel covers on the trailing side of the screen.
    static let coveredWidth: CGFloat = 780

    let availability: SubtitleAppearanceAvailability

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedRow: String?

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        let viewModel = viewModel

        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("player.settings.subtitles")
                    .foregroundStyle(.textTertiary)
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.textTertiary)
                    .accessibilityHidden(true)
                Text("player.settings.subtitles.appearance")
                    .layoutPriority(1)
            }
            .font(.sectionTitle)
            .foregroundStyle(.textPrimary)
            .lineLimit(1)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if !availability.allowsTextStyling {
                        Text("settings.playback.subtitles.footer")
                            .font(.cardMetadata)
                            .foregroundStyle(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }

                    valueRow(
                        "settings.playback.subtitleFontSize",
                        selection: viewModel.subtitleFontSizeBinding,
                        options: viewModel.subtitleFontSizeOptions,
                        isEnabled: availability.allowsTextStyling,
                    ) { Text("settings.playback.fontSize \($0)") }

                    valueRow(
                        "settings.playback.subtitles.color",
                        selection: viewModel.subtitleTextColorBinding,
                        options: viewModel.subtitleTextColorOptions,
                        isEnabled: availability.allowsTextStyling,
                    ) { Text($0.localizedName) }

                    valueRow(
                        "settings.playback.subtitles.weight",
                        selection: viewModel.subtitleFontWeightBinding,
                        options: viewModel.subtitleFontWeightOptions,
                        isEnabled: availability.allowsTextStyling,
                    ) { Text($0.localizedName) }

                    valueRow(
                        "settings.playback.subtitles.background",
                        selection: viewModel.subtitleBackgroundStrengthBinding,
                        options: viewModel.subtitleBackgroundStrengthOptions,
                        isEnabled: availability.allowsTextStyling,
                    ) { Text($0.localizedName) }

                    valueRow(
                        "settings.playback.subtitles.edge",
                        selection: viewModel.subtitleEdgeStyleBinding,
                        options: viewModel.subtitleEdgeStyleOptions,
                        isEnabled: availability.allowsTextStyling,
                    ) { Text($0.localizedName) }

                    valueRow(
                        "settings.playback.subtitles.position",
                        selection: viewModel.subtitleVerticalPositionBinding,
                        options: viewModel.subtitleVerticalPositionOptions,
                        isEnabled: availability.allowsTextStyling,
                    ) { Text($0.localizedName) }

                    if viewModel.showsSubtitleBottomMargin {
                        valueRow(
                            "settings.playback.subtitles.bottomMargin",
                            selection: viewModel.subtitleBottomMarginBinding,
                            options: viewModel.subtitleBottomMarginOptions,
                        ) { Text($0.localizedName) }
                    }

                    valueRow(
                        "settings.playback.subtitles.brightness",
                        selection: viewModel.subtitleBrightnessBinding,
                        options: viewModel.subtitleBrightnessOptions,
                    ) { Text($0.localizedName) }

                    resetRow(viewModel)
                }
                // Room for the focused row's scale inside the scroll view's clipping.
                .padding(8)
            }
        }
        .padding(.vertical, 36)
        .onAppear {
            let firstRow = availability.allowsTextStyling
                ? "settings.playback.subtitleFontSize"
                : "settings.playback.subtitles.brightness"
            DispatchQueue.main.async { focusedRow = firstRow }
        }
    }

    private func valueRow<Value: Hashable>(
        _ titleKey: String,
        selection: Binding<Value>,
        options: [Value],
        isEnabled: Bool = true,
        @ViewBuilder value: @escaping (Value) -> Text,
    ) -> some View {
        let isFocused = focusedRow == titleKey
        let foreground: Color = isFocused ? .black : .white

        return Button {
            step(selection, options: options, by: 1, wraps: true)
        } label: {
            HStack(spacing: 16) {
                Text(LocalizedStringKey(titleKey))
                    .font(.bodyText.weight(.semibold))
                Spacer(minLength: 16)
                Image(systemName: "chevron.left")
                    .foregroundStyle(foreground.opacity(isFocused ? 0.5 : 0))
                    .accessibilityHidden(true)
                value(selection.wrappedValue)
                    .font(.bodyText)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .foregroundStyle(foreground.opacity(isFocused ? 0.5 : 0))
                    .accessibilityHidden(true)
            }
            .rowStyle(isFocused: isFocused, foreground: foreground, reduceMotion: reduceMotion)
        }
        .buttonStyle(PlayerAppearanceRowButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .focused($focusedRow, equals: titleKey)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(selection, options: options, by: -1, wraps: false)
            case .right: step(selection, options: options, by: 1, wraps: false)
            default: break
            }
        }
    }

    private func resetRow(_ viewModel: SettingsViewModel) -> some View {
        let id = "reset"
        let isFocused = focusedRow == id
        let foreground: Color = isFocused ? .black : .white

        return Button {
            viewModel.resetSubtitleAppearance()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "arrow.counterclockwise")
                Text("settings.playback.subtitles.reset")
                    .font(.bodyText.weight(.semibold))
                Spacer(minLength: 0)
            }
            .rowStyle(isFocused: isFocused, foreground: foreground, reduceMotion: reduceMotion)
        }
        .buttonStyle(PlayerAppearanceRowButtonStyle())
        .focused($focusedRow, equals: id)
    }

    private func step<Value: Hashable>(
        _ selection: Binding<Value>,
        options: [Value],
        by delta: Int,
        wraps: Bool,
    ) {
        guard let index = options.firstIndex(of: selection.wrappedValue) else { return }
        let next = index + delta
        if options.indices.contains(next) {
            selection.wrappedValue = options[next]
        } else if wraps, let first = options.first {
            selection.wrappedValue = first
        }
    }
}

private extension View {
    func rowStyle(isFocused: Bool, foreground: Color, reduceMotion: Bool) -> some View {
        foregroundStyle(foreground)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isFocused ? Color.white : .surfaceSubtle,
                in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
            )
            .animation(Motion.focus, value: isFocused)
            .scaleEffect(isFocused && !reduceMotion ? 1.02 : 1)
            .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
    }
}

/// A custom style avoids tvOS's additional native button focus background/scale.
private struct PlayerAppearanceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
