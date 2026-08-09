import AppKit
import GroupActivities
import SwiftUI

struct SharePlaySharingControllerView: NSViewControllerRepresentable {
    let controller: GroupActivitySharingController

    func makeNSViewController(context _: Context) -> GroupActivitySharingController {
        controller
    }

    func updateNSViewController(
        _: GroupActivitySharingController,
        context _: Context,
    ) {}
}
