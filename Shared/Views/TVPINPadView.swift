#if os(tvOS)
    import SwiftUI

    /// Four-digit PIN entry on a remote-friendly keypad; `onComplete` fires as soon as the fourth digit is entered.
    struct TVPINPadView<Footer: View>: View {
        let title: LocalizedStringKey
        var message: String?
        let onComplete: (String) -> Void
        let onCancel: () -> Void
        @ViewBuilder var footer: () -> Footer

        @State private var pin = ""
        @FocusState private var focusedDigit: String?

        private let columns = Array(repeating: GridItem(.fixed(128), spacing: 16), count: 3)
        private let keySize = CGSize(width: 64, height: 48)

        var body: some View {
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 32) {
                    if let message {
                        Text(message)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    pinDisplay
                    footer()
                }
                .frame(maxWidth: 560, alignment: .leading)

                VStack(spacing: 36) {
                    keypad
                    Button("common.actions.cancel", role: .cancel, action: onCancel)
                }
                .frame(width: 440)
                .focusSection()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .taskModalTitle(title)
            .onAppear { focusedDigit = "1" }
        }

        private var pinDisplay: some View {
            HStack(spacing: 12) {
                ForEach(0 ..< 4, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 70, height: 70)
                        if index < pin.count {
                            Text("•")
                                .font(.title.bold())
                        }
                    }
                }
            }
        }

        private var keypad: some View {
            LazyVGrid(columns: columns) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) {
                    digitButton($0)
                }
                Color.clear
                    .frame(width: keySize.width, height: keySize.height)
                digitButton("0")
                Button {
                    pin.removeLast()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2.bold())
                        .frame(width: keySize.width)
                        .padding(.vertical, 16)
                }
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.small)
                .disabled(pin.isEmpty)
            }
        }

        private func digitButton(_ digit: String) -> some View {
            Button {
                guard pin.count < 4 else { return }
                pin.append(digit)
                if pin.count == 4 {
                    let entered = pin
                    pin = ""
                    onComplete(entered)
                }
            } label: {
                Text(digit)
                    .font(.title2.bold())
                    .frame(width: keySize.width)
                    .padding(.vertical, 16)
            }
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.small)
            .focused($focusedDigit, equals: digit)
        }
    }

    extension TVPINPadView where Footer == EmptyView {
        init(
            title: LocalizedStringKey,
            message: String? = nil,
            onComplete: @escaping (String) -> Void,
            onCancel: @escaping () -> Void,
        ) {
            self.init(title: title, message: message, onComplete: onComplete, onCancel: onCancel) { EmptyView() }
        }
    }
#endif
