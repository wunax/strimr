import SwiftUI

struct LiveTVWhatsOnView: View {
    @Bindable var store: LiveTVStore
    let onOpenProgram: (LiveTVProgram) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
        @FocusState private var focusedProgram: LiveTVProgramIdentity?
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if store.onNowSections.isEmpty {
                    LiveTVEmptyState("livetv.empty.onNow", systemImage: "clock", message: store.errorMessage)
                }
                ForEach(store.onNowSections) { row in
                    VStack(alignment: .leading) {
                        Text(row.title)
                            .font(.sectionTitle)
                            .foregroundStyle(.textPrimary)
                        ScrollView(.horizontal) {
                            LazyHStack {
                                ForEach(row.programs, id: \.identity) { program in
                                    #if os(tvOS)
                                        let isFocused = focusedProgram == program.identity
                                    #else
                                        let isFocused = false
                                    #endif
                                    Group {
                                        #if os(tvOS)
                                            onNowProgramCard(program, isFocused: isFocused)
                                                .focusable()
                                                .focused($focusedProgram, equals: program.identity)
                                                .onTapGesture { onOpenProgram(program) }
                                                .accessibilityAddTraits(.isButton)
                                        #else
                                            Button { onOpenProgram(program) } label: {
                                                onNowProgramCard(program, isFocused: false)
                                            }
                                            .buttonStyle(.cardLift)
                                        #endif
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(
                                        Text(
                                            "livetv.onNow.program.accessibility \(program.title) \(channelName(program.channelIdentity))",
                                        ),
                                    )
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            .padding()
        }
    }

    private func onNowProgramCard(_ program: LiveTVProgram, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            Group {
                if let artworkPath = program.artPath ?? program.thumbPath {
                    ArtworkPathView(
                        path: artworkPath,
                        width: 480,
                        height: 270,
                    )
                } else {
                    MediaArtworkPlaceholder(mediaKind: .episode)
                }
            }
            .frame(width: 240, height: 135)
            .mediaArtworkStyle(.compact)
            .cardFocusStyle(isFocused: isFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text(program.title)
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text(channelName(program.channelIdentity))
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            // Follows the bottom edge of the focused artwork so the lifted card does not cover its caption.
            .offset(y: isFocused && !reduceMotion ? 135 * (CardFocusStyle.focusedScale - 1) / 2 : 0)
            .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
        }
        .frame(width: 240, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func channelName(_ identity: LiveTVChannelIdentity) -> String {
        store.channels.first { $0.identity == identity }?.displayTitle ?? ""
    }
}
