import Observation
import SwiftUI

struct CastSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectPerson: (Person) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onSelectPerson: @escaping (Person) -> Void = { _ in },
    ) {
        self.viewModel = viewModel
        self.onSelectPerson = onSelectPerson
    }

    var body: some View {
        if viewModel.isLoading || !viewModel.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                MediaHubSection(title: String(localized: "media.detail.cast.title")) {
                    if viewModel.cast.isEmpty {
                        CastSkeleton()
                    } else {
                        CastCarousel(viewModel: viewModel, onSelectPerson: onSelectPerson)
                    }
                }
            }
            .padding(.horizontal, LayoutMetrics.detailSectionMargin)
            .environment(\.railPageMargin, LayoutMetrics.detailSectionMargin)
            .padding(.bottom, 32)
        }
    }
}

struct CastCarousel: View {
    @Environment(\.railPageMargin) private var pageMargin
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectPerson: (Person) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .portrait)) {
                ForEach(viewModel.cast) { member in
                    CastCard(
                        member: member,
                        imageURL: viewModel.castImageURL(for: member),
                        artworkPath: member.thumbPath,
                        onSelect: member.person.flatMap { person in
                            viewModel.canOpenPerson(person) ? { onSelectPerson(person) } : nil
                        },
                    )
                }
            }
            .padding(.vertical, LayoutMetrics.railVerticalInset)
        }
        #if !os(tvOS)
        .padding(.vertical, -LayoutMetrics.railVerticalInset)
        #endif
        .railBleed(pageMargin: pageMargin)
        .mouseDragScrolling()
        #if os(tvOS)
            .scrollClipDisabled()
            .focusSection()
        #endif
    }
}

struct CastCard: View {
    let member: CastMember
    let imageURL: URL?
    let artworkPath: String?
    let onSelect: (() -> Void)?
    #if os(tvOS)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool
    #elseif os(macOS)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isFocused = false
    #endif

    private let avatarSize = LayoutMetrics.castAvatarSize

    var body: some View {
        #if os(tvOS)
            if let onSelect {
                content
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($isFocused)
                    .onTapGesture(perform: onSelect)
            } else {
                content
            }
        #else
            if let onSelect {
                Button(action: onSelect) {
                    content
                }
                .buttonStyle(.plain)
                #if os(macOS)
                    .onHover { isFocused = $0 }
                #endif
            } else {
                content
            }
        #endif
    }

    private var content: some View {
        VStack(spacing: LayoutMetrics.cardLabelSpacing) {
            avatar
            #if os(tvOS) || os(macOS)
                .cardFocusStyle(isFocused: isFocused)
            #endif

            labels
        }
        .frame(width: LayoutMetrics.castCardWidth)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Circle()
            .fill(.surfaceSubtle)
            .overlay {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            Color.clear
                        default:
                            placeholder
                        }
                    }
                } else if artworkPath != nil {
                    ArtworkPathView(path: artworkPath, width: Int(avatarSize * 2), height: Int(avatarSize * 2))
                } else {
                    placeholder
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: avatarSize * 0.4))
            .foregroundStyle(.textTertiary)
    }

    private var labels: some View {
        VStack(spacing: 2) {
            Text(member.name)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary.opacity(nameOpacity))
                .lineLimit(2)
            if let character = member.character {
                Text(character)
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .opacity(characterOpacity)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        #if os(tvOS) || os(macOS)
            // Follows the bottom edge of the focused avatar so the lifted photo does not cover its caption.
            .offset(y: isFocused && !reduceMotion ? avatarSize * (CardFocusStyle.focusedScale - 1) / 2 : 0)
            .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
        #endif
    }

    private var nameOpacity: Double {
        #if os(tvOS)
            isFocused ? 1 : 0.45
        #else
            1
        #endif
    }

    /// Relative to `textSecondary`, matching the unfocused captions of media cards.
    private var characterOpacity: Double {
        #if os(tvOS)
            isFocused ? 1 : 0.32 / 0.65
        #else
            1
        #endif
    }
}

struct CastSkeleton: View {
    @Environment(\.railPageMargin) private var pageMargin

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .portrait)) {
                ForEach(0 ..< 8, id: \.self) { _ in
                    VStack(spacing: LayoutMetrics.cardLabelSpacing) {
                        Circle()
                            .fill(.surfaceSubtle)
                            .frame(width: LayoutMetrics.castAvatarSize, height: LayoutMetrics.castAvatarSize)
                        VStack(spacing: 2) {
                            SkeletonLine(font: .cardTitle, fraction: 1)
                                .frame(width: LayoutMetrics.castCardWidth * 0.7)
                            SkeletonLine(font: .cardMetadata, fraction: 1)
                                .frame(width: LayoutMetrics.castCardWidth * 0.5)
                        }
                    }
                    .frame(width: LayoutMetrics.castCardWidth)
                }
            }
            #if os(tvOS)
            .padding(.vertical, LayoutMetrics.railVerticalInset)
            #endif
        }
        .scrollDisabled(true)
        .railBleed(pageMargin: pageMargin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("common.loading"))
    }
}
