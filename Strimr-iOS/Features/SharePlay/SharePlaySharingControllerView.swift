import GroupActivities
import SwiftUI
import UIKit

struct SharePlaySharingControllerView: UIViewControllerRepresentable {
    let controller: GroupActivitySharingController

    func makeUIViewController(context: Context) -> GroupActivitySharingController {
        controller
    }

    func updateUIViewController(
        _ uiViewController: GroupActivitySharingController,
        context: Context,
    ) {}
}
