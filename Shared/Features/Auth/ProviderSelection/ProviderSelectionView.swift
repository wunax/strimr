import SwiftUI

struct ProviderSelectionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @FocusState private var focusedProvider: MediaProvider?
    @State private var selectingProvider: MediaProvider?

    var body: some View {
        ScrollView {
            VStack(spacing: verticalSpacing) {
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
            image: "plex_logo",
            accent: Color(red: 0.95, green: 0.68, blue: 0.0),
            provider: .plex,
        )
        providerButton(
            title: "provider.jellyfin",
            image: "jellyfin_logo",
            accent: Color(red: 0.46, green: 0.49, blue: 0.96),
            provider: .jellyfin,
        )
    }

    private func providerButton(
        title: LocalizedStringKey,
        image: String,
        accent: Color,
        provider: MediaProvider,
    ) -> some View {
        let isFocused = focusedProvider == provider
        let isSelecting = selectingProvider == provider

        return Button {
            guard selectingProvider == nil else { return }
            selectingProvider = provider
            Task { await sessionManager.selectProvider(provider) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                    .frame(maxWidth: .infinity, minHeight: logoAreaHeight)
                    .accessibilityHidden(true)
            }
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
            .opacity(selectingProvider == nil || isSelecting ? 1 : 0.5)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .animation(.easeOut(duration: 0.18), value: selectingProvider)
        }
        .buttonStyle(ProviderCardButtonStyle())
        .focused($focusedProvider, equals: provider)
        .disabled(selectingProvider != nil)
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

    private var logoMaxWidth: CGFloat {
        #if os(tvOS)
            280
        #else
            210
        #endif
    }

    private var logoMaxHeight: CGFloat {
        #if os(tvOS)
            108
        #else
            76
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
