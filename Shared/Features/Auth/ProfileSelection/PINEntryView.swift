import SwiftUI

/// Four-digit PIN entry shared by the profile picker and every PIN prompt: dots, then a keypad on iOS and tvOS.
/// macOS has no keypad; the presenting view forwards the keys typed on the keyboard.
struct PINEntryPad<Header: View, Footer: View>: View {
    let title: String
    let message: String
    let pinCount: Int
    /// Bumped by the caller on every rejected PIN, which shakes the dots.
    let rejectedCount: Int
    var isDisabled = false
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        #if os(tvOS)
            HStack(spacing: 160) {
                VStack(spacing: 40) {
                    header()
                    labels
                        .frame(maxWidth: 560)
                    dots
                }

                VStack(spacing: 40) {
                    keypad
                    footer()
                }
                .focusSection()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #elseif os(macOS)
            VStack(spacing: 28) {
                header()
                labels
                dots
                footer()
            }
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
            ScrollView {
                VStack(spacing: 28) {
                    header()
                    labels
                    dots
                    keypad
                    footer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        #endif
    }

    private var labels: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.tileTitle)
                .foregroundStyle(.textPrimary)
            Text(message)
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var dots: some View {
        PINDotsView(count: pinCount)
            .shake(rejectedCount)
    }

    #if !os(macOS)
        private var keypad: some View {
            ProfileKeypad(canDelete: pinCount > 0, onDigit: onDigit, onDelete: onDelete)
                .disabled(isDisabled)
        }
    #endif
}

/// PIN entry in its own presentation. A PIN being defined is typed twice, since the keypad submits on the fourth
/// digit and a typo would otherwise lock the profile.
struct PINPrompt<Footer: View>: View {
    enum Purpose {
        /// Returns whether the PIN is accepted; a rejected one shakes and clears.
        case verify((String) -> Bool)
        case define((String) -> Void)
    }

    let title: String
    let message: String
    let purpose: Purpose
    let onCancel: () -> Void
    @ViewBuilder var footer: () -> Footer

    @State private var pin = ""
    @State private var firstPIN: String?
    @State private var rejectedCount = 0
    @State private var errorMessage: String?
    #if os(macOS)
        @FocusState private var isKeyboardFocused: Bool
    #endif

    var body: some View {
        PINEntryPad(
            title: title,
            message: currentMessage,
            pinCount: pin.count,
            rejectedCount: rejectedCount,
            onDigit: append,
            onDelete: deleteDigit,
        ) {
            Image(systemName: "lock.fill")
                .font(.system(size: lockSize, weight: .semibold))
                .foregroundStyle(.textSecondary)
                .frame(width: lockSize * 2.2, height: lockSize * 2.2)
                .background(.surfaceRaised, in: Circle())
        } footer: {
            VStack(spacing: 16) {
                footer()
                Button("common.actions.cancel", role: .cancel, action: onCancel)
                    .actionButtonStyle(.secondary)
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        .focusable()
        .focusEffectDisabled()
        .focused($isKeyboardFocused)
        .onKeyPress(action: handleKey)
        .onAppear { isKeyboardFocused = true }
        #endif
    }

    private var lockSize: CGFloat {
        #if os(tvOS)
            48
        #else
            28
        #endif
    }

    private var currentMessage: String {
        if let errorMessage {
            return errorMessage
        }
        if case .define = purpose, firstPIN != nil {
            return String(localized: "profiles.pin.confirm")
        }
        return message
    }

    private func append(_ digit: String) {
        guard pin.count < 4 else { return }
        pin.append(digit)
        guard pin.count == 4 else { return }
        let entered = pin
        pin = ""

        switch purpose {
        case let .verify(verify):
            if !verify(entered) {
                reject(String(localized: "profiles.pin.wrong"))
            }
        case let .define(define):
            if firstPIN == nil {
                firstPIN = entered
                errorMessage = nil
            } else if firstPIN == entered {
                define(entered)
            } else {
                firstPIN = nil
                reject(String(localized: "profiles.pin.mismatch"))
            }
        }
    }

    private func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func reject(_ message: String) {
        errorMessage = message
        rejectedCount += 1
    }

    #if os(macOS)
        private func handleKey(_ press: KeyPress) -> KeyPress.Result {
            switch press.key {
            case .escape:
                onCancel()
            case .delete:
                deleteDigit()
            default:
                guard let digit = press.characters.first, press.characters.count == 1, digit.isASCII,
                      digit.isNumber
                else { return .ignored }
                append(String(digit))
            }
            return .handled
        }
    #endif
}

extension PINPrompt where Footer == EmptyView {
    init(title: String, message: String, purpose: Purpose, onCancel: @escaping () -> Void) {
        self.init(title: title, message: message, purpose: purpose, onCancel: onCancel) { EmptyView() }
    }
}
