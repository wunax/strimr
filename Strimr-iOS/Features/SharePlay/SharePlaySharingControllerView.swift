import GroupActivities
import SwiftUI
import UIKit

struct SharePlaySharingControllerView: UIViewControllerRepresentable {
    let controller: GroupActivitySharingController

    func makeUIViewController(context _: Context) -> GroupActivitySharingController {
        controller
    }

    func updateUIViewController(
        _: GroupActivitySharingController,
        context _: Context,
    ) {}
}
