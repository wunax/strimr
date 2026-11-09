import SwiftUI

/// Leads to the title's other editions. Each one is a separate item with its own progress, so this opens its page
/// instead of switching what plays like the version menu does.
struct OtherEditionsButton: View {
    let viewModel: MediaDetailViewModel

    var body: some View {
        let editions = viewModel.otherEditions
        if editions.count == 1, let edition = editions.first {
            Button {
                viewModel.selectEdition(edition)
            } label: {
                label(
                    String(localized: "media.editions.otherOne \(edition.editionLabel)"),
                    systemImage: "chevron.right",
                )
            }
            .modifier(OtherEditionsButtonStyle())
        } else if !editions.isEmpty {
            Menu {
                ForEach(editions) { edition in
                    Button {
                        viewModel.selectEdition(edition)
                    } label: {
                        Text(verbatim: edition.editionLabel)
                        if let remaining = edition.remainingTimeText {
                            Text(verbatim: remaining)
                        }
                    }
                }
            } label: {
                label(String(localized: "media.editions.otherCount \(editions.count)"), systemImage: "chevron.down")
            }
            .modifier(OtherEditionsButtonStyle())
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        #if os(tvOS)
            // Matches the version, audio and subtitle pills it sits next to.
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .lineLimit(1)
                Image(systemName: systemImage)
                    .font(.cardMetadata.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.cardMetadata)
        #else
            HStack(spacing: 6) {
                Text(verbatim: title)
                    .lineLimit(1)
                Image(systemName: systemImage)
                    .font(.badge.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        #endif
    }
}

private struct OtherEditionsButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
            // Hierarchical styles, not the white theme tokens, so the label turns dark when focused.
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .menuIndicator(.hidden)
        #else
            content
                .font(.facts)
                .foregroundStyle(.textSecondary)
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
        #endif
    }
}
