import SwiftUI

/// Key and value rows at the bottom of the detail page: genres and studio.
struct DetailFactsSection: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        DetailFactsList(rows: rows)
    }

    private var rows: [DetailFactRow] {
        var rows: [DetailFactRow] = []
        if !viewModel.media.genres.isEmpty {
            rows.append(DetailFactRow(
                label: String(localized: "media.detail.genres"),
                value: viewModel.media.genres.joined(separator: ", "),
            ))
        }
        if let studio = viewModel.media.studio, !studio.isEmpty {
            rows.append(DetailFactRow(label: String(localized: "media.detail.studio"), value: studio))
        }
        return rows
    }
}

struct DetailFactRow {
    let label: String
    let value: String
}

/// The "Details" block closing a detail page; hidden when there is nothing to list.
struct DetailFactsList: View {
    let rows: [DetailFactRow]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                Text("media.detail.details")
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label)
                                .foregroundStyle(.textTertiary)
                                .frame(width: 96, alignment: .leading)
                            Text(row.value)
                                .foregroundStyle(.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.facts)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
