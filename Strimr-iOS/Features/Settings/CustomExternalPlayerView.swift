import SwiftUI

struct CustomExternalPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CustomExternalPlayerFormModel
    let onSave: (CustomExternalPlayer) -> Void

    init(player: CustomExternalPlayer?, onSave: @escaping (CustomExternalPlayer) -> Void) {
        _model = State(initialValue: CustomExternalPlayerFormModel(player: player))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                TextField("settings.playback.externalPlayer.custom.name", text: $model.name)
                    .autocorrectionDisabled()
            }

            Section {
                TextField(
                    "settings.playback.externalPlayer.custom.template",
                    text: $model.template,
                    prompt: Text(verbatim: "myplayer://play?url={url}"),
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if let error = model.templateError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("settings.playback.externalPlayer.custom.template")
            } footer: {
                Text("settings.playback.externalPlayer.custom.help")
            }
        }
        .navigationTitle("settings.playback.externalPlayer.custom.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.actions.done") {
                    onSave(model.player)
                    dismiss()
                }
                .disabled(!model.canSave)
            }
        }
    }
}
