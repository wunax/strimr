import SwiftUI

@MainActor
struct SleepTimerPromptOverlay: View {
    let sleepTimer: SleepTimer

    var body: some View {
        PlayerPromptCard {
            details
        } primaryAction: {
            Button {
                sleepTimer.continueAfterPrompt()
            } label: {
                Label("player.sleepTimer.prompt.continue", systemImage: "play.fill")
            }
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: [])
            #endif
        } secondaryAction: {
            Button {
                sleepTimer.pauseNow()
            } label: {
                Label("player.sleepTimer.prompt.pause", systemImage: "pause.fill")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("player.sleepTimer.title", systemImage: "moon.zzz.fill")
                .eyebrowStyle()
                .foregroundStyle(.textSecondary)

            Text("player.sleepTimer.prompt.title")
                .font(.tileTitle)

            if let promptDeadline = sleepTimer.promptDeadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(Int(promptDeadline.timeIntervalSince(context.date).rounded(.up)), 0)
                    Text(String(localized: "player.sleepTimer.prompt.pausingIn \(remaining)"))
                        .font(.facts.weight(.medium))
                        .foregroundStyle(.textSecondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .foregroundStyle(.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SleepTimerBadge: View {
    let sleepTimer: SleepTimer
    var mediaKind: MediaKind?

    var body: some View {
        if let mode = sleepTimer.mode {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                if let deadline = sleepTimer.deadline, deadline > .now {
                    Text(timerInterval: Date.now ... deadline, countsDown: true)
                        .monospacedDigit()
                } else {
                    Text(mode.title(for: mediaKind))
                }
            }
            .playerBadgeStyle()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("player.sleepTimer.title"))
            .accessibilityValue(Text(mode.title(for: mediaKind)))
        }
    }
}
