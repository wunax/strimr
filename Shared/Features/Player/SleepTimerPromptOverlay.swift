import SwiftUI

@MainActor
struct SleepTimerPromptOverlay: View {
    let sleepTimer: SleepTimer

    @FocusState private var focusedAction: Action?

    private enum Action: Hashable {
        case continueWatching
        case pause
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            #if os(tvOS)
                tvLayout
            #elseif os(macOS)
                macLayout
            #else
                mobileLayout
            #endif
        }
        .zIndex(100)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("player.sleepTimer.title", systemImage: "moon.zzz.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("player.sleepTimer.prompt.title")
                .font(.title2.weight(.bold))

            if let promptDeadline = sleepTimer.promptDeadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(Int(promptDeadline.timeIntervalSince(context.date).rounded(.up)), 0)
                    Text(String(localized: "player.sleepTimer.prompt.pausingIn \(remaining)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                sleepTimer.continueAfterPrompt()
            } label: {
                Label("player.sleepTimer.prompt.continue", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            #if os(tvOS)
                .focused($focusedAction, equals: .continueWatching)
            #endif
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: [])
            #endif

            Button {
                sleepTimer.pauseNow()
            } label: {
                Label("player.sleepTimer.prompt.pause", systemImage: "pause.fill")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            #if os(tvOS)
                .focused($focusedAction, equals: .pause)
            #endif
        }
        .frame(maxWidth: .infinity)
        #if os(tvOS)
            .onMoveCommand { direction in
                switch direction {
                case .left where focusedAction == .pause:
                    focusedAction = .continueWatching
                case .right where focusedAction == .continueWatching:
                    focusedAction = .pause
                case .left, .right, .up, .down:
                    focusedAction = focusedAction ?? .continueWatching
                default:
                    break
                }
            }
        #endif
    }

    private var mobileLayout: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                details
                actions
            }
            .padding(20)
            .frame(maxWidth: 520)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tvLayout: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                details
                actions
            }
            .padding(30)
            .frame(maxWidth: 800)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 60)
            .padding(.bottom, 48)
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedAction = .continueWatching
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var macLayout: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                details
                actions
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.15), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("player.sleepTimer.title"))
            .accessibilityValue(Text(mode.title(for: mediaKind)))
        }
    }
}
