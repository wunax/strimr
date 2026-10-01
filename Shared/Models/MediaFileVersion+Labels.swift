import Foundation

extension MediaFileVersion {
    /// Row title, e.g. `4K · Dolby Vision · HEVC`. Server titles are only used when they tell versions apart.
    func displayLabel(among versions: [MediaFileVersion]) -> String {
        let labels = Self.displayLabels(for: versions)
        if let index = versions.firstIndex(of: self) {
            return labels[index]
        }
        return baseLabel(usesTitle: false)
    }

    static func displayLabels(for versions: [MediaFileVersion]) -> [String] {
        let usesTitles = hasDistinctTitles(versions)
        var labels = versions.map { $0.baseLabel(usesTitle: usesTitles) }
        labels = disambiguate(labels, versions: versions, with: \.totalSizeText)
        labels = disambiguate(labels, versions: versions, with: \.fileName)
        return labels
    }

    /// Row subtitle: main audio, size, bitrate, then file name, which often carries "Director's Cut" or "VF".
    var detailLabel: String {
        [audioLabel, totalSizeText, bitrateText, fileName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    /// Compact label for buttons, e.g. `4K DV` or `1080p`.
    var shortLabel: String {
        let components = [resolutionLabel, shortDynamicRangeLabel].compactMap(\.self)
        if components.isEmpty {
            return technicalLabel
        }
        return components.joined(separator: " ")
    }

    var technicalLabel: String {
        let components = [resolutionLabel, dynamicRangeLabel, videoCodecLabel].compactMap(\.self)
        if components.isEmpty {
            return container?.uppercased() ?? String(localized: "media.versions.title")
        }
        return components.joined(separator: " · ")
    }

    var fileName: String? {
        parts.lazy.compactMap(\.fileName).first
    }

    private var trimmedTitle: String? {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func baseLabel(usesTitle: Bool) -> String {
        let label = usesTitle ? trimmedTitle ?? technicalLabel : technicalLabel
        guard isOptimized else { return label }
        var prefix = String(localized: "media.versions.optimized")
        if let target = optimizationTarget?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
            prefix += " (\(target))"
        }
        return "\(prefix) · \(label)"
    }

    private static func hasDistinctTitles(_ versions: [MediaFileVersion]) -> Bool {
        Set(versions.compactMap(\.trimmedTitle)).count >= 2
    }

    private static func disambiguate(
        _ labels: [String],
        versions: [MediaFileVersion],
        with suffix: KeyPath<MediaFileVersion, String?>,
    ) -> [String] {
        let counts = Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
        return zip(labels, versions).map { label, version in
            guard counts[label, default: 0] > 1,
                  let value = version[keyPath: suffix],
                  !value.isEmpty
            else { return label }
            return "\(label) · \(value)"
        }
    }

    private var resolutionLabel: String? {
        guard let tier = Int(signatureComponents.height) else { return nil }
        switch tier {
        case 4320: return "8K"
        case 2160: return "4K"
        default: return "\(tier)p"
        }
    }

    private var dynamicRangeLabel: String? {
        guard let range = primaryVideoStream?.dynamicRange, !range.isEmpty else { return nil }
        return range
    }

    private var shortDynamicRangeLabel: String? {
        switch signatureComponents.dynamicRange {
        case "dv": "DV"
        case "hdr10", "hdr10+": "HDR"
        case "hlg": "HLG"
        default: nil
        }
    }

    private var videoCodecLabel: String? {
        switch signatureComponents.videoCodec {
        case "": nil
        case "h264": "H.264"
        case "hevc": "HEVC"
        case let codec: codec.uppercased()
        }
    }

    private var audioLabel: String? {
        let audio = primaryAudioStream
        let codec: String? = switch (audioCodec ?? audio?.codec)?.lowercased() {
        case nil, "": nil
        case "truehd": "TrueHD"
        case "eac3": "E-AC-3"
        case "ac3": "AC-3"
        case "dca", "dts": "DTS"
        case "flac": "FLAC"
        case "aac": "AAC"
        case "opus": "Opus"
        case let value?: value.uppercased()
        }
        let channels = (audioChannels ?? audio?.channels).map(Self.channelLabel)
        let components = [codec, audio?.spatialFormat, channels].compactMap(\.self)
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    private nonisolated static func channelLabel(_ channels: Int) -> String {
        switch channels {
        case 1: "1.0"
        case 2: "2.0"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels)ch"
        }
    }
}
