import SwiftUI

struct PlayerSettingsOption: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var highlightsSubtitle = false
    var isSelected = false
    var systemImage: String?
    var isDisabled = false
    var opensSubmenu = false
    var sectionTitle: String?
    let action: () -> Void
}

struct PlayerSettingsOptionsView: View {
    let title: LocalizedStringKey
    let options: [PlayerSettingsOption]
    var initialOptionID: String?
    /// Shown before the title of a submenu, since the remote's Back button returns to it.
    var parentTitle: LocalizedStringKey?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedOption: String?

    private var initialFocusID: String? {
        initialOptionID ?? options.first(where: \.isSelected)?.id ?? options.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let parentTitle {
                    Text(parentTitle)
                        .foregroundStyle(.textTertiary)
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .layoutPriority(1)
            }
            .font(.sectionTitle)
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(options) { option in
                            if let sectionTitle = option.sectionTitle {
                                Text(sectionTitle)
                                    .eyebrowStyle()
                                    .foregroundStyle(.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 24)
                                    .padding(.horizontal, 20)
                            }
                            let isFocused = focusedOption == option.id
                            let foreground: Color = isFocused ? .black : .white
                            Button(action: option.action) {
                                HStack(spacing: 16) {
                                    Image(systemName: option
                                        .isSelected ? "checkmark.circle.fill" : (option.systemImage ?? "circle"))
                                        .foregroundStyle(option.isSelected ? Color.selectionAccent : foreground
                                            .opacity(option.opensSubmenu ? 1 : 0.5))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(option.title).font(.bodyText.weight(.semibold))
                                        if let subtitle = option.subtitle {
                                            Text(subtitle)
                                                .font(.cardMetadata
                                                    .weight(option.highlightsSubtitle ? .semibold : .regular))
                                                .foregroundStyle(option.highlightsSubtitle
                                                    ? Color.selectionAccent
                                                    : foreground.opacity(0.65))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if option.opensSubmenu {
                                        Image(systemName: "chevron.right")
                                            .font(.bodyText.weight(.semibold))
                                            .foregroundStyle(foreground.opacity(0.5))
                                    }
                                }
                                .foregroundStyle(foreground)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    isFocused ? Color.white : .surfaceSubtle,
                                    in: RoundedRectangle(
                                        cornerRadius: LayoutMetrics.cardCornerRadius,
                                        style: .continuous,
                                    ),
                                )
                                .animation(Motion.focus, value: isFocused)
                                .scaleEffect(isFocused && !reduceMotion ? 1.02 : 1)
                                .animation(
                                    Motion.animation(Motion.focusScale, reduceMotion: reduceMotion),
                                    value: isFocused,
                                )
                            }
                            .buttonStyle(PlayerPanelButtonStyle())
                            .disabled(option.isDisabled)
                            .opacity(option.isDisabled ? 0.45 : 1)
                            .focused($focusedOption, equals: option.id)
                            .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                            .id(option.id)
                        }
                    }
                    // Room for the focused row's scale inside the scroll view's clipping.
                    .padding(8)
                }
                .onAppear {
                    if let initialFocusID {
                        proxy.scrollTo(initialFocusID, anchor: .center)
                        DispatchQueue.main.async { focusedOption = initialFocusID }
                    }
                }
            }
        }
        .padding(.vertical, 36)
    }
}

/// A custom style avoids tvOS's additional native button focus background/scale.
private struct PlayerPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
