import Observation
import SwiftUI

@MainActor
struct SeerrMediaRequestTVView: View {
    @Bindable var viewModel: SeerrMediaRequestViewModel
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle(LocalizedStringKey(viewModel.sheetTitleKey))
            .alert("integrations.seerr.error.title", isPresented: $viewModel.isShowingError) {
                Button("common.actions.done") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.didComplete) { _, didComplete in
                guard didComplete else { return }
                onComplete()
                dismiss()
            }
            .task(id: viewModel.selectedRequestType) {
                await viewModel.loadServiceOptionsIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.requiresRequestTypeSelection, viewModel.selectedRequestType == nil {
            requestTypeSelection
        } else {
            requestForm
        }
    }

    private var requestTypeSelection: some View {
        List {
            Section("seerr.request.type.title") {
                ForEach(viewModel.requestTypeOptions, id: \.self) { option in
                    Button {
                        viewModel.selectRequestType(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(option.titleKey))
                                .font(.headline)
                            Text(LocalizedStringKey(option.subtitleKey))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.automatic)
    }

    private var requestForm: some View {
        List {
            if viewModel.requestTypeOptions.count > 1, let selectedType = viewModel.selectedRequestType {
                Section("seerr.request.type.title") {
                    Picker("seerr.request.type.title", selection: requestTypeBinding(selectedType)) {
                        ForEach(viewModel.requestTypeOptions, id: \.self) { option in
                            Text(LocalizedStringKey(option.titleKey)).tag(option)
                        }
                    }
                    .pickerStyle(.automatic)
                }
            }

            if viewModel.isMovie, !viewModel.requiresAdvancedConfiguration {
                Section {
                    Text("seerr.request.movie.confirmation")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.requiresAdvancedConfiguration {
                requestServiceOptionsSection
            }

            if viewModel.isTV {
                seasonSelectionSection
            }

            Section {
                Button(action: submitRequest) {
                    HStack(spacing: 10) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(LocalizedStringKey(viewModel.submitButtonKey))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandPrimary)
                .disabled(!viewModel.canSubmit || viewModel.isSubmitting)
            }

            if viewModel.isEditing {
                Section {
                    Button("seerr.request.action.cancel", role: .destructive) {
                        Task {
                            await viewModel.cancelRequest()
                        }
                    }
                }
            }
        }
        .listStyle(.automatic)
    }

    private var requestServiceOptionsSection: some View {
        Section("seerr.request.options.title") {
            if viewModel.isLoadingServices, viewModel.availableServers.isEmpty {
                ProgressView("seerr.request.services.loading")
            }

            if let error = viewModel.servicesErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.shouldShowServerPicker {
                Picker("seerr.request.options.server", selection: serverSelectionBinding) {
                    ForEach(viewModel.availableServers) { server in
                        Text(server.name).tag(server.id)
                    }
                }
            }

            if !viewModel.serviceRootFolders.isEmpty {
                if viewModel.shouldShowRootFolderPicker {
                    Picker("seerr.request.options.rootFolder", selection: rootFolderBinding) {
                        ForEach(viewModel.serviceRootFolders, id: \.id) { folder in
                            Text(folder.path ?? "").tag(folder.path ?? "")
                        }
                    }
                } else if let rootFolder = viewModel.selectedRootFolder {
                    HStack {
                        Text("seerr.request.options.rootFolder")
                        Spacer()
                        Text(rootFolder)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.serviceProfiles.isEmpty {
                if viewModel.shouldShowProfilePicker {
                    Picker("seerr.request.options.profile", selection: profileSelectionBinding) {
                        ForEach(viewModel.serviceProfiles, id: \.id) { profile in
                            Text(profile.name ?? "").tag(profile.id)
                        }
                    }
                } else if let profileName = selectedProfileName {
                    HStack {
                        Text("seerr.request.options.profile")
                        Spacer()
                        Text(profileName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var seasonSelectionSection: some View {
        Section("seerr.request.seasons.title") {
            if viewModel.seasons.isEmpty {
                Text("seerr.request.seasons.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.seasons, id: \.id) { season in
                    if let seasonNumber = season.seasonNumber {
                        Toggle(isOn: seasonSelectionBinding(for: seasonNumber)) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.seasonTitle(for: season))
                                        .font(.headline)
                                    Text(seasonEpisodeCountText(season))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let badge = viewModel.seasonAvailabilityBadge(for: season) {
                                    SeerrSeasonAvailabilityBadgeView(badge: badge, showsLabel: true)
                                }
                            }
                        }
                        .disabled(!viewModel.isSeasonSelectable(seasonNumber))
                    }
                }
            }

            if let messageKey = viewModel.partialRequestsDisabledMessageKey {
                Text(LocalizedStringKey(messageKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var serverSelectionBinding: Binding<Int> {
        Binding(
            get: { viewModel.selectedServerId ?? viewModel.availableServers.first?.id ?? 0 },
            set: { newValue in
                Task {
                    await viewModel.selectServer(id: newValue)
                }
            },
        )
    }

    private var profileSelectionBinding: Binding<Int> {
        Binding(
            get: { viewModel.selectedProfileId ?? viewModel.serviceProfiles.first?.id ?? 0 },
            set: { viewModel.selectedProfileId = $0 },
        )
    }

    private var rootFolderBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedRootFolder ?? viewModel.serviceRootFolders.first?.path ?? "" },
            set: { viewModel.selectedRootFolder = $0 },
        )
    }

    private var selectedProfileName: String? {
        guard let selectedProfileId = viewModel.selectedProfileId else { return nil }
        return viewModel.serviceProfiles.first(where: { $0.id == selectedProfileId })?.name
    }

    private func requestTypeBinding(_ selectedType: SeerrMediaRequestType) -> Binding<SeerrMediaRequestType> {
        Binding(
            get: { viewModel.selectedRequestType ?? selectedType },
            set: { newValue in
                viewModel.selectRequestType(newValue)
            },
        )
    }

    private func seasonSelectionBinding(for seasonNumber: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedSeasons.contains(seasonNumber) },
            set: { isSelected in
                viewModel.toggleSeason(seasonNumber, isSelected: isSelected)
            },
        )
    }

    private func seasonEpisodeCountText(_ season: SeerrSeason) -> String {
        let count = season.episodeCount ?? 0
        return String(localized: "media.labels.countEpisode \(count)")
    }

    private func submitRequest() {
        Task {
            await viewModel.submitRequest()
        }
    }
}

private extension SeerrMediaRequestViewModel {
    func seasonTitle(for season: SeerrSeason) -> String {
        if let name = season.name, !name.isEmpty {
            return name
        }
        if let number = season.seasonNumber {
            return String(localized: "media.detail.season") + " \(number)"
        }
        return String(localized: "media.detail.season")
    }
}
