import SwiftUI

/// A program in the guide grid.
struct LiveTVGuideProgramCell: View {
    let program: LiveTVProgram
    let geometry: LiveTVGuideGeometry
    let tintsCategory: Bool
    let isFocused: Bool
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiveTVGuideMetrics.cellCornerRadius, style: .continuous)
    }

    private var isAiring: Bool {
        program.isAiring(at: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if program.startDate < geometry.start {
                    Image(systemName: "chevron.left")
                        .font(.cardMetadata)
                        .foregroundStyle(.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(program.title)
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                if program.isScheduledForRecording {
                    Image(systemName: program.isRecording ? "record.circle.fill" : "record.circle")
                        .font(.cardMetadata)
                        .foregroundStyle(.recordingIndicator)
                        .accessibilityLabel(Text("livetv.badge.scheduled"))
                }
            }
            Text(subtitle)
                .font(.cardMetadata)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(background, in: shape)
        .overlay(alignment: .bottomLeading) {
            if isAiring {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.progressFill)
                        .frame(width: proxy.size.width * program.progress(at: now), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(shape)
                .accessibilityHidden(true)
            }
        }
        .overlay {
            shape.stroke(.textPrimary, lineWidth: isFocused ? 3 : 0)
        }
        .scaleEffect(isFocused && !reduceMotion ? 1.03 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 10, y: 5)
        .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        program.episodeLabel ?? (
            program.startDate.formatted(date: .omitted, time: .shortened)
                + " – " + program.endDate.formatted(date: .omitted, time: .shortened)
        )
    }

    private var background: some ShapeStyle {
        let base: Color = isFocused ? .white.opacity(0.28) : (isAiring ? .surfaceRaised : .surfaceSubtle)
        guard tintsCategory, let category = LiveTVShelves.categoryOrder.first(where: program.categories.contains)
        else { return AnyShapeStyle(base) }
        return AnyShapeStyle(base.mix(with: category.guideTint, by: 0.18))
    }
}

/// The channel at the start of a guide row: logo and number, marked while it plays.
struct LiveTVGuideChannelCell: View {
    let channel: LiveTVChannel
    let isPlaying: Bool
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiveTVGuideMetrics.cellCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let number = channel.number {
                Text(number)
                    .font(.cardMetadata.monospacedDigit())
                    .foregroundStyle(.textSecondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
            LiveTVChannelLogo(channel: channel, showsNumber: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if channel.isFavorite {
                Image(systemName: "star.fill")
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .accessibilityLabel(Text("livetv.shelf.favorites"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isFocused ? Color.white.opacity(0.28) : .surfaceSubtle, in: shape)
        .overlay {
            shape.stroke(Color.selectionAccent, lineWidth: isPlaying ? 2 : 0)
        }
        .overlay {
            shape.stroke(.textPrimary, lineWidth: isFocused ? 3 : 0)
        }
        .scaleEffect(isFocused && !reduceMotion ? 1.03 : 1)
        .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("livetv.channel.watch \(channel.displayTitle)"))
    }
}

struct LiveTVGuideRulerCell: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.cardMetadata)
            .foregroundStyle(.textSecondary)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle().fill(.strokeSubtle).frame(width: 1)
            }
    }
}

struct LiveTVGuideCornerCell: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .font(.cardMetadata.weight(.semibold))
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
