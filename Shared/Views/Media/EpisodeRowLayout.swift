import SwiftUI

/// Lays out an episode row in wide layouts: 16:9 artwork on a third of the row, its text beside it, top aligned.
/// Sizing the artwork from the proposed width gives the row its final height on the first pass; measuring the row
/// and resizing afterwards made lazy stacks correct their scroll offset for every row that appeared.
struct EpisodeRowLayout: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let metrics = metrics(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return CGSize(width: metrics.width, height: metrics.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 2 else { return }
        let metrics = metrics(width: bounds.width, subviews: subviews)
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(metrics.artwork),
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + metrics.artwork.width + spacing, y: bounds.minY),
            proposal: ProposedViewSize(width: metrics.textWidth, height: nil),
        )
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> (
        width: CGFloat,
        height: CGFloat,
        artwork: CGSize,
        textWidth: CGFloat,
    ) {
        let artworkWidth = width / 3
        let artwork = CGSize(width: artworkWidth, height: artworkWidth * 9 / 16)
        let textWidth = max(0, width - artworkWidth - spacing)
        let textHeight = subviews.count == 2
            ? subviews[1].sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height
            : 0
        return (width, max(artwork.height, textHeight), artwork, textWidth)
    }
}
