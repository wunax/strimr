import SwiftUI

struct ExternalPlayerOptionsView: View {
    @Environment(SettingsNavigation.self) private var navigation
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsList {
            ForEach(Array(viewModel.externalPlayerOptions.enumerated()), id: \.element) { index, option in
                let isSelected = viewModel.selectedExternalPlayerOption == option
                Button {
                    select(option)
                } label: {
                    HStack {
                        Text(viewModel.title(for: option))
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
                .settingsFocus("option-\(index)", isDefault: isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func select(_ option: ExternalPlayerOption) {
        let didSelect = viewModel.selectExternalPlayer(option)
        navigation.pop()
        guard !didSelect else { return }
        navigation.push("settings.playback.externalPlayer.custom.title") {
            CustomExternalPlayerView(player: nil) { player in
                viewModel.saveCustomExternalPlayer(player)
            }
        }
    }
}

struct CustomExternalPlayerView: View {
    @Environment(SettingsNavigation.self) private var navigation
    @State private var model: CustomExternalPlayerFormModel
    let onSave: (CustomExternalPlayer) -> Void

    init(player: CustomExternalPlayer?, onSave: @escaping (CustomExternalPlayer) -> Void) {
        _model = State(initialValue: CustomExternalPlayerFormModel(player: player))
        self.onSave = onSave
    }

    var body: some View {
        SettingsScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("settings.playback.externalPlayer.custom.name")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("settings.playback.externalPlayer.custom.name", text: $model.name)
                    .settingsFocus("name", isDefault: true)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("settings.playback.externalPlayer.custom.template")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField(
                    "settings.playback.externalPlayer.custom.template",
                    text: $model.template,
                    prompt: Text(verbatim: "myplayer://play?url={url}").foregroundColor(.gray),
                )
                .settingsFocus("template")
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let error = model.templateError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("settings.playback.externalPlayer.custom.help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    onSave(model.player)
                    navigation.pop()
                } label: {
                    Text("common.actions.done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .settingsFocus("save")
                .disabled(!model.canSave)
            }
            .padding(24)
        }
    }
}
