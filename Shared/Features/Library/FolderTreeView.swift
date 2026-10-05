import SwiftUI

struct FolderTreeView: View {
    let model: FolderTreeModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var indentWidth: CGFloat {
        #if os(tvOS)
            40
        #else
            20
        #endif
    }

    var body: some View {
        if model.isLoadingRoot, model.rootItems.isEmpty {
            ProgressView("library.browse.loading")
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        } else if let errorMessage = model.errorMessage, model.rootItems.isEmpty {
            ContentUnavailableView {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text("common.errors.tryAgainLater")
            } actions: {
                Button("common.actions.retry") {
                    Task { await model.loadRoot() }
                }
            }
        } else if model.hasLoadedRoot, model.rootItems.isEmpty {
            ContentUnavailableView(
                "library.browse.empty.title",
                systemImage: "folder",
                description: Text("library.browse.empty.description"),
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(model.rows) { row in
                    rowView(row)
                        .padding(.leading, CGFloat(row.depth) * indentWidth)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: FolderTreeModel.Row) -> some View {
        switch row.item {
        case let .folder(folder):
            FolderTreeRow(title: folder.title, isExpanded: row.isExpanded, isLoading: row.isLoading) {
                Task { await model.toggle(folder) }
            }
        case let .media(media):
            MediaListRow(media: media) {
                onSelectMedia(media)
            }
        }
    }
}

struct FolderTreeRow: View {
    let title: String
    let isExpanded: Bool
    let isLoading: Bool
    let onTap: () -> Void

    #if os(tvOS)
        @FocusState private var isFocused: Bool
    #endif

    private var isHighlighted: Bool {
        #if os(tvOS)
            isFocused
        #else
            false
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            14
        #else
            10
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .frame(width: 24)

                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, verticalPadding)
            .modifier(MediaListRowHighlight(isFocused: isHighlighted))

            #if !os(tvOS)
                Divider()
            #endif
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onPlayPauseCommand(perform: onTap)
        #endif
            .onTapGesture(perform: onTap)
    }
}
