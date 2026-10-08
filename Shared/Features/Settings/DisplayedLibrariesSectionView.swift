import SwiftUI

@MainActor
struct DisplayedLibrariesSectionView: View {
    @State private var viewModel: DisplayedLibrariesViewModel

    init(settingsManager: SettingsManager, libraryStore: LibraryStore) {
        _viewModel = State(
            initialValue: DisplayedLibrariesViewModel(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            ),
        )
    }

    var body: some View {
        Section {
            rows
        } header: {
            Text("settings.interface.displayedLibraries")
        }
        .task {
            await viewModel.loadLibraries()
        }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.isLoading, viewModel.libraries.isEmpty {
            ProgressView()
        } else if viewModel.libraries.isEmpty {
            Text("settings.interface.displayedLibraries.empty")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(viewModel.libraries.enumerated()), id: \.element.identity) { index, library in
                LibraryOrderRow(
                    title: library.title,
                    subtitle: viewModel.subtitle(for: library),
                    isOn: viewModel.displayedBinding(for: library),
                    key: "displayed-library-\(library.identity.stableKey)",
                    canMoveUp: index > 0,
                    canMoveDown: index < viewModel.libraries.count - 1,
                ) { offset in
                    viewModel.moveLibrary(at: index, by: offset)
                }
            }
        }
    }
}

/// Library name with its server underneath when the profile has several servers.
struct LibrarySettingsLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Library toggle with the same up/down arrows as the home rows settings.
struct LibraryOrderRow: View {
    let title: String
    let subtitle: String?
    let isOn: Binding<Bool>
    let key: String
    var canReorder = true
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: isOn) {
                    LibrarySettingsLabel(title: title, subtitle: subtitle)
                        .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
                }
                .settingsFocus(key)

                if canReorder {
                    HStack(spacing: 12) {
                        Button {
                            move(-1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("settings.interface.homeRows.moveUp"))
                        .settingsFocus("\(key)-up")
                        .disabled(!canMoveUp)

                        Button {
                            move(1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("settings.interface.homeRows.moveDown"))
                        .settingsFocus("\(key)-down", exitsLeft: false)
                        .disabled(!canMoveDown)
                    }
                }
            }
        #else
            HStack(spacing: 12) {
                Toggle(isOn: isOn) {
                    LibrarySettingsLabel(title: title, subtitle: subtitle)
                        .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
                }

                // Hidden rather than removed so every toggle stays aligned.
                Group {
                    Button {
                        move(-1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .accessibilityLabel(Text("settings.interface.homeRows.moveUp"))
                    .disabled(!canMoveUp)

                    Button {
                        move(1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .accessibilityLabel(Text("settings.interface.homeRows.moveDown"))
                    .disabled(!canMoveDown)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(canReorder ? 1 : 0)
                .disabled(!canReorder)
                .accessibilityHidden(!canReorder)
            }
            .id(key)
        #endif
    }
}
