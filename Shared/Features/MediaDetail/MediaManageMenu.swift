import Observation
import SwiftUI

/// Runs the Manage actions of the card and detail menus. The server applies them in the background, so a success
/// only means it accepted them, which the notice says.
@MainActor
@Observable
final class MediaManageController {
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private(set) var isPerforming = false
    var notice: Notice?
    /// The media whose actions the tvOS dialog lists.
    var dialogMedia: MediaItem?
    var artworkPicker: ArtworkPickerViewModel?

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
                notice = Self.acceptedNotice(for: action)
                onAccepted?()
            case let .failed(message):
                notice = Notice(title: Self.failureTitle(for: action), message: message)
            case .cancelled:
                break
            }
        }
    }

    private static func acceptedNotice(for action: MediaQuickAction) -> Notice? {
        switch action {
        case .refreshMetadata:
            Notice(
                title: String(localized: "media.manage.refreshMetadata.started"),
                message: String(localized: "media.manage.refreshMetadata.startedMessage"),
            )
        case .analyze:
            Notice(
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
                    Button {
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
    /// `onArtworkChanged` runs once the artwork screen closes after a change.
    func mediaManagePresentation(
        _ controller: MediaManageController,
        quickActions: MediaQuickActions,
        onArtworkChanged: (() -> Void)? = nil,
        onAccepted: (() -> Void)? = nil,
    ) -> some View {
        modifier(MediaManagePresentation(
            controller: controller,
            quickActions: quickActions,
            onArtworkChanged: onArtworkChanged,
            onAccepted: onAccepted,
        ))
    }
}

private struct MediaManagePresentation: ViewModifier {
    @Bindable var controller: MediaManageController
    let quickActions: MediaQuickActions
    let onArtworkChanged: (() -> Void)?
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
                    Button(action.title) {
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
            .alert(item: $controller.notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("common.actions.done")),
                )
            }
    }
}
