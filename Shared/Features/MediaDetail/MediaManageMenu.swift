import Observation
import SwiftUI

/// Runs the Manage actions of the card and detail menus. The server applies most of them in the background, so a
/// success only means it accepted them, which the toast says. A deletion opens its confirmation right away, since a
/// view that held a context menu cannot present one once the server has answered.
@MainActor
@Observable
final class MediaManageController {
    private(set) var isPerforming = false
    var toast: Toast?
    /// The media whose actions the tvOS dialog lists.
    var dialogMedia: MediaItem?
    var artworkPicker: ArtworkPickerViewModel?
    var deletionItem: MediaItem?
    var matchSearch: MatchSearchViewModel?
    /// The media whose unmatch waits for a confirmation.
    var pendingUnmatch: MediaItem?

    func perform(
        _ action: MediaQuickAction,
        on item: MediaItem,
        quickActions: MediaQuickActions,
        onAccepted: (() -> Void)? = nil,
    ) {
        guard !isPerforming else { return }
        switch action {
        case .editArtwork:
            artworkPicker = quickActions.artworkPicker(for: item)
        case .delete:
            deletionItem = item
        case .fixMatch, .identify:
            matchSearch = quickActions.matchSearch(for: item)
        case .unmatch:
            pendingUnmatch = item
        default:
            run(action, on: item, quickActions: quickActions, onAccepted: onAccepted)
        }
    }

    func unmatch(_ item: MediaItem, quickActions: MediaQuickActions, onAccepted: (() -> Void)?) {
        guard !isPerforming else { return }
        run(.unmatch, on: item, quickActions: quickActions, onAccepted: onAccepted)
    }

    private func run(
        _ action: MediaQuickAction,
        on item: MediaItem,
        quickActions: MediaQuickActions,
        onAccepted: (() -> Void)?,
    ) {
        isPerforming = true
        Task {
            let outcome: MediaQuickActions.Outcome = switch action {
            case .refreshMetadata: await quickActions.refreshMetadata(item)
            case .analyze: await quickActions.analyze(item)
            case .unmatch: await quickActions.unmatch(item)
            default: .cancelled
            }
            isPerforming = false
            switch outcome {
            case .succeeded:
                toast = Self.acceptedToast(for: action)
                onAccepted?()
            case let .failed(message):
                toast = Toast(style: .failure, title: Self.failureTitle(for: action), message: message)
            case .cancelled:
                break
            }
        }
    }

    private static func acceptedToast(for action: MediaQuickAction) -> Toast? {
        switch action {
        case .refreshMetadata:
            Toast(
                style: .success,
                title: String(localized: "media.manage.refreshMetadata.started"),
                message: String(localized: "media.manage.refreshMetadata.startedMessage"),
            )
        case .analyze:
            Toast(
                style: .success,
                title: String(localized: "media.manage.analyze.started"),
                message: String(localized: "media.manage.analyze.startedMessage"),
            )
        case .unmatch:
            Toast(
                style: .success,
                title: String(localized: "media.manage.unmatch.done"),
                message: String(localized: "media.manage.unmatch.doneMessage"),
            )
        default:
            nil
        }
    }

    private static func failureTitle(for action: MediaQuickAction) -> String {
        switch action {
        case .analyze: String(localized: "media.manage.analyze.error")
        case .unmatch: String(localized: "media.manage.unmatch.error")
        default: String(localized: "media.manage.refreshMetadata.error")
        }
    }
}

extension MediaQuickAction {
    var role: ButtonRole? {
        self == .delete || self == .unmatch ? .destructive : nil
    }
}

/// The Manage entry of a menu. tvOS menus handle nested menus poorly, so there it opens a dialog instead, presented
/// by `mediaManagePresentation`.
struct MediaManageMenu: View {
    let item: MediaItem
    let quickActions: MediaQuickActions
    let controller: MediaManageController
    var onAccepted: (() -> Void)?

    var body: some View {
        #if os(tvOS)
            Button {
                controller.dialogMedia = item
            } label: {
                Label(MediaQuickAction.manage.title, systemImage: MediaQuickAction.manage.systemImage)
            }
            .disabled(controller.isPerforming)
        #else
            Menu {
                ForEach(quickActions.manageActions(for: item), id: \.self) { action in
                    Button(role: action.role) {
                        controller.perform(action, on: item, quickActions: quickActions, onAccepted: onAccepted)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } label: {
                Label(MediaQuickAction.manage.title, systemImage: MediaQuickAction.manage.systemImage)
            }
            .disabled(controller.isPerforming)
        #endif
    }
}

extension View {
    /// `onArtworkChanged` runs once the artwork screen closes after a change, `onDeleted` once an item was deleted.
    func mediaManagePresentation(
        _ controller: MediaManageController,
        quickActions: MediaQuickActions,
        onArtworkChanged: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil,
        onAccepted: (() -> Void)? = nil,
    ) -> some View {
        modifier(MediaManagePresentation(
            controller: controller,
            quickActions: quickActions,
            onArtworkChanged: onArtworkChanged,
            onDeleted: onDeleted,
            onAccepted: onAccepted,
        ))
    }
}

private struct MediaManagePresentation: ViewModifier {
    @Bindable var controller: MediaManageController
    let quickActions: MediaQuickActions
    let onArtworkChanged: (() -> Void)?
    let onDeleted: (() -> Void)?
    let onAccepted: (() -> Void)?
    @State private var hasArtworkChanged = false
    @State private var hasMatchChanged = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                MediaQuickAction.manage.title,
                isPresented: Binding(
                    get: { controller.dialogMedia != nil },
                    set: {
                        if !$0 {
                            controller.dialogMedia = nil
                        }
                    },
                ),
                presenting: controller.dialogMedia,
            ) { item in
                ForEach(quickActions.manageActions(for: item), id: \.self) { action in
                    Button(action.title, role: action.role) {
                        controller.perform(action, on: item, quickActions: quickActions, onAccepted: onAccepted)
                    }
                }
                Button("common.actions.cancel", role: .cancel) {}
            }
            .taskPresentation(item: $controller.artworkPicker) {
                if hasArtworkChanged {
                    hasArtworkChanged = false
                    onArtworkChanged?()
                }
            } content: { picker in
                ArtworkPickerView(viewModel: picker)
                    .onChange(of: picker.changeCount) { hasArtworkChanged = true }
            }
            .taskPresentation(item: $controller.deletionItem, style: .dialog) { item in
                MediaDeletionView(
                    viewModel: MediaDeletionViewModel(item: item, quickActions: quickActions),
                    onDeleted: onDeleted,
                )
            }
            .taskPresentation(item: $controller.matchSearch) {
                guard hasMatchChanged else { return }
                hasMatchChanged = false
                onAccepted?()
            } content: { search in
                MatchSearchFlow(
                    search: search,
                    title: matchTitle(for: search.item),
                    makeArtworkPicker: quickActions.manageActions(for: search.item).contains(.editArtwork)
                        ? { quickActions.artworkPicker(for: search.item) }
                        : nil,
                ) {
                    hasMatchChanged = true
                }
            }
            .alert(
                "media.manage.unmatch.confirmTitle",
                isPresented: Binding(
                    get: { controller.pendingUnmatch != nil },
                    set: {
                        if !$0 {
                            controller.pendingUnmatch = nil
                        }
                    },
                ),
                presenting: controller.pendingUnmatch,
            ) { item in
                Button("media.manage.unmatch", role: .destructive) {
                    controller.unmatch(item, quickActions: quickActions, onAccepted: onAccepted)
                }
                Button("common.actions.cancel", role: .cancel) {}
            } message: { _ in
                Text("media.manage.unmatch.confirmMessage")
            }
            .toast($controller.toast)
    }

    private func matchTitle(for item: MediaItem) -> String {
        let action = quickActions.manageActions(for: item).first { $0 == .fixMatch || $0 == .identify }
        return (action ?? .identify).title
    }
}

/// The match search, then the artwork picker in the same presentation when the user wants a new poster for the new
/// match: presenting it once the search closed could fail when the view that opened the search is gone.
private struct MatchSearchFlow: View {
    let search: MatchSearchViewModel
    let title: String
    let makeArtworkPicker: (() -> ArtworkPickerViewModel?)?
    /// Runs after the match or the artwork changed.
    let onChange: () -> Void
    @State private var artworkPicker: ArtworkPickerViewModel?

    var body: some View {
        if let artworkPicker {
            ArtworkPickerView(viewModel: artworkPicker)
                .onChange(of: artworkPicker.changeCount) { onChange() }
        } else {
            MatchSearchView(
                viewModel: search,
                title: title,
                onChoosePoster: makeArtworkPicker.map { make in { artworkPicker = make() } },
            )
            .onChange(of: search.appliedCandidate) {
                if search.appliedCandidate != nil {
                    onChange()
                }
            }
        }
    }
}
