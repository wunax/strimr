import SwiftUI

extension View {
    /// Asks for a playlist name, prefilled with `initialName`; an empty name cannot be submitted.
    func playlistNamePrompt(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        confirmTitle: LocalizedStringKey,
        initialName: String = "",
        onSubmit: @escaping (String) -> Void,
    ) -> some View {
        modifier(PlaylistNamePrompt(
            isPresented: isPresented,
            title: title,
            confirmTitle: confirmTitle,
            initialName: initialName,
            onSubmit: onSubmit,
        ))
    }

    func playlistDeleteConfirmation(
        isPresented: Binding<Bool>,
        playlistTitle: String,
        onDelete: @escaping () -> Void,
    ) -> some View {
        alert(
            Text("playlist.delete.confirm.title \(playlistTitle)"),
            isPresented: isPresented,
        ) {
            Button("common.actions.cancel", role: .cancel) {}
            Button("common.actions.delete", role: .destructive, action: onDelete)
        } message: {
            Text("playlist.delete.confirm.message")
        }
    }

    func playlistActionFailureAlert(_ failure: Binding<PlaylistActionFailure?>) -> some View {
        alert(item: failure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("common.actions.done")),
            )
        }
    }
}

private struct PlaylistNamePrompt: ViewModifier {
    @Binding var isPresented: Bool
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let initialName: String
    let onSubmit: (String) -> Void

    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("playlist.name.placeholder", text: $name)
                Button("common.actions.cancel", role: .cancel) {}
                Button(confirmTitle) { onSubmit(trimmedName) }
                    .disabled(trimmedName.isEmpty)
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    name = initialName
                }
            }
    }
}
