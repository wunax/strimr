import SwiftUI

struct MediaFileInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                Group {
                    if viewModel.isLoadingFileInfo {
                        ProgressView("media.fileInfo.loading")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if let fileInfo = viewModel.fileInfo, !fileInfo.versions.isEmpty {
                        fileInfoContent(fileInfo)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .navigationTitle("media.fileInfo.title")
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.close") { dismiss() }
                    }
                }
            #endif
        }
        .task {
            await viewModel.loadFileInfo()
        }
    }

    private func fileInfoContent(_ fileInfo: MediaFileInfo) -> some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.media.title)
                    .font(.title2.weight(.semibold))
                if let summary = fileInfo.firstVersion?.summaryLabels, !summary.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(summary, id: \.self) { label in
                                Text(label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.secondary.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }

            ForEach(Array(fileInfo.versions.enumerated()), id: \.offset) { index, version in
                MediaFileInfoVersionView(index: index, version: version)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(viewModel.fileInfoErrorMessage == nil
                ? "media.fileInfo.unavailable"
                : "media.fileInfo.error")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let errorMessage = viewModel.fileInfoErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.loadFileInfo(forceReload: true) }
            } label: {
                Label("common.actions.retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private struct MediaFileInfoVersionView: View {
    let index: Int
    let version: MediaFileVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: versionTitle)
                .font(.headline)

            infoSection("media.fileInfo.summary", systemImage: "info.circle") {
                field("media.fileInfo.container", version.container?.uppercased())
                field("media.fileInfo.duration", version.durationText)
                field("media.fileInfo.size", version.totalSizeText)
                field("media.fileInfo.bitrate", version.bitrateText)
                field("media.fileInfo.resolution", version.resolutionText)
                field("media.fileInfo.aspectRatio", version.aspectRatio)
                field("media.fileInfo.videoCodec", combined(version.videoCodec, version.videoProfile))
                field("media.fileInfo.frameRate", version.videoFrameRate)
                field("media.fileInfo.audioCodec", combined(version.audioCodec, version.audioProfile))
                field("media.fileInfo.channels", version.audioChannels.map { "\($0)" })
            }

            if !version.parts.isEmpty {
                infoSection("media.fileInfo.file", systemImage: "doc") {
                    ForEach(Array(version.parts.enumerated()), id: \.offset) { index, part in
                        MediaFileInfoPartView(index: index, part: part)
                    }
                }
            }

            if !version.attachments.isEmpty {
                infoSection("media.fileInfo.attachments", systemImage: "paperclip") {
                    ForEach(Array(version.attachments.enumerated()), id: \.offset) { _, attachment in
                        VStack(alignment: .leading, spacing: 6) {
                            field("media.fileInfo.fileName", attachment.fileName)
                            field("media.fileInfo.codec", attachment.codec)
                            field("media.fileInfo.mimeType", attachment.mimeType)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    private var versionTitle: String {
        String(localized: "media.fileInfo.version \(index + 1)")
    }

    @ViewBuilder
    private func infoSection<Content: View>(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content,
    ) -> some View where Content: View {
        VStack(alignment: .leading, spacing: 12) {
            Label(titleKey, systemImage: systemImage)
                .font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func field(_ labelKey: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            MediaFileInfoField(label: labelKey, value: value)
        }
    }

    private func combined(_ first: String?, _ second: String?) -> String? {
        switch (first, second) {
        case let (first?, second?) where !first.isEmpty && !second.isEmpty:
            "\(first) (\(second))"
        case let (first?, _):
            first
        case let (_, second?):
            second
        default:
            nil
        }
    }
}

private struct MediaFileInfoPartView: View {
    let index: Int
    let part: MediaFilePart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: fileTitle)
                .font(.subheadline.weight(.semibold))
            field("media.fileInfo.fileName", part.fileName)
            field("media.fileInfo.path", part.path)
            field("media.fileInfo.size", part.sizeText)
            field("media.fileInfo.container", part.container?.uppercased())
            field("media.fileInfo.duration", part.durationText)
            if let exists = part.exists {
                field("media.fileInfo.filePresent", exists ? String(localized: "media.fileInfo.yes") : String(localized: "media.fileInfo.no"))
            }
            if let accessible = part.accessible {
                field("media.fileInfo.fileReadable", accessible ? String(localized: "media.fileInfo.yes") : String(localized: "media.fileInfo.no"))
            }
            if let id = part.id {
                field("media.fileInfo.fileId", id)
            }

            ForEach([MediaFileStreamKind.video, .audio, .subtitle, .other], id: \.self) { kind in
                let streams = part.streams.filter { $0.kind == kind }
                if !streams.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(kind.titleKey, systemImage: kind.systemImage)
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(streams.enumerated()), id: \.offset) { _, stream in
                            MediaFileInfoStreamView(stream: stream)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var fileTitle: String {
        String(localized: "media.fileInfo.file \(index + 1)")
    }

    @ViewBuilder
    private func field(_ labelKey: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            MediaFileInfoField(label: labelKey, value: value)
        }
    }
}

private struct MediaFileInfoStreamView: View {
    let stream: MediaFileStream

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stream.headline)
                .font(.callout.weight(.semibold))

            HStack(spacing: 6) {
                ForEach(flagKeys, id: \.self) { key in
                    Text(LocalizedStringKey(key))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.14), in: Capsule())
                }
            }

            field("media.fileInfo.codec", stream.codec)
            field("media.fileInfo.codecTag", stream.codecTag)
            field("media.fileInfo.profile", stream.profile)
            field("media.fileInfo.language", stream.language)
            field("media.fileInfo.languageCode", stream.languageCode)
            field("media.fileInfo.bitrate", stream.bitrateText)
            field("media.fileInfo.resolution", stream.resolutionText)
            field("media.fileInfo.frameRate", stream.frameRateText)
            field("media.fileInfo.bitDepth", stream.bitDepth.map { "\($0)-bit" })
            field("media.fileInfo.dynamicRange", stream.dynamicRange)
            field("media.fileInfo.pixelFormat", stream.pixelFormat)
            field("media.fileInfo.colorSpace", stream.colorSpace)
            field("media.fileInfo.colorTransfer", stream.colorTransfer)
            field("media.fileInfo.aspectRatio", stream.aspectRatio)
            field("media.fileInfo.channels", stream.channelsText)
            field("media.fileInfo.sampleRate", stream.sampleRateText)
            field("media.fileInfo.spatialAudio", stream.spatialFormat)
            field("media.fileInfo.subtitleFormat", stream.subtitleFormat)
            field("media.fileInfo.path", stream.path)
            if let index = stream.index {
                field("media.fileInfo.streamIndex", String(index))
            }
            if let id = stream.id {
                field("media.fileInfo.streamId", id)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.35))
                .frame(width: 3)
        }
    }

    private var flagKeys: [String] {
        [
            stream.isDefault == true ? "media.fileInfo.default" : nil,
            stream.isSelected == true ? "media.fileInfo.selected" : nil,
            stream.isForced == true ? "media.fileInfo.forced" : nil,
            stream.isExternal == true ? "media.fileInfo.external" : nil,
            stream.isHearingImpaired == true ? "media.fileInfo.hearingImpaired" : nil,
        ].compactMap { $0 }
    }

    @ViewBuilder
    private func field(_ labelKey: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            MediaFileInfoField(label: labelKey, value: value)
        }
    }
}

private struct MediaFileInfoField: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
    }
}

private extension MediaFileStreamKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .video:
            "media.fileInfo.video"
        case .audio:
            "media.fileInfo.audio"
        case .subtitle:
            "media.fileInfo.subtitles"
        case .other:
            "media.fileInfo.other"
        }
    }

    var systemImage: String {
        switch self {
        case .video:
            "film"
        case .audio:
            "waveform"
        case .subtitle:
            "captions.bubble"
        case .other:
            "questionmark.square"
        }
    }
}
