import Observation
import SwiftUI

struct CastSection: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Cast")
                            .font(.headline)
                            .fontWeight(.semibold)

                        if viewModel.isLoading && viewModel.cast.isEmpty {
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
            Text(viewModel.isLoading ? "Loading cast…" : "No cast information available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            CastCarousel(viewModel: viewModel)
        }
    }
}

struct CastCarousel: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(viewModel.cast) { member in
                    CastCard(
                        member: member,
                        imageURL: viewModel.castImageURL(for: member)
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct CastCard: View {
    let member: CastMember
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                if let character = member.character {
                    Text(character)
                        .font(.footnote)
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 160)
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
        .frame(width: 120, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
