import SwiftUI

struct PlayerChapterSelectionView: View {
    var chapters: [MediaChapter]
    var currentPosition: Double
    var imageURL: (MediaChapter) -> URL?
    var onSelect: (MediaChapter) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(chapters, id: \.stableID) { chapter in
                        chapterRow(chapter)
                            .id(chapter.stableID)
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    guard let currentChapter else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(currentChapter.stableID, anchor: .center)
                    }
                }
            }
            .navigationTitle("player.chapters.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.actions.done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var currentChapter: MediaChapter? {
        chapters.first { $0.contains(time: currentPosition) }
    }

    private func chapterRow(_ chapter: MediaChapter) -> some View {
        let isCurrent = currentChapter?.stableID == chapter.stableID

        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 14) {
                PlayerChapterArtworkView(imageURL: imageURL(chapter))
                    .frame(width: 112, height: 63)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.displayTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(chapter.startTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            chapter.accessibilityDescription(
                totalCount: chapters.count,
                isCurrent: isCurrent,
            ),
        )
    }
}
