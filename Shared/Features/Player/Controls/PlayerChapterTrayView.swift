import SwiftUI

struct PlayerChapterTrayView: View {
    var chapters: [MediaChapter]
    var currentPosition: Double
    var onSelect: (MediaChapter) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
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
            .buttonStyle(.cardLift)
        #endif
    }

    private func cardContent(_ chapter: MediaChapter, isCurrent: Bool, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            PlayerChapterArtworkView(
                artworkPath: chapter.thumbPath,
                width: Int(Metrics.artworkWidth * 2),
                height: Int(Metrics.artworkHeight * 2),
            )
            .frame(width: Metrics.artworkWidth, height: Metrics.artworkHeight)
            .background(.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Metrics.usesFocus ? .title2 : .body)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(Metrics.usesFocus ? 12 : 6)
                }
            }
            .cardFocusStyle(isFocused: isFocused)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(chapter.displayTitle)
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(chapter.startTimeText)
                    .font(.cardMetadata.monospacedDigit())
                    .foregroundStyle(.textSecondary)
            }
        }
        .frame(width: Metrics.artworkWidth)
        .contentShape(Rectangle())
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
        static let cardSpacing: CGFloat = 28
        static let contentPadding: CGFloat = 12
        static let trayHeight: CGFloat = 270
    #else
        static let usesFocus = false
        static let artworkWidth: CGFloat = 172
        static let cardSpacing: CGFloat = 14
        static let contentPadding: CGFloat = 2
        static let trayHeight: CGFloat = 160
    #endif

    static var artworkHeight: CGFloat {
        artworkWidth * 9 / 16
    }
}
