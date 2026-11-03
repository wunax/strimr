import SwiftUI

enum HomeHeroMode {
    /// The hero fills the screen with the featured titles.
    case showcase
    /// Focus is in the rows and the hero follows the focused card.
    case browsing
}

enum HomeHeroButton: Hashable {
    case play
    case details
}

/// Text, actions and pagination of the home hero's current page.
struct HomeShowcaseContentView: View {
    let slide: HomeHeroSlide
    let index: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let eyebrow = slide.eyebrow {
                Text(eyebrow)
                    .eyebrowStyle()
                    .foregroundStyle(.textSecondary)
            }

            MediaHeroContentView(media: slide.media)

            if slide.isResume, let progress = slide.media.viewProgressPercentage {
                ProgressView(value: progress, total: 100)
                    .progressViewStyle(HeroProgressStyle())
                    .frame(width: 360)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(slide.accessibilityLabel)
    }
}

/// The two actions of the hero page.
struct HomeShowcaseActions: View {
    let slide: HomeHeroSlide
    let focusedButton: FocusState<HomeHeroButton?>.Binding
    let onPlay: () -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button(action: onPlay) {
                Label(
                    slide.isResume ? "common.actions.resume" : "common.actions.play",
                    systemImage: "play.fill",
                )
            }
            .actionButtonStyle(.primary)
            .focused(focusedButton, equals: .play)

            Button(action: onDetails) {
                Label("home.hero.moreInfo", systemImage: "info.circle")
            }
            .actionButtonStyle(.secondary)
            .focused(focusedButton, equals: .details)
        }
    }
}

struct HomeShowcasePageIndicator: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0 ..< count, id: \.self) { page in
                Capsule()
                    .fill(page == index ? AnyShapeStyle(.selectionAccent) : AnyShapeStyle(.textTertiary))
                    .frame(width: page == index ? 32 : 12, height: 12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("home.hero.page \(index + 1) \(count)"))
    }
}

private struct HeroProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.progressTrack)
                Capsule()
                    .fill(.progressFill)
                    .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 8)
    }
}
