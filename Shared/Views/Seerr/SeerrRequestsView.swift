import Observation
import SwiftUI

@MainActor
struct SeerrRequestsView: View {
    @State var viewModel: SeerrRequestsViewModel
    let onSelectMedia: (SeerrMedia) -> Void
    @State private var editRequest: SeerrEditRequestState?
    @State private var requestPendingDeletion: SeerrRequest?

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        content
            .navigationTitle("seerr.requests.title")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    optionsMenu
                }
            }
        #elseif os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    optionsMenu
                }
            }
        #endif
            .task(id: viewModel.query) {
                await viewModel.reload()
            }
        #if !os(tvOS)
            .refreshable {
                await viewModel.reload()
            }
        #endif
            .alert("integrations.seerr.error.title", isPresented: $bindableViewModel.isShowingError) {
                Button("common.actions.done") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "seerr.requests.delete.title",
                isPresented: deleteDialogBinding,
                presenting: requestPendingDeletion,
            ) { request in
                Button("seerr.requests.delete.confirm", role: .destructive) {
                    Task { await viewModel.delete(request) }
                }
                Button("common.actions.cancel", role: .cancel) {}
            } message: { _ in
                Text("seerr.requests.delete.message")
            }
        #if os(tvOS)
            .navigationDestination(item: $editRequest) { state in
                SeerrMediaRequestView(viewModel: state.viewModel) {
                    Task { await viewModel.reload() }
                }
            }
        #else
            .sheet(item: $editRequest) { state in
                SeerrMediaRequestSheetView(viewModel: state.viewModel) {
                    Task { await viewModel.reload() }
                }
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
                #endif
            }
        #endif
    }

    private var content: some View {
        ZStack {
            #if os(tvOS)
                Color("Background").ignoresSafeArea()
            #endif

            ScrollView {
                LazyVStack(alignment: .leading, spacing: contentSpacing) {
                    #if os(tvOS)
                        HStack {
                            optionsMenu
                            Spacer()
                        }
                        .focusSection()
                    #endif

                    statusFilterBar

                    if viewModel.isLoading, viewModel.requests.isEmpty {
                        ProgressView("integrations.seerr.discover.loading")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if viewModel.requests.isEmpty, viewModel.hasLoaded {
                        emptyState
                    } else {
                        ForEach(viewModel.requests) { request in
                            SeerrRequestCardView(
                                viewModel: viewModel,
                                request: request,
                                onOpen: { open(request) },
                                onEdit: { edit(request) },
                                onDelete: { requestPendingDeletion = request },
                            )
                            .task {
                                await viewModel.loadMoreIfNeeded(current: request)
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
            }
        }
    }

    private var contentSpacing: CGFloat {
        #if os(tvOS)
            24
        #else
            12
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { requestPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    requestPendingDeletion = nil
                }
            },
        )
    }

    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SeerrRequestStatusFilter.allCases) { filter in
                    let isSelected = viewModel.query.status == filter
                    Button {
                        viewModel.query.status = filter
                    } label: {
                        Text(LocalizedStringKey(filter.titleKey))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        #if !os(tvOS)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(.textPrimary)
                            .background(isSelected ? Color.purple : .surfaceSubtle, in: Capsule())
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .purple : .secondary)
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            #if os(tvOS)
            .padding(.vertical, 8)
            #endif
        }
        .scrollBounceBehavior(.basedOnSize)
        #if os(tvOS)
            .focusSection()
        #endif
    }

    private var optionsMenu: some View {
        Menu {
            Picker("seerr.requests.options.type", selection: $viewModel.query.mediaType) {
                ForEach(SeerrRequestMediaFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.titleKey)).tag(filter)
                }
            }

            Picker("seerr.requests.options.sort", selection: $viewModel.query.sort) {
                ForEach(SeerrRequestSort.allCases) { sort in
                    Text(LocalizedStringKey(sort.titleKey)).tag(sort)
                }
            }

            Toggle("seerr.requests.options.oldestFirst", isOn: $viewModel.query.isAscending)
        } label: {
            #if os(tvOS)
                Label("seerr.requests.options.title", systemImage: optionsIcon)
            #else
                Image(systemName: optionsIcon)
            #endif
        }
        .accessibilityLabel(Text("seerr.requests.options.title"))
    }

    private var optionsIcon: String {
        let isFiltered = viewModel.query.mediaType != .all
            || viewModel.query.sort != .added
            || viewModel.query.isAscending
        return isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.textSecondary)
            Text("seerr.requests.empty")
                .font(.headline)
            Text("seerr.requests.empty.description")
                .font(.subheadline)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func open(_ request: SeerrRequest) {
        guard let media = viewModel.openableMedia(for: request) else { return }
        onSelectMedia(media)
    }

    private func edit(_ request: SeerrRequest) {
        Task {
            guard let editViewModel = await viewModel.makeEditViewModel(for: request) else { return }
            editRequest = SeerrEditRequestState(viewModel: editViewModel)
        }
    }
}

struct SeerrEditRequestState: Identifiable, Hashable {
    let id = UUID()
    let viewModel: SeerrMediaRequestViewModel

    static func == (lhs: SeerrEditRequestState, rhs: SeerrEditRequestState) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
