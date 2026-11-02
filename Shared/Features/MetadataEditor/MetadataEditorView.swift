#if !os(tvOS)
    import SwiftUI

    struct MetadataEditorView: View {
        @Environment(\.dismiss) private var dismiss
        @State var viewModel: MetadataEditorViewModel
        @State private var newEntries: [MetadataField: String] = [:]
        @State private var isConfirmingDiscard = false

        var body: some View {
            @Bindable var bindableViewModel = viewModel

            NavigationStack {
                content
                    .navigationTitle("media.metadata.title")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.actions.cancel") {
                                if viewModel.hasChanges {
                                    isConfirmingDiscard = true
                                } else {
                                    dismiss()
                                }
                            }
                            .confirmationDialog(
                                "media.metadata.discard.title",
                                isPresented: $isConfirmingDiscard,
                                titleVisibility: .visible,
                            ) {
                                Button("media.metadata.discard", role: .destructive) { dismiss() }
                                Button("media.metadata.keepEditing", role: .cancel) {}
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            if viewModel.isSaving {
                                ProgressView()
                            } else {
                                Button("media.metadata.save") {
                                    Task {
                                        if await viewModel.save() {
                                            dismiss()
                                        }
                                    }
                                }
                                .disabled(!viewModel.canSave)
                            }
                        }
                    }
                    .alert(item: $bindableViewModel.failure) { failure in
                        Alert(
                            title: Text("media.metadata.error"),
                            message: Text(failure.message),
                            dismissButton: .default(Text("common.actions.done")),
                        )
                    }
            }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 640)
            #endif
            .interactiveDismissDisabled(viewModel.hasChanges || viewModel.isSaving)
            .task { await viewModel.load() }
            .sheet(item: $bindableViewModel.artworkPicker) { picker in
                ArtworkPickerView(viewModel: picker)
                    .onChange(of: picker.changeCount) { viewModel.noteArtworkChanged() }
            }
        }

        @ViewBuilder
        private var content: some View {
            if let draft = viewModel.draft {
                form(draft)
                    .disabled(viewModel.isSaving)
            } else if let message = viewModel.loadErrorMessage {
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                } description: {
                    Text("common.errors.tryAgainLater")
                } actions: {
                    Button("common.actions.retry") {
                        Task { await viewModel.load() }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private func form(_ draft: MetadataDraft) -> some View {
            Form {
                Section("media.metadata.section.info") {
                    ForEach(draft.fields.filter { !$0.isList && $0 != .summary }, id: \.self) { field in
                        row(field, draft: draft)
                    }
                }
                if draft.fields.contains(.summary) {
                    Section {
                        TextField(
                            MetadataField.summary.title,
                            text: textBinding(.summary),
                            axis: .vertical,
                        )
                        .lineLimit(4 ... 12)
                        .labelsHidden()
                    } header: {
                        header(.summary, draft: draft)
                    }
                }
                ForEach(draft.fields.filter(\.isList), id: \.self) { field in
                    listSection(field, draft: draft)
                }
                if viewModel.canEditArtwork {
                    Section {
                        Button {
                            viewModel.openArtwork()
                        } label: {
                            HStack {
                                Label("media.manage.editArtwork", systemImage: "photo.on.rectangle")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("media.metadata.artwork.footer")
                    }
                }
            }
            .formStyle(.grouped)
        }

        private func row(_ field: MetadataField, draft: MetadataDraft) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                header(field, draft: draft)
                switch field {
                case .releaseDate:
                    dateEditor(draft: draft)
                case .contentRating where !draft.contentRatingOptions.isEmpty:
                    contentRatingPicker(draft: draft)
                default:
                    TextField(field.title, text: textBinding(field))
                        .labelsHidden()
                }
            }
        }

        private func header(_ field: MetadataField, draft: MetadataDraft) -> some View {
            HStack {
                Text(field.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                Spacer()
                if draft.lockableFields.contains(field) {
                    let isLocked = draft.isLocked(field)
                    Button {
                        viewModel.toggleLock(field)
                    } label: {
                        Image(systemName: isLocked ? "lock.fill" : "lock.open")
                            .foregroundStyle(isLocked ? .primary : .tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(Text(isLocked ? "media.metadata.unlock" : "media.metadata.lock"))
                    .accessibilityLabel(Text(isLocked ? "media.metadata.unlock" : "media.metadata.lock"))
                    .accessibilityValue(Text(verbatim: field.title))
                }
            }
        }

        @ViewBuilder
        private func dateEditor(draft: MetadataDraft) -> some View {
            if let date = MetadataDate.date(from: draft.value(.releaseDate)) {
                HStack {
                    DatePicker(
                        MetadataField.releaseDate.title,
                        selection: Binding(
                            get: { date },
                            set: { viewModel.setValue(MetadataDate.string(from: $0), for: .releaseDate) },
                        ),
                        displayedComponents: .date,
                    )
                    .labelsHidden()
                    // The date is a calendar day with no time zone, stored at midnight UTC.
                    .environment(\.timeZone, .gmt)
                    Spacer()
                    Button("media.metadata.clearDate", role: .destructive) {
                        viewModel.setValue("", for: .releaseDate)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Button("media.metadata.addDate") {
                    viewModel.setValue(MetadataDate.string(from: .now), for: .releaseDate)
                }
                .buttonStyle(.borderless)
            }
        }

        private func contentRatingPicker(draft: MetadataDraft) -> some View {
            let current = draft.value(.contentRating)
            let options = draft.contentRatingOptions.contains(current) || current.isEmpty
                ? draft.contentRatingOptions
                : [current] + draft.contentRatingOptions
            return Picker(MetadataField.contentRating.title, selection: textBinding(.contentRating)) {
                Text("media.metadata.contentRating.none").tag("")
                ForEach(options, id: \.self) { option in
                    Text(verbatim: option).tag(option)
                }
            }
            .labelsHidden()
        }

        private func listSection(_ field: MetadataField, draft: MetadataDraft) -> some View {
            Section {
                ForEach(draft.list(field), id: \.self) { entry in
                    HStack {
                        Text(verbatim: entry)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeEntry(entry, from: field)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("media.metadata.remove"))
                        .accessibilityValue(Text(verbatim: entry))
                    }
                }
                HStack {
                    TextField("media.metadata.addEntry", text: entryBinding(field))
                        .labelsHidden()
                        .onSubmit { addEntry(to: field) }
                    Button {
                        addEntry(to: field)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled((newEntries[field] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(Text("media.metadata.addEntry"))
                }
                ForEach(viewModel.suggestions(for: field, matching: newEntries[field] ?? ""), id: \.self) { value in
                    Button {
                        viewModel.addEntry(value, to: field)
                        newEntries[field] = nil
                    } label: {
                        Label {
                            Text(verbatim: value)
                        } icon: {
                            Image(systemName: "text.badge.plus")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                header(field, draft: draft)
            }
        }

        private func addEntry(to field: MetadataField) {
            viewModel.addEntry(newEntries[field] ?? "", to: field)
            newEntries[field] = nil
        }

        private func textBinding(_ field: MetadataField) -> Binding<String> {
            Binding(
                get: { viewModel.draft?.value(field) ?? "" },
                set: { viewModel.setValue($0, for: field) },
            )
        }

        private func entryBinding(_ field: MetadataField) -> Binding<String> {
            Binding(
                get: { newEntries[field] ?? "" },
                set: { newEntries[field] = $0 },
            )
        }
    }
#endif
