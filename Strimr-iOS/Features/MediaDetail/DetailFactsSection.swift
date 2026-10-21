import SwiftUI

/// Genres and studio of the title.
struct DetailFactsSection: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        genresSection

        if let studio = viewModel.media.studio {
            metaRow(label: String(localized: "media.detail.studio"), value: studio)
        }
    }

    @ViewBuilder
    private var genresSection: some View {
        if !viewModel.media.genres.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("media.detail.genres")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.media.genres, id: \.self) { genre in
                            badge(text: genre)
                        }
                    }
                }
            }
        }
    }

    private func badge(text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}
