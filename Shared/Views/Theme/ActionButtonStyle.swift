import SwiftUI

/// `primary` is the one main action of a page, such as Play; `secondary` sits beside it.
enum ActionButtonRole {
    case primary
    case secondary
}

extension View {
    /// Capsule action button. tvOS keeps the system bordered styles for the native focus lift and focused colors;
    /// elsewhere the capsule is drawn here. Like the system styles, it pads the label, which can still set a width.
    @ViewBuilder
    func actionButtonStyle(_ role: ActionButtonRole) -> some View {
        #if os(tvOS)
            switch role {
            case .primary:
                buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
                    .foregroundStyle(.black)
            case .secondary:
                buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        #else
            buttonStyle(CapsuleActionButtonStyle(role: role))
        #endif
    }
}

#if !os(tvOS)
    private struct CapsuleActionButtonStyle: ButtonStyle {
        let role: ActionButtonRole

        func makeBody(configuration: Configuration) -> some View {
            CapsuleActionButton(role: role, configuration: configuration)
        }
    }

    private struct CapsuleActionButton: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize
        let role: ActionButtonRole
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .transformEnvironment(\.font) { font in
                    switch controlSize {
                    case .mini:
                        font = .caption
                    case .small:
                        font = .subheadline
                    default:
                        break
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minHeight)
                .background(background, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
                .opacity(configuration.isPressed ? 0.7 : 1)
            #if os(macOS)
                .hoverLift(scale: 1.03)
            #endif
        }

        private var horizontalPadding: CGFloat {
            switch controlSize {
            case .mini: 12
            case .small: 16
            default: 20
            }
        }

        private var minHeight: CGFloat {
            switch controlSize {
            case .mini: LayoutMetrics.miniActionButtonHeight
            case .small: LayoutMetrics.smallActionButtonHeight
            default: LayoutMetrics.actionButtonHeight
            }
        }

        private var foreground: Color {
            switch role {
            case .primary:
                isEnabled ? .black : .secondary
            case .secondary:
                isEnabled ? .textPrimary : .textTertiary
            }
        }

        private var background: Color {
            switch role {
            case .primary:
                isEnabled ? .white : .surfaceRaised
            case .secondary:
                .surfaceRaised
            }
        }
    }
#endif
