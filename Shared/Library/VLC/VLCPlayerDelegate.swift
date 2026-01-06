import Foundation

@MainActor
protocol VLCPlayerDelegate: AnyObject {
    func propertyChange(player: VLCPlayerViewController, property: PlayerProperty, data: Any?)
    func fileLoaded()
    func playbackEnded()
}
