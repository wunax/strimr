import SwiftUI

struct PlayerChapterTrayView: View {
    var chapters: [MediaChapter]
    var currentPosition: Double
    var onSelect: (MediaChapter) -> Void

    @FocusState private var focusedChapterID: String?

    var body: some View {
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
            .defaultFocus($focusedChapterID, initialChapterID)
            .onAppear {
                guard let initialChapterID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(initialChapterID, anchor: .center)
                }
            }
            .onChange(of: focusedChapterID) { _, chapterID in
                if let chapterID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(chapterID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 270)
        .focusSection()
    }

    private var initialChapterID: String? {
        currentChapter?.stableID ?? chapters.first?.stableID
    }

    private var currentChapter: MediaChapter? {
        chapters.first { $0.contains(time: currentPosition) }
    }

    private func chapterCard(_ chapter: MediaChapter) -> some View {
        let isFocused = focusedChapterID == chapter.stableID
        let isCurrent = currentChapter?.stableID == chapter.stableID

        return VStack(alignment: .leading, spacing: 10) {
            PlayerChapterArtworkView(
                artworkPath: chapter.thumbPath,
                width: 640,
                height: 360,
            )
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
