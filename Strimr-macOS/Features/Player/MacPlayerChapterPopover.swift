import SwiftUI

struct MacPlayerChapterPopover: View {
    var chapters: [PlexChapter]
    var currentPosition: Double
    var imageURL: (PlexChapter) -> URL?
    var onSelect: (PlexChapter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("player.chapters.title")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(chapters, id: \.stableID) { chapter in
                            chapterRow(chapter)
                                .id(chapter.stableID)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    guard let currentChapter else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(currentChapter.stableID, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 360, height: 420)
    }

    private var currentChapter: PlexChapter? {
        chapters.first { $0.contains(time: currentPosition) }
    }

    private func chapterRow(_ chapter: PlexChapter) -> some View {
        let isCurrent = currentChapter?.stableID == chapter.stableID

        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 12) {
                PlayerChapterArtworkView(imageURL: imageURL(chapter))
                    .frame(width: 120, height: 68)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(chapter.startTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.15) : .clear),
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            chapter.accessibilityDescription(
                totalCount: chapters.count,
                isCurrent: isCurrent,
            ),
        )
    }
}
