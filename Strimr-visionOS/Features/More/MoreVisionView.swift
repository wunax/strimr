import SwiftUI

struct MoreVisionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("tabs.more")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                NavigationLink(value: MoreVisionRoute.settings) {
                    moreRow(title: "settings.title", systemImage: "gearshape.fill")
                }
                .buttonStyle(.plain)

                NavigationLink(value: MoreVisionRoute.watchTogether) {
                    moreRow(title: "watchTogether.title", systemImage: "person.2.fill")
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await sessionManager.requestProfileSelection()
                    }
                } label: {
                    moreRow(title: "more.switchProfile", systemImage: "person.crop.circle")
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await sessionManager.requestServerSelection()
                    }
                } label: {
                    moreRow(title: "more.switchServer", systemImage: "server.rack")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    moreRow(title: "common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(32)
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
    }

    private func moreRow(title: LocalizedStringKey, systemImage: String, isDestructive: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isDestructive ? .red : .brandPrimary)
                .frame(width: 40)

            Text(title)
                .font(.headline)
                .foregroundStyle(isDestructive ? .red : .primary)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hoverEffect()
    }
}
