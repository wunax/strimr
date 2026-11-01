import Observation
import SwiftUI

/// Runs the Manage actions of a library. Each one covers the whole library and can take long, so it is confirmed
/// first, and a success only means the server accepted it.
@MainActor
@Observable
final class LibraryManageController {
    struct Request: Identifiable {
        let id = UUID()
        let action: LibraryManageAction
        let library: Library
    }

    enum Prompt: Identifiable {
        case confirmation(Request)
        case notice(MediaManageController.Notice)

        var id: UUID {
            switch self {
            case let .confirmation(request): request.id
            case let .notice(notice): notice.id
            }
        }
    }

    private(set) var isPerforming = false
    var prompt: Prompt?
    /// The library whose actions the tvOS dialog lists.
    var dialogLibrary: Library?

    func request(_ action: LibraryManageAction, on library: Library) {
        prompt = .confirmation(Request(action: action, library: library))
    }

    func perform(_ request: Request, actions: LibraryManageActions) {
        guard !isPerforming else { return }
        isPerforming = true
        Task {
            let outcome = await actions.perform(request.action, on: request.library)
            isPerforming = false
            switch outcome {
            case .succeeded:
                prompt = .notice(MediaManageController.Notice(
                    title: request.action.startedTitle,
                    message: request.action.startedMessage,
                ))
            case let .failed(message):
                prompt = .notice(MediaManageController.Notice(title: request.action.failureTitle, message: message))
            case .cancelled:
                break
            }
        }
    }
}

/// The actions of a library, each asking for confirmation, for a menu that already groups them.
struct LibraryManageMenuItems: View {
    let library: Library
    let actions: LibraryManageActions
    let controller: LibraryManageController

    var body: some View {
        ForEach(actions.actions(for: library), id: \.self) { action in
            Button {
                controller.request(action, on: library)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .disabled(controller.isPerforming)
        }
    }
}

/// The Manage entry of a library's menu. tvOS menus handle nested menus poorly, so there it opens a dialog instead,
/// presented by `libraryManagePresentation`.
struct LibraryManageMenu: View {
    let library: Library
    let actions: LibraryManageActions
    let controller: LibraryManageController

    var body: some View {
        #if os(tvOS)
            Button {
                controller.dialogLibrary = library
            } label: {
                Label(MediaQuickAction.manage.title, systemImage: MediaQuickAction.manage.systemImage)
            }
            .disabled(controller.isPerforming)
        #else
            Menu {
                LibraryManageMenuItems(library: library, actions: actions, controller: controller)
            } label: {
                Label(MediaQuickAction.manage.title, systemImage: MediaQuickAction.manage.systemImage)
            }
            .disabled(controller.isPerforming)
        #endif
    }
}

extension View {
    /// `actions` resolves the actions of a library's server, nil when it is not connected.
    func libraryManagePresentation(
        _ controller: LibraryManageController,
        actions: @escaping (Library) -> LibraryManageActions?,
    ) -> some View {
        modifier(LibraryManagePresentation(controller: controller, actions: actions))
    }
}

private struct LibraryManagePresentation: ViewModifier {
    @Bindable var controller: LibraryManageController
    let actions: (Library) -> LibraryManageActions?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                MediaQuickAction.manage.title,
                isPresented: Binding(
                    get: { controller.dialogLibrary != nil },
                    set: {
                        if !$0 {
                            controller.dialogLibrary = nil
                        }
                    },
                ),
                presenting: controller.dialogLibrary,
            ) { library in
                ForEach(actions(library)?.actions(for: library) ?? [], id: \.self) { action in
                    Button(action.title) {
                        controller.request(action, on: library)
                    }
                }
                Button("common.actions.cancel", role: .cancel) {}
            }
            .alert(item: $controller.prompt) { prompt in
                switch prompt {
                case let .confirmation(request):
                    Alert(
                        title: Text(request.action.title),
                        message: Text(request.action.confirmationMessage(for: request.library)),
                        primaryButton: .default(Text(request.action.title)) {
                            guard let actions = actions(request.library) else { return }
                            controller.perform(request, actions: actions)
                        },
                        secondaryButton: .cancel(),
                    )
                case let .notice(notice):
                    Alert(
                        title: Text(notice.title),
                        message: Text(notice.message),
                        dismissButton: .default(Text("common.actions.done")),
                    )
                }
            }
    }
}
