import Observation
import SwiftUI

struct SeerrCollectionSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    let onSelectMedia: (SeerrMedia) -> Void
    @State private var isConfirmingRequest = false

    var body: some View {
        if let collection = viewModel.collection, let parts = collection.parts, parts.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                MediaHubSection(title: collection.name ?? String(localized: "seerr.detail.collection")) {
                    SeerrMediaCarousel(
                        items: parts,
                        showsLabels: true,
                        onSelectMedia: onSelectMedia,
                    )
                }

                requestAllButton

                if let message = viewModel.collectionErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.facts)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, LayoutMetrics.detailSectionMargin)
            .environment(\.railPageMargin, LayoutMetrics.detailSectionMargin)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var requestAllButton: some View {
        let parts = viewModel.collectionRequestableParts
        if !parts.isEmpty {
            Button {
                isConfirmingRequest = true
            } label: {
                Label {
                    Text("seerr.collection.requestAll \(parts.count)")
                } icon: {
                    if viewModel.isRequestingCollection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
            }
            .actionButtonStyle(.secondary)
            .disabled(viewModel.isRequestingCollection)
            .confirmationDialog(
                "seerr.collection.requestAll.confirmTitle",
                isPresented: $isConfirmingRequest,
                titleVisibility: .visible,
            ) {
                Button("seerr.request.action.submit") {
                    Task { await viewModel.requestCollection() }
                }
                Button("common.actions.cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage(for: parts))
            }
        }
    }

    private func confirmationMessage(for parts: [SeerrMedia]) -> String {
        var lines = parts.map { $0.title ?? $0.name ?? "" }
        if viewModel.isCollectionLimitedByQuota {
            lines.append(String(localized: "seerr.collection.quotaLimited \(viewModel.collectionQuotaRemaining)"))
        }
        return lines.joined(separator: "\n")
    }
}
