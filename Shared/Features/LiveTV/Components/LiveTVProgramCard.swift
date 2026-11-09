import SwiftUI

/// A 16:9 What's On card: the program's artwork with the channel logo, or the logo alone without guide data.
struct LiveTVProgramCard: View {
    let item: LiveTVShelfItem
    let size: CGSize
    var showsStartTime = false
    let onOpen: () -> Void
    var onFocus: (() -> Void)?
    var contextActions: LiveTVCardActions?

    #if os(tvOS)
        @FocusState private var isFocused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #elseif os(macOS)
        @State private var isFocused = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            artwork
            #if os(tvOS) || os(macOS)
                .cardFocusStyle(isFocused: isFocused)
            #endif
            labels
        }
        .frame(width: size.width, alignment: .leading)
        .contentShape(Rectangle())
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    onFocus?()
                }
            }
            .onPlayPauseCommand(perform: onOpen)
        #elseif os(macOS)
            .onHover { isFocused = $0 }
        #endif
            .onTapGesture(perform: onOpen)
            .contextMenu {
                if let contextActions {
                    LiveTVCardMenu(item: item, actions: contextActions)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityAddTraits(.isButton)
    }

    private var artwork: some View {
        ZStack {
            Rectangle().fill(.surfaceSubtle)
            if let path = item.program?.artPath ?? item.program?.thumbPath {
                ArtworkPathView(path: path, width: Int(size.width * 2), height: Int(size.height * 2))
            } else {
                LiveTVChannelLogo(channel: item.channel)
                    .padding(size.height * 0.22)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .mediaArtworkStyle()
        .overlay(alignment: .topLeading) {
            if item.program?.artPath != nil || item.program?.thumbPath != nil, item.channel.thumbPath != nil {
                LiveTVChannelLogo(channel: item.channel)
                    .frame(width: size.width * 0.22, height: size.height * 0.16)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.badgeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let program = item.program {
                LiveTVProgramBadges(program: program, showsStartTime: showsStartTime)
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let program = item.program, program.isCurrentlyAiring {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    CardProgressBar(progress: program.progress(at: context.date))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.program?.title ?? item.channel.title)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
            Text(item.channel.displayTitle)
                .font(.cardMetadata)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
        }
        #if os(tvOS) || os(macOS)
        .offset(y: isFocused && !reduceMotion ? size.height * (CardFocusStyle.focusedScale - 1) / 2 : 0)
        .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
        #endif
    }

    private var accessibilityText: String {
        guard let program = item.program else { return item.channel.displayTitle }
        return String(localized: "livetv.onNow.program.accessibility \(program.title) \(item.channel.displayTitle)")
    }
}

/// Status badges over a program's artwork: recording, start time of an upcoming program.
struct LiveTVProgramBadges: View {
    let program: LiveTVProgram
    var showsStartTime = false

    var body: some View {
        HStack(spacing: 6) {
            if program.isScheduledForRecording {
                Image(systemName: program.isRecording ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(.recordingIndicator)
                    .accessibilityLabel(Text(
                        program.isRecording ? "livetv.recording.status.recording" : "livetv.recording.status.scheduled",
                    ))
            }
            if showsStartTime {
                Text(program.startDate, format: .dateTime.hour().minute())
                    .foregroundStyle(.textPrimary)
            }
        }
        .font(.badge)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.badgeBackground, in: Capsule(style: .continuous))
        .opacity(program.isScheduledForRecording || showsStartTime ? 1 : 0)
    }
}

struct LiveTVCardActions {
    let watch: (LiveTVChannel, LiveTVProgram?) -> Void
    let details: ((LiveTVProgram) -> Void)?
    let record: ((LiveTVProgram) -> Void)?
    let toggleFavorite: (LiveTVChannel) -> Void
}

private struct LiveTVCardMenu: View {
    let item: LiveTVShelfItem
    let actions: LiveTVCardActions

    var body: some View {
        if item.program?.isCurrentlyAiring ?? true {
            Button("livetv.watchLive", systemImage: "play.fill") { actions.watch(item.channel, item.program) }
        }
        if let program = item.program {
            if let details = actions.details {
                Button("livetv.program.details", systemImage: "info.circle") { details(program) }
            }
            if let record = actions.record, !program.isScheduledForRecording {
                Button("livetv.record", systemImage: "record.circle") { record(program) }
            }
        }
        Button(
            item.channel.isFavorite ? "livetv.favorite.remove" : "livetv.favorite.add",
            systemImage: item.channel.isFavorite ? "star.slash" : "star",
        ) {
            actions.toggleFavorite(item.channel)
        }
    }
}
