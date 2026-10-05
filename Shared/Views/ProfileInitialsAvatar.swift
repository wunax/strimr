import SwiftUI

/// Avatar of a local profile: its initials on a gradient.
struct ProfileInitialsAvatar: View {
    let initials: String

    var body: some View {
        LinearGradient(
            colors: [Color.brandPrimary.opacity(0.9), Color.brandPrimary.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay {
            Text(initials)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.3)
                .foregroundStyle(.white)
                .padding(12)
        }
    }
}

/// Four-digit PIN entry used for local profiles and Plex Home users.
struct ProfilePINPrompt: View {
    let title: LocalizedStringKey
    let message: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var pin = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        #if os(tvOS)
            TVPINPadView(title: title, message: message, onComplete: onSubmit, onCancel: onCancel)
        #else
            form
        #endif
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            SecureField("auth.profile.pin.placeholder", text: $pin)
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
                .textContentType(.password)
                .focused($isFocused)
                .onSubmit(submit)
            HStack {
                Button("common.actions.cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("common.actions.continue", action: submit)
                    .disabled(pin.isEmpty)
            }
        }
        .padding()
        .onAppear { isFocused = true }
        .pinDigits($pin)
    }

    private func submit() {
        guard !pin.isEmpty else { return }
        onSubmit(pin)
    }
}

extension View {
    /// Keeps a PIN field to four digits, whatever is typed or pasted.
    func pinDigits(_ pin: Binding<String>) -> some View {
        onChange(of: pin.wrappedValue) { _, newValue in
            let sanitized = String(newValue.filter(\.isNumber).prefix(4))
            if sanitized != newValue {
                pin.wrappedValue = sanitized
            }
        }
    }
}
