import SwiftUI

struct PlayerChapterTrayView: View {
    var chapters: [MediaChapter]
    var currentPosition: Double
    var onSelect: (MediaChapter) -> Void

    @FocusState private var focusedChapterID: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Metrics.cardSpacing) {
                    ForEach(chapters, id: \.stableID) { chapter in
                        chapterCard(chapter)
                            .id(chapter.stableID)
                    }
                }
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.vertical, Metrics.contentPadding + 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            #if os(tvOS)
                .defaultFocus($focusedChapterID, initialChapterID)
            #endif
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
        .frame(height: Metrics.trayHeight)
        #if os(tvOS)
            .focusSection()
        #endif
    }

    private var initialChapterID: String? {
        currentChapter?.stableID ?? chapters.first?.stableID
    }

    private var currentChapter: MediaChapter? {
        chapters.first { $0.contains(time: currentPosition) }
    }

    @ViewBuilder
    private func chapterCard(_ chapter: MediaChapter) -> some View {
        let isCurrent = currentChapter?.stableID == chapter.stableID
        #if os(tvOS)
            cardContent(chapter, isCurrent: isCurrent, isFocused: focusedChapterID == chapter.stableID)
                .focusable()
                .focused($focusedChapterID, equals: chapter.stableID)
                .onTapGesture {
                    onSelect(chapter)
                }
                .accessibilityAddTraits(.isButton)
        #else
            Button {
                onSelect(chapter)
            } label: {
                cardContent(chapter, isCurrent: isCurrent, isFocused: false)
            }
            .buttonStyle(.plain)
        #endif
    }

    private func cardContent(_ chapter: MediaChapter, isCurrent: Bool, isFocused: Bool) -> some View {
        let isHighlighted = isFocused || (!Metrics.usesFocus && isCurrent)

        return VStack(alignment: .leading, spacing: Metrics.cardSpacing / 3) {
            PlayerChapterArtworkView(
                artworkPath: chapter.thumbPath,
                width: Int(Metrics.artworkWidth * 2),
                height: Int(Metrics.artworkHeight * 2),
            )
            .frame(width: Metrics.artworkWidth, height: Metrics.artworkHeight)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.artworkCornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Metrics.usesFocus ? .title2 : .body)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(Metrics.usesFocus ? 12 : 6)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(chapter.displayTitle)
                    .font(Metrics.usesFocus ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(chapter.startTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isFocused ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(.white)
        .frame(width: Metrics.artworkWidth)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .fill(.white.opacity(isHighlighted ? 0.16 : 0.06)),
        )
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .stroke(.white.opacity(isFocused ? 0.85 : 0.12), lineWidth: isFocused ? 2 : 1)
        }
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 8)
        .scaleEffect(isFocused ? 1.025 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            chapter.accessibilityDescription(
                totalCount: chapters.count,
                isCurrent: isCurrent,
            ),
        )
    }
}

private enum Metrics {
    #if os(tvOS)
        static let usesFocus = true
        static let artworkWidth: CGFloat = 320
        static let artworkCornerRadius: CGFloat = 14
        static let cardCornerRadius: CGFloat = 20
        static let cardSpacing: CGFloat = 28
        static let contentPadding: CGFloat = 12
        static let trayHeight: CGFloat = 270
    #else
        static let usesFocus = false
        static let artworkWidth: CGFloat = 172
        static let artworkCornerRadius: CGFloat = 10
        static let cardCornerRadius: CGFloat = 14
        static let cardSpacing: CGFloat = 14
        static let contentPadding: CGFloat = 2
        static let trayHeight: CGFloat = 160
    #endif

    static var artworkHeight: CGFloat {
        artworkWidth * 9 / 16
    }
}
