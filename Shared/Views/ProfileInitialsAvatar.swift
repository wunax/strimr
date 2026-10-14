import SwiftUI

/// Avatar of a local profile: its initials on a gradient.
struct ProfileInitialsAvatar: View {
    let initials: String
    var tint: Color = .brandPrimary

    var body: some View {
        LinearGradient(
            colors: [tint, tint.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay {
            GeometryReader { geometry in
                Text(initials)
                    .font(.system(size: geometry.size.width * 0.36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
