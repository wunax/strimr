import SwiftUI

@MainActor
struct OfflineDownloadsRootView: View {
    var body: some View {
        NavigationStack {
            DownloadsView()
        }
    }
}
