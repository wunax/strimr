import AppKit
import GroupActivities
import SwiftUI

struct MacSharePlaySharingControllerView: NSViewControllerRepresentable {
    let controller: GroupActivitySharingController

    func makeNSViewController(context _: Context) -> GroupActivitySharingController {
        controller
    }

    func updateNSViewController(
        _: GroupActivitySharingController,
        context _: Context,
    ) {}
}
