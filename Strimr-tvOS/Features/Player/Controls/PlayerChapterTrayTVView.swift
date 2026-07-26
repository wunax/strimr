import SwiftUI

struct PlayerChapterTrayTVView: View {
    var chapters: [PlexChapter]
    var currentPosition: Double
    var imageURL: (PlexChapter) -> URL?
    var onSelect: (PlexChapter) -> Void

    @FocusState private var focusedChapterID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("player.chapters.title")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 28) {
                        ForEach(chapters, id: \.stableID) { chapter in
                            chapterCard(chapter)
                                .id(chapter.stableID)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    let initialID = currentChapter?.stableID ?? chapters.first?.stableID
                    DispatchQueue.main.async {
                        focusedChapterID = initialID
                        if let initialID {
                            proxy.scrollTo(initialID, anchor: .center)
                        }
                    }
                }
                .onChange(of: focusedChapterID) { _, chapterID in
                    guard let chapterID else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(chapterID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 285)
        .focusSection()
    }

    private var currentChapter: PlexChapter? {
        chapters.first { $0.contains(time: currentPosition) }
    }

    private func chapterCard(_ chapter: PlexChapter) -> some View {
        let isFocused = focusedChapterID == chapter.stableID
        let isCurrent = currentChapter?.stableID == chapter.stableID

        return Button {
            onSelect(chapter)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                PlayerChapterArtworkView(imageURL: imageURL(chapter))
                    .frame(width: 320, height: 180)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .padding(12)
                        }
                    }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(chapter.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(chapter.startTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 320)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(isFocused ? 0.2 : 0.06)),
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(isFocused ? 0.9 : 0.12), lineWidth: isFocused ? 3 : 1)
            }
            .scaleEffect(isFocused ? 1.04 : 1)
            .animation(.easeInOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedChapterID, equals: chapter.stableID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            chapter.accessibilityDescription(
                totalCount: chapters.count,
                isCurrent: isCurrent,
            ),
        )
    }
}
