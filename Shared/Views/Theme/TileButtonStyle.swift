import SwiftUI

#if os(iOS)
    /// Large rounded tile of a touch remote, such as the player controls on the half of a foldable lying flat.
    /// `isProminent` fills it white like the primary action button, for the one action that should catch the eye.
    struct TileButtonStyle: ButtonStyle {
        var isProminent = false

        func makeBody(configuration: Configuration) -> some View {
            Tile(configuration: configuration, isProminent: isProminent)
        }

        private struct Tile: View {
            @Environment(\.isEnabled) private var isEnabled
            @Environment(\.accessibilityReduceMotion) private var reduceMotion

            let configuration: Configuration
            let isProminent: Bool

            private var shape: RoundedRectangle {
                RoundedRectangle(cornerRadius: LayoutMetrics.tileCornerRadius, style: .continuous)
            }

            var body: some View {
                configuration.label
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(background, in: shape)
                    .contentShape(shape)
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                    .animation(Motion.focus, value: configuration.isPressed)
                    .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, isPressed in isPressed }
            }

            private var foreground: Color {
                if !isEnabled {
                    return .textTertiary
                }
                return isProminent ? .black : .textPrimary
            }

            private var background: Color {
                if isProminent {
                    return isEnabled ? .white : .surfaceRaised
                }
                return configuration.isPressed ? .strokeSubtle : .surfaceRaised
            }
        }
    }

    extension ButtonStyle where Self == TileButtonStyle {
        static var tile: TileButtonStyle {
            TileButtonStyle()
        }

        static func tile(isProminent: Bool) -> TileButtonStyle {
            TileButtonStyle(isProminent: isProminent)
        }
    }
#endif
