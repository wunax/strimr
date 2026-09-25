import SwiftUI

struct PlayerSettingsOption: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    var isSelected = false
    var systemImage: String?
    let action: () -> Void
}

struct PlayerSettingsOptionsView: View {
    let title: LocalizedStringKey
    let options: [PlayerSettingsOption]
    let onClose: () -> Void
    @FocusState private var focusedOption: String?

    private var displayedOptions: [PlayerSettingsOption] {
        options + [PlayerSettingsOption(
            id: "close",
            title: String(localized: "common.actions.done"),
            systemImage: "xmark",
            action: onClose,
        )]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.title2.bold())
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(displayedOptions) { option in
                            Button(action: option.action) {
                                HStack(spacing: 16) {
                                    Image(systemName: option
                                        .isSelected ? "checkmark.circle.fill" : (option.systemImage ?? "circle"))
                                        .foregroundStyle(option.isSelected ? Color.brandPrimary : .white.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(option.title).font(.headline)
                                        if let subtitle = option.subtitle {
                                            Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.white)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color.white.opacity(focusedOption == option.id ? 0.18 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 14),
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(focusedOption == option.id ? Color.white : .clear, lineWidth: 3)
                                }
                            }
                            .buttonStyle(PlayerPanelButtonStyle())
                            .focused($focusedOption, equals: option.id)
                            .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                            .id(option.id)
                        }
                    }
                    .padding(4)
                }
                .onAppear {
                    let initialID = options.first(where: \.isSelected)?.id ?? displayedOptions.first?.id
                    if let initialID {
                        proxy.scrollTo(initialID, anchor: .center)
                        DispatchQueue.main.async { focusedOption = initialID }
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
