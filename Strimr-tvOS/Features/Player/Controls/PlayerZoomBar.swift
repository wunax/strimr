import SwiftUI

/// Steps the video zoom over the playing picture, so each step shows its framing right away.
struct PlayerZoomBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let controller: PlayerController
    let fillScale: Double
    let resetZoom: VideoZoom
    let onDone: () -> Void

    @FocusState private var focusedControl: PlaybackOffsetControl?

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 32) {
                Label("player.settings.display.zoom", systemImage: zoom.feedbackSystemImage)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                PlaybackOffsetResetButton(isEnabled: zoom != resetZoom) {
                    select(resetZoom)
                }
                .focused($focusedControl, equals: .reset)
                Button(action: onDone) {
                    Text("common.actions.done")
                        .foregroundStyle(.foreground)
                }
                .fontWeight(.semibold)
            }
            .focusSection()

            HStack(spacing: 20) {
                stepButton(direction: -1)
                valueView
                stepButton(direction: 1)
            }
            .focusSection()
        }
        .fixedSize()
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .videoOverlayGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear {
            DispatchQueue.main.async { focusedControl = .fineIncrease }
        }
    }

    private var zoom: VideoZoom {
        controller.videoZoom
    }

    private var scale: Double {
        zoom.scale(fillScale: fillScale)
    }

    private var valueView: some View {
        VStack(spacing: 2) {
            Text(zoom.feedbackTitle(fillScale: fillScale))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            // Fit and fill are named, so their scale goes underneath; kept when empty so the buttons do not jump.
            Text(zoom.persistedMode == nil ? " " : VideoZoom.percentText(scale: scale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("player.settings.display.zoom"))
        .accessibilityValue(zoom.feedbackTitle(fillScale: fillScale))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    private func stepButton(direction: Int) -> some View {
        let next = zoom.stepped(by: direction, fillScale: fillScale)
        return PlaybackOffsetStepButton(
            title: direction > 0 ? "+" : "−",
            accessibilityLabel: String(
                localized: direction > 0 ? "player.settings.display.zoomIn" : "player.settings.display.zoomOut",
            ),
            accessibilityValue: next.feedbackTitle(fillScale: fillScale),
            isEnabled: next != zoom,
            action: { step(by: direction) },
        )
        .focused($focusedControl, equals: direction > 0 ? .fineIncrease : .fineDecrease)
    }

    /// Reads the controller rather than `zoom`, since a held button keeps calling the action it started with.
    private func step(by direction: Int) {
        select(controller.videoZoom.stepped(by: direction, fillScale: fillScale))
    }

    private func select(_ zoom: VideoZoom) {
        withAnimation(Motion.animation(Motion.focus, reduceMotion: reduceMotion)) {
            controller.setVideoZoom(zoom)
        }
    }
}
