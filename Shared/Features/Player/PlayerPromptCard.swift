import SwiftUI

/// Card raised over playing video to ask for a decision, such as Up Next or the sleep timer check-in. It dims the
/// video, sits at the bottom of the player (bottom trailing on macOS) and keeps tvOS focus on its two actions.
@MainActor
struct PlayerPromptCard<Artwork: View, Details: View, PrimaryAction: View, SecondaryAction: View>: View {
    private let hasArtwork: Bool
    private let artwork: Artwork
    private let details: Details
    private let primaryAction: PrimaryAction
    private let secondaryAction: SecondaryAction

    @FocusState private var focusedAction: Action?

    private enum Action: Hashable {
        case primary
        case secondary
    }

    init(
        @ViewBuilder details: () -> Details,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        @ViewBuilder secondaryAction: () -> SecondaryAction,
        @ViewBuilder artwork: () -> Artwork,
    ) {
        hasArtwork = true
        self.artwork = artwork()
        self.details = details()
        self.primaryAction = primaryAction()
        self.secondaryAction = secondaryAction()
    }

    var body: some View {
        ZStack {
            Color.overlayScrim
                .ignoresSafeArea()
                .contentShape(Rectangle())

            content
                .padding(Self.cardPadding)
                .frame(maxWidth: maxWidth)
                .videoOverlayGlass(
                    in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous),
                )
                .padding(Self.screenInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.placement)
            #if os(tvOS)
                .focusSection()
                .onAppear {
                    DispatchQueue.main.async {
                        focusedAction = .primary
                    }
                }
            #endif
        }
        .zIndex(100)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    artworkView
                    details
                }

                actions
            }
        #else
            HStack(alignment: .center, spacing: Self.artworkSpacing) {
                artworkView

                VStack(alignment: .leading, spacing: Self.detailsSpacing) {
                    details
                    actions
                }
            }
        #endif
    }

    @ViewBuilder
    private var artworkView: some View {
        if hasArtwork {
            artwork
                .frame(width: Self.artworkWidth, height: Self.artworkWidth * 9 / 16)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            primaryAction
                .actionButtonStyle(.primary)
            #if os(tvOS)
                .focused($focusedAction, equals: .primary)
            #endif

            secondaryAction
                .actionButtonStyle(.secondary)
            #if os(tvOS)
                .focused($focusedAction, equals: .secondary)
            #endif
        }
        .frame(maxWidth: .infinity)
        #if os(tvOS)
            .onMoveCommand { direction in
                switch direction {
                case .left where focusedAction == .secondary:
                    focusedAction = .primary
                case .right where focusedAction == .primary:
                    focusedAction = .secondary
                case .left, .right, .up, .down:
                    focusedAction = focusedAction ?? .primary
                default:
                    break
                }
            }
        #endif
    }

    private var maxWidth: CGFloat {
        #if os(tvOS)
            hasArtwork ? 1100 : 800
        #elseif os(macOS)
            hasArtwork ? 580 : 420
        #else
            520
        #endif
    }

    private static var placement: Alignment {
        #if os(macOS)
            .bottomTrailing
        #else
            .bottom
        #endif
    }

    private static var screenInsets: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 0, leading: 60, bottom: 48, trailing: 60)
        #elseif os(macOS)
            EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        #else
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        #endif
    }

    private static var cardPadding: CGFloat {
        #if os(tvOS)
            30
        #elseif os(macOS)
            18
        #else
            20
        #endif
    }

    private static var artworkWidth: CGFloat {
        #if os(tvOS)
            300
        #elseif os(macOS)
            210
        #else
            180
        #endif
    }

    private static var artworkSpacing: CGFloat {
        #if os(tvOS)
            28
        #else
            16
        #endif
    }

    private static var detailsSpacing: CGFloat {
        #if os(tvOS)
            18
        #else
            12
        #endif
    }
}

extension PlayerPromptCard where Artwork == EmptyView {
    init(
        @ViewBuilder details: () -> Details,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        @ViewBuilder secondaryAction: () -> SecondaryAction,
    ) {
        hasArtwork = false
        artwork = EmptyView()
        self.details = details()
        self.primaryAction = primaryAction()
        self.secondaryAction = secondaryAction()
    }
}
