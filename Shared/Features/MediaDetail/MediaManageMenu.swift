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

    func perform(
        _ action: MediaQuickAction,
        on item: MediaItem,
        quickActions: MediaQuickActions,
        onAccepted: (() -> Void)? = nil,
    ) {
        guard !isPerforming else { return }
        if action == .editArtwork {
            artworkPicker = quickActions.artworkPicker(for: item)
            return
        }
        if action == .delete {
            deletionItem = item
            return
        }
        isPerforming = true
        Task {
            let outcome: MediaQuickActions.Outcome = switch action {
            case .refreshMetadata: await quickActions.refreshMetadata(item)
            case .analyze: await quickActions.analyze(item)
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
        default:
            nil
        }
    }

    private static func failureTitle(for action: MediaQuickAction) -> String {
        switch action {
        case .analyze: String(localized: "media.manage.analyze.error")
        default: String(localized: "media.manage.refreshMetadata.error")
        }
    }
}

extension MediaQuickAction {
    var role: ButtonRole? {
        self == .delete ? .destructive : nil
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
            .toast($controller.toast)
    }
}
