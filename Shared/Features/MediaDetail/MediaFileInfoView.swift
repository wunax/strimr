import SwiftUI

private enum MediaFileInfoLayout {
    #if os(tvOS)
        static let outerHorizontalPadding: CGFloat = 12
        static let maximumContentWidth: CGFloat = 1400
        static let minimumFieldWidth: CGFloat = 300
        static let outerVerticalPadding: CGFloat = 32
        static let contentSpacing: CGFloat = 32
        static let versionSpacing: CGFloat = 24
        static let partListSpacing: CGFloat = 20
        static let attachmentListSpacing: CGFloat = 18
        static let subsectionSpacing: CGFloat = 18
        static let cardContentSpacing: CGFloat = 18
        static let cardPadding: CGFloat = 20
        static let gridSpacing: CGFloat = 16
        static let disclosureContentPadding: CGFloat = 16
        static let nestedLabelSpacing: CGFloat = 12
        static let streamSpacing: CGFloat = 16
        static let streamPadding: CGFloat = 16
        static let streamListSpacing: CGFloat = 14
        static let disclosureSpacing: CGFloat = 20
        static let nestedLabelVerticalPadding: CGFloat = 4
        static let partVerticalPadding: CGFloat = 6
    #else
        static let outerHorizontalPadding: CGFloat = 24
        static let maximumContentWidth: CGFloat = 1000
        static let minimumFieldWidth: CGFloat = 190
        static let outerVerticalPadding: CGFloat = 24
        static let contentSpacing: CGFloat = 24
        static let versionSpacing: CGFloat = 16
        static let partListSpacing: CGFloat = 16
        static let attachmentListSpacing: CGFloat = 14
        static let subsectionSpacing: CGFloat = 14
        static let cardContentSpacing: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 12
        static let disclosureContentPadding: CGFloat = 12
        static let nestedLabelSpacing: CGFloat = 8
        static let streamSpacing: CGFloat = 12
        static let streamPadding: CGFloat = 12
        static let streamListSpacing: CGFloat = 10
        static let disclosureSpacing: CGFloat = 0
        static let nestedLabelVerticalPadding: CGFloat = 0
        static let partVerticalPadding: CGFloat = 4
    #endif
}

struct MediaFileInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: MediaDetailViewModel
    let targetMedia: MediaItem?

    init(viewModel: MediaDetailViewModel, targetMedia: MediaItem? = nil) {
        _viewModel = Bindable(viewModel)
        self.targetMedia = targetMedia
    }

    var body: some View {
        TaskModalNavigationView {
            fileInfoScrollView
                .taskModalTitle("media.fileInfo.title")
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.close") { dismiss() }
                    }
                }
            #endif
        }
        .task {
            await viewModel.loadFileInfo(for: targetMedia)
        }
    }

    private var fileInfoScrollView: some View {
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
            .frame(maxWidth: MediaFileInfoLayout.maximumContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, MediaFileInfoLayout.outerHorizontalPadding)
            .padding(.vertical, MediaFileInfoLayout.outerVerticalPadding)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func fileInfoContent(_ fileInfo: MediaFileInfo) -> some View {
        LazyVStack(alignment: .leading, spacing: MediaFileInfoLayout.contentSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(targetMedia?.title ?? viewModel.media.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                if let summary = fileInfo.firstVersion?.summaryLabels, !summary.isEmpty {
                    MediaFileInfoFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(Array(summary.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.secondary.opacity(0.14), in: Capsule())
                        }
                    }
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
                Task { await viewModel.loadFileInfo(for: targetMedia, forceReload: true) }
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
        VStack(alignment: .leading, spacing: MediaFileInfoLayout.versionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: versionTitle)
                    .font(.title3.weight(.semibold))

                if let title = version.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if hasGeneralFields {
                infoCard("media.fileInfo.general", systemImage: "doc.text") {
                    infoGrid {
                        field("media.fileInfo.container", version.container?.uppercased())
                        field("media.fileInfo.duration", version.durationText)
                        field("media.fileInfo.size", version.totalSizeText)
                        field("media.fileInfo.bitrate", version.bitrateText)
                        field("media.fileInfo.aspectRatio", version.aspectRatio)
                    }
                }
            }

            if hasVideoFields {
                infoCard("media.fileInfo.video", systemImage: "film") {
                    infoGrid {
                        field("media.fileInfo.resolution", version.resolutionText)
                        field("media.fileInfo.videoCodec", combined(version.videoCodec, version.videoProfile))
                        field("media.fileInfo.frameRate", version.videoFrameRate)
                    }
                }
            }

            if hasAudioFields {
                infoCard("media.fileInfo.audio", systemImage: "waveform") {
                    infoGrid {
                        field("media.fileInfo.audioCodec", combined(version.audioCodec, version.audioProfile))
                        field("media.fileInfo.channels", version.audioChannels.map { "\($0)" })
                    }
                }
            }

            if !version.parts.isEmpty {
                MediaFileInfoDisclosureCard(
                    titleKey: "media.fileInfo.file",
                    systemImage: "doc",
                ) {
                    VStack(alignment: .leading, spacing: MediaFileInfoLayout.partListSpacing) {
                        ForEach(Array(version.parts.enumerated()), id: \.offset) { index, part in
                            MediaFileInfoPartView(index: index, part: part)
                        }
                    }
                }
            }

            if !version.attachments.isEmpty {
                MediaFileInfoDisclosureCard(
                    titleKey: "media.fileInfo.attachments",
                    systemImage: "paperclip",
                ) {
                    VStack(alignment: .leading, spacing: MediaFileInfoLayout.attachmentListSpacing) {
                        ForEach(Array(version.attachments.enumerated()), id: \.offset) { index, attachment in
                            infoGrid {
                                field("media.fileInfo.fileName", attachment.fileName)
                                field("media.fileInfo.codec", attachment.codec)
                                field("media.fileInfo.mimeType", attachment.mimeType)
                            }

                            if index < version.attachments.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var versionTitle: String {
        String(localized: "media.fileInfo.version \(index + 1)")
    }

    private var hasGeneralFields: Bool {
        [
            version.container,
            version.durationText,
            version.totalSizeText,
            version.bitrateText,
            version.aspectRatio,
        ].contains { $0?.isEmpty == false }
    }

    private var hasVideoFields: Bool {
        [
            version.resolutionText,
            combined(version.videoCodec, version.videoProfile),
            version.videoFrameRate,
        ].contains { $0?.isEmpty == false }
    }

    private var hasAudioFields: Bool {
        [
            combined(version.audioCodec, version.audioProfile),
            version.audioChannels.map { "\($0)" },
        ].contains { $0?.isEmpty == false }
    }

    @ViewBuilder
    private func infoCard(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: MediaFileInfoLayout.cardContentSpacing) {
            Label(titleKey, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(MediaFileInfoLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        #if os(tvOS)
            .modifier(TVModalReadingFocus())
        #endif
    }

    private func infoGrid(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: MediaFileInfoLayout.minimumFieldWidth), alignment: .leading)],
            alignment: .leading,
            spacing: MediaFileInfoLayout.gridSpacing,
            content: content,
        )
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
        VStack(alignment: .leading, spacing: MediaFileInfoLayout.subsectionSpacing) {
            Text(verbatim: fileTitle)
                .font(.subheadline.weight(.semibold))

            infoGrid {
                field("media.fileInfo.fileName", part.fileName)
                field("media.fileInfo.path", part.path)
                field("media.fileInfo.size", part.sizeText)
                field("media.fileInfo.container", part.container?.uppercased())
                field("media.fileInfo.duration", part.durationText)
                if let exists = part.exists {
                    field(
                        "media.fileInfo.filePresent",
                        exists ? String(localized: "media.fileInfo.yes") : String(localized: "media.fileInfo.no"),
                    )
                }
                if let accessible = part.accessible {
                    field(
                        "media.fileInfo.fileReadable",
                        accessible ? String(localized: "media.fileInfo.yes") : String(localized: "media.fileInfo.no"),
                    )
                }
                if let id = part.id {
                    field("media.fileInfo.fileId", id)
                }
            }

            VStack(alignment: .leading, spacing: MediaFileInfoLayout.disclosureSpacing) {
                ForEach([MediaFileStreamKind.video, .audio, .subtitle, .other], id: \.self) { kind in
                    let streams = part.streams.filter { $0.kind == kind }
                    if !streams.isEmpty {
                        MediaFileInfoDisclosureCard(
                            titleKey: kind.titleKey,
                            systemImage: kind.systemImage,
                            initiallyExpanded: false,
                            style: .nested,
                        ) {
                            VStack(alignment: .leading, spacing: MediaFileInfoLayout.streamListSpacing) {
                                ForEach(Array(streams.enumerated()), id: \.offset) { _, stream in
                                    MediaFileInfoStreamView(stream: stream)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, MediaFileInfoLayout.partVerticalPadding)
    }

    private var fileTitle: String {
        String(localized: "media.fileInfo.file \(index + 1)")
    }

    private func infoGrid(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: MediaFileInfoLayout.minimumFieldWidth), alignment: .leading)],
            alignment: .leading,
            spacing: MediaFileInfoLayout.gridSpacing,
            content: content,
        )
    }

    @ViewBuilder
    private func field(_ labelKey: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            MediaFileInfoField(label: labelKey, value: value)
        }
    }
}

private struct MediaFileInfoDisclosureCard<Content: View>: View {
    enum Style: Equatable {
        case card
        case nested
    }

    let titleKey: LocalizedStringKey
    let systemImage: String
    let style: Style
    private let content: () -> Content

    @State private var isExpanded: Bool

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        initiallyExpanded: Bool = false,
        style: Style = .card,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.style = style
        self.content = content
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(tvOS)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    disclosureLabel
                }
                .buttonStyle(.plain)

                if isExpanded {
                    content()
                        .padding(.top, MediaFileInfoLayout.disclosureContentPadding)
                }
            #else
                DisclosureGroup(isExpanded: $isExpanded) {
                    content()
                        .padding(.top, MediaFileInfoLayout.disclosureContentPadding)
                } label: {
                    disclosureLabel
                }
            #endif
        }
        .padding(style == .card ? MediaFileInfoLayout.cardPadding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.primary.opacity(0.055))
            }
        }
    }

    private var disclosureLabel: some View {
        HStack(spacing: MediaFileInfoLayout.nestedLabelSpacing) {
            Label(titleKey, systemImage: systemImage)
                .font(style == .card ? .headline : .subheadline.weight(.semibold))

            Spacer(minLength: 8)

            #if os(tvOS)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            #endif
        }
        .contentShape(Rectangle())
        #if os(tvOS)
            .padding(.vertical, style == .nested ? MediaFileInfoLayout.nestedLabelVerticalPadding : 0)
        #endif
    }
}

private struct MediaFileInfoStreamView: View {
    let stream: MediaFileStream

    var body: some View {
        VStack(alignment: .leading, spacing: MediaFileInfoLayout.streamSpacing) {
            Text(stream.headline)
                .font(.callout.weight(.semibold))
                .lineLimit(2)

            if !flagKeys.isEmpty {
                MediaFileInfoFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(flagKeys, id: \.self) { key in
                        Text(LocalizedStringKey(key))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.14), in: Capsule())
                    }
                }
            }

            infoGrid {
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
        }
        .padding(MediaFileInfoLayout.streamPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        #if os(tvOS)
            .modifier(TVModalReadingFocus())
        #endif
    }

    private var flagKeys: [String] {
        [
            stream.isDefault == true ? "media.fileInfo.default" : nil,
            stream.isSelected == true ? "media.fileInfo.selected" : nil,
            stream.isForced == true ? "media.fileInfo.forced" : nil,
            stream.isExternal == true ? "media.fileInfo.external" : nil,
            stream.isHearingImpaired == true ? "media.fileInfo.hearingImpaired" : nil,
        ].compactMap(\.self)
    }

    private func infoGrid(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: MediaFileInfoLayout.minimumFieldWidth), alignment: .leading)],
            alignment: .leading,
            spacing: MediaFileInfoLayout.gridSpacing,
            content: content,
        )
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
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        #else
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Text(value)
                    .font(.callout)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

private struct MediaFileInfoFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    typealias Cache = Void

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Cache,
    ) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        let width = proposal.width ?? rows.map { row in
            row.reduce(CGFloat.zero) { result, item in
                max(result, item.offset + item.size.width)
            }
        }.max() ?? 0
        let height = rows.reduce(CGFloat.zero) { result, row in
            result + (row.map(\.size.height).max() ?? 0)
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Cache,
    ) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                let point = CGPoint(
                    x: bounds.minX + item.offset + item.size.width / 2,
                    y: y + rowHeight / 2,
                )
                subviews[item.index].place(
                    at: point,
                    anchor: .center,
                    proposal: ProposedViewSize(item.size),
                )
            }
            y += rowHeight + verticalSpacing
        }
    }

    private func rows(
        for subviews: Subviews,
        maxWidth: CGFloat,
    ) -> [[FlowItem]] {
        var rows: [[FlowItem]] = []
        var currentRow: [FlowItem] = []
        var currentWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = currentRow.isEmpty ? 0 : horizontalSpacing
            let wouldOverflow = maxWidth.isFinite && currentWidth + spacing + size.width > maxWidth

            if wouldOverflow, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
            }

            let rowSpacing = currentRow.isEmpty ? 0 : horizontalSpacing
            currentRow.append(FlowItem(index: index, offset: currentWidth + rowSpacing, size: size))
            currentWidth += rowSpacing + size.width
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct FlowItem {
        let index: Int
        let offset: CGFloat
        let size: CGSize
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
