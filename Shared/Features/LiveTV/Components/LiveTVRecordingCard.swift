import SwiftUI

/// A recording as a 16:9 card, its status in a badge over the artwork.
struct LiveTVRecordingCard: View {
    let recording: DVRRecording
    let program: LiveTVProgram?
    let size: CGSize
    let onOpen: () -> Void
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?

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
            .onPlayPauseCommand(perform: onOpen)
        #elseif os(macOS)
            .onHover { isFocused = $0 }
        #endif
            .onTapGesture(perform: onOpen)
            .contextMenu {
                if let onCancel {
                    Button("livetv.recording.cancel", systemImage: "xmark.circle", role: .destructive, action: onCancel)
                }
                if let onDelete {
                    Button("common.delete", systemImage: "trash", role: .destructive, action: onDelete)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private var artworkPath: String? {
        program?.artPath ?? program?.thumbPath ?? recording.playableMedia?.thumbPath
    }

    private var artwork: some View {
        ZStack {
            Rectangle().fill(.surfaceSubtle)
            if let artworkPath {
                ArtworkPathView(path: artworkPath, width: Int(size.width * 2), height: Int(size.height * 2))
            } else {
                Image(systemName: "record.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.textTertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .mediaArtworkStyle()
        .overlay(alignment: .topTrailing) {
            if recording.status != .completed {
                Label(recording.status.localizedTitle, systemImage: recording.status.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.badge)
                    .foregroundStyle(recording.status == .recording ? Color.recordingIndicator : .textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.badgeBackground, in: Capsule(style: .continuous))
                    .padding(8)
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.cardMetadata)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
        }
        #if os(tvOS) || os(macOS)
        .offset(y: isFocused && !reduceMotion ? size.height * (CardFocusStyle.focusedScale - 1) / 2 : 0)
        .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
        #endif
    }

    private var subtitle: String {
        var parts: [String] = []
        if let start = recording.startDate {
            parts.append(start.formatted(.dateTime.weekday().hour().minute()))
        }
        if let channel = recording.channelTitle {
            parts.append(channel)
        }
        return parts.joined(separator: " · ")
    }
}

extension DVRRecordingStatus {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .scheduled: "livetv.recording.status.scheduled"
        case .recording: "livetv.recording.status.recording"
        case .completed: "livetv.recording.status.completed"
        case .cancelled: "livetv.recording.status.cancelled"
        case .error: "livetv.recording.status.error"
        case .unknown: "livetv.recording.status.unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: "clock"
        case .recording: "record.circle.fill"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .error: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }
}
