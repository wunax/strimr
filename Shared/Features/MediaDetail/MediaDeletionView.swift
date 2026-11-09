import SwiftUI

/// Confirms the deletion of a media from the server, with what it removes from the server's disk.
struct MediaDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @State var viewModel: MediaDeletionViewModel
    var onDeleted: (() -> Void)?
    #if os(iOS)
        @State private var contentHeight: CGFloat = 0
        /// The navigation bar and the bottom safe area, which the sheet height includes.
        @State private var chromeHeight: CGFloat = 0
    #endif

    var body: some View {
        TaskModalNavigationView {
            titledContent
                .taskModalActions {
                    Button(role: .destructive, action: delete) {
                        Text("media.manage.delete.confirm")
                    }
                    .disabled(!viewModel.canDelete)
                } actions: {
                    Button("common.actions.cancel") { dismiss() }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 140)
        #endif
        #if os(iOS)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + chromeHeight)] : [.medium])
        #endif
        .interactiveDismissDisabled(isDeleting)
        .task {
            await viewModel.load()
        }
    }

    private var title: String {
        String(localized: "media.manage.delete.confirmation.title \(viewModel.item.title)")
    }

    /// On iOS the title sits in the body, where a long one wraps instead of being cut by the toolbar buttons, and the
    /// sheet is only as tall as the body and the toolbar above it.
    private var titledContent: some View {
        #if os(iOS)
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: {
                    chromeHeight = $0
                }
                .toolbarTitleDisplayMode(.inline)
        #else
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .taskModalTitle(verbatim: title)
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(iOS)
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
            #endif
            switch viewModel.state {
            case .loading, .deleted:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.bodyText)
                    .foregroundStyle(.textPrimary)
            case .ready, .deleting:
                if let impact = viewModel.impact {
                    Text("media.manage.delete.confirmation.message \(impact.summary)")
                        .font(.bodyText)
                        .foregroundStyle(.textPrimary)
                }
                if isDeleting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
    }

    private var isDeleting: Bool {
        if case .deleting = viewModel.state {
            return true
        }
        return false
    }

    /// The toast center is read first: once the item is deleted, the view that presented this one can go away.
    private func delete() {
        let toasts = toasts
        let title = viewModel.item.title
        Task {
            await viewModel.delete()
            guard viewModel.state == .deleted else { return }
            toasts?.show(Toast(
                style: .success,
                title: String(localized: "media.manage.delete.done \(title)"),
            ))
            onDeleted?()
            dismiss()
        }
    }
}
