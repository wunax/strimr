import SwiftUI

struct PlayerChapterTrayView: View {
    var chapters: [PlexChapter]
    var currentPosition: Double
    var imageURL: (PlexChapter) -> URL?
    var onSelect: (PlexChapter) -> Void
    var onFocusExit: () -> Void

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
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear {
                    let initialID = currentChapter?.stableID ?? chapters.first?.stableID
                    DispatchQueue.main.async {
                        focusedChapterID = initialID
                        if let initialID {
                            proxy.scrollTo(initialID, anchor: .center)
                        }
                    }
                }
                .onChange(of: focusedChapterID) { previousID, chapterID in
                    if let chapterID {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(chapterID, anchor: .center)
                        }
                    } else if previousID != nil {
                        onFocusExit()
                    }
                }
            }
        }
        .frame(height: 310)
        .focusSection()
    }

    private var currentChapter: PlexChapter? {
        chapters.first { $0.contains(time: currentPosition) }
    }

    private func chapterCard(_ chapter: PlexChapter) -> some View {
        let isFocused = focusedChapterID == chapter.stableID
        let isCurrent = currentChapter?.stableID == chapter.stableID

        return VStack(alignment: .leading, spacing: 10) {
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
                    .foregroundStyle(isFocused ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 320)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.16 : 0.06)),
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(isFocused ? 0.85 : 0.12), lineWidth: isFocused ? 2 : 1)
        }
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 8)
        .scaleEffect(isFocused ? 1.025 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .focusable()
        .focused($focusedChapterID, equals: chapter.stableID)
        .onTapGesture {
            onSelect(chapter)
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            chapter.accessibilityDescription(
                totalCount: chapters.count,
                isCurrent: isCurrent,
            ),
        )
    }
}
