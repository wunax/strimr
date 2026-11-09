import SwiftUI

struct PlaybackSettingsView: View {
    var playbackRate: Float
    var quality: TranscodeQualityPreset
    var showsQualitySelection: Bool
    var versions: [PlaybackSettingsVersion] = []
    var onSelectVersion: (String) -> Void = { _ in }
    var onSelectPlaybackRate: (Float) -> Void
    var onSelectQuality: (TranscodeQualityPreset) -> Void
    var videoZoom = VideoZoom.fit
    var videoFillScale = 1.0
    var onSelectVideoScaleMode: (PlayerVideoScaleMode) -> Void = { _ in }
    var sleepTimer: SleepTimer?
    var sleepTimerModes: [SleepTimerMode] = []
    var sleepTimerMediaKind: MediaKind?
    var isSleepTimerAvailable = true
    var onSelectSleepTimer: (SleepTimerMode?) -> Void = { _ in }
    @Binding var showsPlaybackStatistics: Bool
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !versions.isEmpty {
                    Section("player.settings.version") {
                        ForEach(versions) { version in
                            TrackSelectionRow(
                                title: version.title,
                                subtitle: version.subtitle,
                                isSelected: version.isSelected,
                            ) {
                                onSelectVersion(version.id)
                            }
                            .disabled(!version.isAvailable)
                        }
                    }
                }

                if showsQualitySelection {
                    Section("player.settings.quality") {
                        Picker(
                            "player.settings.quality",
                            selection: Binding(
                                get: { quality },
                                set: { onSelectQuality($0) },
                            ),
                        ) {
                            ForEach(TranscodeQualityPreset.displayOrder) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Picker(
                        "player.settings.speed",
                        selection: Binding(
                            get: { playbackRate },
                            set: { onSelectPlaybackRate($0) },
                        ),
                    ) {
                        ForEach(PlaybackSpeedOptions.all) { option in
                            Text("player.settings.speed.value \(option.valueText)")
                                .tag(option.rate)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(
                        "player.settings.display",
                        selection: Binding(
                            get: { videoZoom.persistedMode },
                            set: { mode in
                                if let mode {
                                    onSelectVideoScaleMode(mode)
                                }
                            },
                        ),
                    ) {
                        ForEach(PlayerVideoScaleMode.allCases) { mode in
                            Text(mode.feedbackTitle).tag(Optional(mode))
                        }
                        if case .custom = videoZoom {
                            Text(videoZoom.feedbackTitle(fillScale: videoFillScale))
                                .tag(PlayerVideoScaleMode?.none)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let sleepTimer {
                    SleepTimerSettingsSection(
                        sleepTimer: sleepTimer,
                        modes: sleepTimerModes,
                        mediaKind: sleepTimerMediaKind,
                        isAvailable: isSleepTimerAvailable,
                        onSelect: onSelectSleepTimer,
                    )
                }

                Section {
                    Toggle(isOn: $showsPlaybackStatistics) {
                        Label("player.statistics.title", systemImage: "chart.bar.xaxis")
                    }
                } footer: {
                    Text("player.statistics.footer")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("settings.playback.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.actions.done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct SleepTimerSettingsSection: View {
    let sleepTimer: SleepTimer
    let modes: [SleepTimerMode]
    let mediaKind: MediaKind?
    let isAvailable: Bool
    let onSelect: (SleepTimerMode?) -> Void

    var body: some View {
        Section {
            Picker(
                selection: Binding(
                    get: { sleepTimer.mode },
                    set: { onSelect($0) },
                ),
            ) {
                Text("player.sleepTimer.off").tag(SleepTimerMode?.none)
                ForEach(modes, id: \.self) { mode in
                    Text(mode.title(for: mediaKind)).tag(Optional(mode))
                }
            } label: {
                Label("player.sleepTimer.title", systemImage: "moon.zzz")
            }
            .pickerStyle(.menu)
            .disabled(!isAvailable)

            if let deadline = sleepTimer.deadline, deadline > .now {
                LabeledContent("player.sleepTimer.remaining") {
                    Text(timerInterval: Date.now ... deadline, countsDown: true)
                        .monospacedDigit()
                }

                Button {
                    sleepTimer.extend()
                } label: {
                    Label(
                        String(localized: "player.sleepTimer.extend \(SleepTimer.extensionMinutes)"),
                        systemImage: "plus",
                    )
                }
            }

            if sleepTimer.isActive {
                Button("player.sleepTimer.cancel", role: .destructive) {
                    onSelect(nil)
                }
            }
        } footer: {
            if !isAvailable {
                Text("player.sleepTimer.unavailableSharePlay")
            }
        }
    }
}
