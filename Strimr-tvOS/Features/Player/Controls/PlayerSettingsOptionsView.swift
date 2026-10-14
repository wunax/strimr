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
    @FocusState private var focusedOption: String?

    private var initialFocusID: String? {
        initialOptionID ?? options.first(where: \.isSelected)?.id ?? options.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let parentTitle {
                    Text(parentTitle)
                        .foregroundStyle(.white.opacity(0.5))
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .layoutPriority(1)
            }
            .font(.title2.bold())
            .lineLimit(1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(options) { option in
                            if let sectionTitle = option.sectionTitle {
                                Text(sectionTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.6))
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
                                        .foregroundStyle(option.isSelected ? Color.brandPrimary : foreground
                                            .opacity(option.opensSubmenu ? 1 : 0.5))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(option.title).font(.headline)
                                        if let subtitle = option.subtitle {
                                            Text(subtitle)
                                                .font(.caption.weight(option.highlightsSubtitle ? .semibold : .regular))
                                                .foregroundStyle(option.highlightsSubtitle
                                                    ? Color.brandPrimary
                                                    : foreground.opacity(0.65))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if option.opensSubmenu {
                                        Image(systemName: "chevron.right")
                                            .font(.headline)
                                            .foregroundStyle(foreground.opacity(0.5))
                                    }
                                }
                                .foregroundStyle(foreground)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    isFocused ? Color.white : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 14),
                                )
                                .scaleEffect(isFocused ? 1.02 : 1)
                                .animation(.easeOut(duration: 0.15), value: isFocused)
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
