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
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("media.detail.cast.title")
                            .font(.headline)
                            .fontWeight(.semibold)

                        if viewModel.isLoading, viewModel.cast.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    castContent
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 32)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var castContent: some View {
        if viewModel.cast.isEmpty {
            Text(viewModel.isLoading ? "media.detail.cast.loading" : "media.detail.cast.empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            CastCarousel(viewModel: viewModel, onSelectPerson: onSelectPerson)
        }
    }
}

struct CastCarousel: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectPerson: (Person) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(viewModel.cast) { member in
                    CastCard(
                        member: member,
                        imageURL: viewModel.castImageURL(for: member),
                        onSelect: member.person.map { person in
                            { onSelectPerson(person) }
                        },
                    )
                }
            }
            #if os(tvOS)
            .padding(.vertical, 12)
            #endif
        }
        .mouseDragScrolling()
        #if os(tvOS)
            .scrollClipDisabled()
        #endif
    }
}

private var sectionHorizontalPadding: CGFloat {
    #if os(macOS)
        28
    #elseif os(iOS)
        16
    #else
        0
    #endif
}

struct CastCard: View {
    let member: CastMember
    let imageURL: URL?
    let onSelect: (() -> Void)?
    #if os(tvOS)
        @FocusState private var isFocused: Bool
    #endif

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
            } else {
                content
            }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(nameFont)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                if let character = member.character {
                    Text(character)
                        .font(characterFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(width: 140, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: isFocusedValue)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                    case .empty:
                        ProgressView()
                            .tint(.secondary)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        #if os(tvOS)
            .scaleEffect(isFocused ? 1.12 : 1)
        #endif
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("media.detail.cast.noPhoto")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nameFont: Font {
        #if os(tvOS)
            .footnote
        #else
            .callout
        #endif
    }

    private var characterFont: Font {
        #if os(tvOS)
            .caption2
        #else
            .caption
        #endif
    }

    private var isFocusedValue: Bool {
        #if os(tvOS)
            isFocused
        #else
            false
        #endif
    }
}
