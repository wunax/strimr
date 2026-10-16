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
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("settings.playback.externalPlayer.custom.name", text: $model.name)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            "settings.playback.externalPlayer.custom.template",
                            text: $model.template,
                            prompt: Text(verbatim: "myplayer://play?url={url}"),
                        )
                        .autocorrectionDisabled()

                        if let error = model.templateError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("settings.playback.externalPlayer.custom.title")
                } footer: {
                    Text("settings.playback.externalPlayer.custom.help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("common.actions.cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("common.actions.done") {
                    onSave(model.player)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
            }
            .padding()
        }
        .frame(width: 480)
    }
}
