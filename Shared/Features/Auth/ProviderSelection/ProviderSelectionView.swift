import SwiftUI

struct ProviderSelectionView: View {
    @FocusState private var focusedProvider: MediaProvider?
    let onSelect: (MediaProvider) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: verticalSpacing) {
                Image("Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: appLogoSize, height: appLogoSize)
                    .clipShape(RoundedRectangle(cornerRadius: appLogoCornerRadius, style: .continuous))
                    .accessibilityHidden(true)

                header
                providerChoices
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("provider.selection.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("provider.selection.subtitle")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 620)
    }

    private var providerChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: cardSpacing) {
                providerButtons
            }
            .frame(minWidth: horizontalLayoutMinimumWidth)

            VStack(spacing: cardSpacing) {
                providerButtons
            }
        }
    }

    @ViewBuilder
    private var providerButtons: some View {
        providerButton(
            title: "provider.plex",
            symbol: "play.rectangle.fill",
            accent: Color(red: 0.95, green: 0.68, blue: 0.0),
            provider: .plex,
        )
        providerButton(
            title: "provider.jellyfin",
            symbol: "server.rack",
            accent: Color(red: 0.46, green: 0.49, blue: 0.96),
            provider: .jellyfin,
        )
    }

    private func providerButton(
        title: LocalizedStringKey,
        symbol: String,
        accent: Color,
        provider: MediaProvider,
    ) -> some View {
        let isFocused = focusedProvider == provider

        return Button {
            onSelect(provider)
        } label: {
            HStack(spacing: symbolSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: logoAreaHeight)
            .padding(cardPadding)
            .frame(maxWidth: .infinity, minHeight: cardMinimumHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.13 : 0.07))
                    .overlay {
                        accent.opacity(isFocused ? 0.16 : 0.08)
                            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(
                        isFocused ? accent.opacity(0.9) : Color.white.opacity(0.12),
                        lineWidth: isFocused ? 3 : 1,
                    )
            }
            .shadow(color: isFocused ? accent.opacity(0.22) : .clear, radius: 24, y: 8)
            .scaleEffect(isFocused ? 1.035 : 1)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(ProviderCardButtonStyle())
        .focused($focusedProvider, equals: provider)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var contentMaxWidth: CGFloat {
        #if os(tvOS)
            1120
        #else
            820
        #endif
    }

    private var horizontalLayoutMinimumWidth: CGFloat {
        #if os(tvOS)
            900
        #else
            600
        #endif
    }

    private var appLogoSize: CGFloat {
        #if os(tvOS)
            192
        #else
            128
        #endif
    }

    private var appLogoCornerRadius: CGFloat {
        #if os(tvOS)
            40
        #else
            28
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            64
        #else
            24
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            72
        #else
            32
        #endif
    }

    private var verticalSpacing: CGFloat {
        #if os(tvOS)
            56
        #else
            32
        #endif
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
            40
        #else
            24
        #endif
    }

    private var cardMinimumHeight: CGFloat {
        #if os(tvOS)
            210
        #else
            140
        #endif
    }

    private var cardCornerRadius: CGFloat {
        #if os(tvOS)
            28
        #else
            20
        #endif
    }

    private var symbolSize: CGFloat {
        #if os(tvOS)
            56
        #else
            36
        #endif
    }

    private var symbolSpacing: CGFloat {
        #if os(tvOS)
            24
        #else
            14
        #endif
    }

    private var logoAreaHeight: CGFloat {
        #if os(tvOS)
            112
        #else
            80
        #endif
    }
}

private struct ProviderCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
