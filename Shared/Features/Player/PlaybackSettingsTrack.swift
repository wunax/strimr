import SwiftUI

struct PlaybackSettingsTrack: Identifiable, Hashable {
    let track: PlayerTrack
    let plexStream: PlexPartStream?

    var id: Int {
        track.id
    }

    private var plexCodec: String? {
        plexStream?.codec.uppercased()
    }

    var title: String {
        guard plexStream != nil else { return track.displayName }

        if let plexDisplayTitle = plexStream?.displayTitle, !plexDisplayTitle.isEmpty {
            switch track.type {
            case .subtitle:
                if let plexCodec {
                    return "\(plexDisplayTitle) (\(plexCodec))"
                }
                return plexDisplayTitle
            default:
                return plexDisplayTitle
            }
        }

        return track.displayName
    }

    var subtitle: String? {
        guard plexStream != nil else { return track.codec?.uppercased() }

        if let plexTitle = plexStream?.title, !plexTitle.isEmpty {
            return plexTitle
        }

        return plexCodec ?? track.codec?.uppercased()
    }
}

struct TrackSelectionRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
