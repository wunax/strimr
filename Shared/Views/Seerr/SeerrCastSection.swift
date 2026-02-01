import Observation
import SwiftUI

struct SeerrCastSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel

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
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
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
            SeerrCastCarousel(viewModel: viewModel)
        }
    }
}

private struct SeerrCastCarousel: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(viewModel.cast) { member in
                    SeerrCastCard(
                        member: member,
                        imageURL: viewModel.castImageURL(for: member, width: 240, height: 240),
                    )
                }
            }
            .padding(.vertical, 0)
            .padding(.horizontal, 2)
        }
    }
}

private struct SeerrCastCard: View {
    let member: SeerrCastMember
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name ?? "")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                if let character = member.character {
                    Text(character)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(width: 140, alignment: .leading)
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
}
