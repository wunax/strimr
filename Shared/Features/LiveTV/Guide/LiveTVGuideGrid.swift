import SwiftUI

/// Interactions of the guide grid, shared by the UIKit and SwiftUI implementations.
struct LiveTVGuideGridActions {
    let openProgram: (LiveTVProgram) -> Void
    let showDetails: (LiveTVProgram) -> Void
    let tuneChannel: (LiveTVChannel) -> Void
    let toggleFavorite: (LiveTVChannel) -> Void
    let focusProgram: (LiveTVProgram) -> Void
    let reachEdge: (_ forward: Bool) -> Void
}

#if os(iOS) || os(tvOS)
    import UIKit

    /// The guide as a virtualized collection view: 300 channels over a day of programs only create the visible cells.
    struct LiveTVGuideGrid: UIViewControllerRepresentable {
        let model: LiveTVGuideGridModel
        let services: MediaServices
        let scrollRequest: LiveTVGuideScrollRequest?
        let actions: LiveTVGuideGridActions

        func makeUIViewController(context _: Context) -> LiveTVGuideGridController {
            LiveTVGuideGridController(services: services)
        }

        func updateUIViewController(_ controller: LiveTVGuideGridController, context _: Context) {
            controller.actions = actions
            controller.update(model: model)
            if let scrollRequest {
                controller.perform(scrollRequest)
            }
        }
    }

    final class LiveTVGuideGridController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
        fileprivate static let rulerKind = "ruler"
        fileprivate static let cornerKind = "corner"
        fileprivate static let nowKind = "now"

        var actions: LiveTVGuideGridActions?
        private let services: MediaServices
        private let layout = LiveTVGuideLayout()
        private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        private var model: LiveTVGuideGridModel?
        private var lastScrollRequestID: UUID?
        private var pendingScrollRequest: LiveTVGuideScrollRequest?
        private var preferredFocusIndexPath: IndexPath?
        /// The time focus keeps while it moves between channels.
        private var focusAnchorDate: Date?
        /// Stands in for `remembersLastFocusedIndexPath`, which would take precedence over the preferred index path.
        /// A program rather than an index path, since reloads and filters move programs in the grid.
        private var lastFocusedProgram: LiveTVProgram?
        private var clockTimer: Timer?

        init(services: MediaServices) {
            self.services = services
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            collectionView.backgroundColor = .clear
            collectionView.dataSource = self
            collectionView.delegate = self
            collectionView.contentInsetAdjustmentBehavior = .never
            collectionView.showsHorizontalScrollIndicator = false
            #if os(iOS)
                collectionView.isDirectionalLockEnabled = true
                collectionView.bounces = false
            #endif
            collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "program")
            collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "channel")
            for kind in [Self.rulerKind, Self.cornerKind, Self.nowKind] {
                collectionView.register(
                    LiveTVGuideSupplementaryView.self,
                    forSupplementaryViewOfKind: kind,
                    withReuseIdentifier: kind,
                )
            }
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(collectionView)
            NSLayoutConstraint.activate([
                collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            clockTimer?.invalidate()
            clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshClock() }
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            clockTimer?.invalidate()
            clockTimer = nil
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if let pendingScrollRequest, collectionView.bounds.width > 0 {
                self.pendingScrollRequest = nil
                scroll(to: pendingScrollRequest)
            }
        }

        func update(model newModel: LiveTVGuideGridModel) {
            guard newModel != model else { return }
            let previous = model
            model = newModel
            layout.model = newModel
            let offset = collectionView.contentOffset
            collectionView.reloadData()
            layout.invalidateLayout()
            if let previous, previous.start > newModel.start {
                // Earlier hours were added on the left: keep the same times on screen.
                let shift = LiveTVGuideMetrics.width(of: previous.start.timeIntervalSince(newModel.start))
                collectionView.layoutIfNeeded()
                collectionView.contentOffset = CGPoint(x: offset.x + shift, y: offset.y)
            }
        }

        func perform(_ request: LiveTVGuideScrollRequest) {
            guard request.id != lastScrollRequestID else { return }
            lastScrollRequestID = request.id
            if collectionView.bounds.width > 0, model != nil {
                scroll(to: request)
            } else {
                pendingScrollRequest = request
            }
        }

        private func scroll(to request: LiveTVGuideScrollRequest) {
            guard let model else { return }
            collectionView.layoutIfNeeded()
            let geometry = model.geometry
            let visibleWidth = collectionView.bounds.width - LiveTVGuideMetrics.channelColumnWidth
            // Leave a little of the past visible, so what is on air does not start at the edge.
            let x = geometry.x(for: request.date) - LiveTVGuideMetrics.channelColumnWidth - visibleWidth * 0.1
            var y = collectionView.contentOffset.y
            if let channel = request.channel, let row = model.row(of: channel) {
                let rowY = layout.rowY(row)
                let visibleHeight = collectionView.bounds.height - LiveTVGuideMetrics.rulerHeight
                y = rowY - LiveTVGuideMetrics.rulerHeight - visibleHeight / 3
            }
            let maxX = max(0, collectionView.contentSize.width - collectionView.bounds.width)
            let maxY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
            collectionView.setContentOffset(
                CGPoint(x: min(max(0, x), maxX), y: min(max(0, y), maxY)),
                animated: false,
            )
            focusAnchorDate = request.date
            if request.movesFocus,
               let channel = request.channel ?? visibleFirstChannel(),
               let row = model.row(of: channel),
               let match = model.program(at: request.date, row: row)
            {
                preferredFocusIndexPath = IndexPath(item: match.index + 1, section: row)
                #if os(tvOS)
                    setNeedsFocusUpdate()
                    updateFocusIfNeeded()
                #endif
            }
        }

        private func visibleFirstChannel() -> LiveTVChannelIdentity? {
            guard let model else { return nil }
            let row = layout.firstVisibleRow(in: collectionView.bounds)
            return model.channels.indices.contains(row) ? model.channels[row].identity : nil
        }

        private func refreshClock() {
            layout.now = Date()
            layout.invalidateLayout()
            for indexPath in collectionView.indexPathsForVisibleItems where indexPath.item > 0 {
                if let cell = collectionView.cellForItem(at: indexPath) {
                    cell.setNeedsUpdateConfiguration()
                }
            }
        }

        // MARK: Data source

        func numberOfSections(in _: UICollectionView) -> Int {
            model?.channels.count ?? 0
        }

        func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            1 + (model?.rows[section].count ?? 0)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath,
        ) -> UICollectionViewCell {
            guard let model else { return UICollectionViewCell() }
            let services = services
            if indexPath.item == 0 {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "channel", for: indexPath)
                let channel = model.channels[indexPath.section]
                let isPlaying = channel.identity == model.playingChannel
                cell.configurationUpdateHandler = { cell, state in
                    cell.contentConfiguration = UIHostingConfiguration {
                        LiveTVGuideChannelCell(channel: channel, isPlaying: isPlaying, isFocused: state.isFocused)
                            .environment(services)
                            .padding(.trailing, LiveTVGuideMetrics.channelColumnGap)
                            // Programs scroll under the fixed column.
                            .background(Color("Background"))
                    }
                    .margins(.all, 0)
                }
                return cell
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "program", for: indexPath)
            let program = model.rows[indexPath.section][indexPath.item - 1]
            let geometry = model.geometry
            let tints = model.tintsCategories
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    LiveTVGuideProgramCell(
                        program: program,
                        geometry: geometry,
                        tintsCategory: tints,
                        isFocused: state.isFocused,
                        now: Date(),
                    )
                }
                .margins(.all, 0)
            }
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath,
        ) -> UICollectionReusableView {
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: kind,
                for: indexPath,
            )
            guard let view = view as? LiveTVGuideSupplementaryView, let model else { return view }
            switch kind {
            case Self.rulerKind:
                let slots = layout.slots
                if slots.indices.contains(indexPath.item) {
                    view.show(LiveTVGuideRulerCell(date: slots[indexPath.item]))
                }
            case Self.cornerKind:
                view.show(LiveTVGuideCornerCell(date: layout.visibleDate(in: collectionView.bounds) ?? model.start))
            default:
                view.show(Rectangle().fill(.liveIndicator).frame(width: 2))
            }
            return view
        }

        // MARK: Delegate

        func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard let model, let actions else { return }
            if indexPath.item == 0 {
                actions.tuneChannel(model.channels[indexPath.section])
            } else {
                actions.openProgram(model.rows[indexPath.section][indexPath.item - 1])
            }
        }

        func collectionView(
            _: UICollectionView,
            contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
            point _: CGPoint,
        ) -> UIContextMenuConfiguration? {
            guard let indexPath = indexPaths.first, let model, let actions else { return nil }
            let channel = model.channels[indexPath.section]
            let favoriteTitle = String(localized: channel.isFavorite ? "livetv.favorite.remove" : "livetv.favorite.add")
            let favorite = UIAction(
                title: favoriteTitle,
                image: UIImage(systemName: channel.isFavorite ? "star.slash" : "star"),
            ) { _ in actions.toggleFavorite(channel) }
            if indexPath.item == 0 {
                let watch = UIAction(
                    title: String(localized: "livetv.watchLive"),
                    image: UIImage(systemName: "play.fill"),
                ) { _ in actions.tuneChannel(channel) }
                return UIContextMenuConfiguration(actionProvider: { _ in UIMenu(children: [watch, favorite]) })
            }
            let program = model.rows[indexPath.section][indexPath.item - 1]
            var items: [UIMenuElement] = []
            if program.isCurrentlyAiring {
                items.append(UIAction(
                    title: String(localized: "livetv.watchLive"),
                    image: UIImage(systemName: "play.fill"),
                ) { _ in actions.openProgram(program) })
            }
            items.append(UIAction(
                title: String(localized: "livetv.program.details"),
                image: UIImage(systemName: "info.circle"),
            ) { _ in actions.showDetails(program) })
            items.append(favorite)
            return UIContextMenuConfiguration(actionProvider: { _ in UIMenu(children: items) })
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let model, scrollView.bounds.width > 0 else { return }
            let threshold = scrollView.bounds.width
            if scrollView.contentOffset.x + scrollView.bounds.width > scrollView.contentSize.width - threshold {
                actions?.reachEdge(true)
            } else if scrollView.contentOffset.x < threshold / 2, model.start > Date().addingTimeInterval(-6 * 3600) {
                actions?.reachEdge(false)
            }
            if let corner = collectionView.visibleSupplementaryViews(ofKind: Self.cornerKind).first
                as? LiveTVGuideSupplementaryView
            {
                corner.show(LiveTVGuideCornerCell(date: layout.visibleDate(in: scrollView.bounds) ?? model.start))
            }
        }

        #if os(tvOS)
            /// The fixed column would make the focus engine scroll the grid to its edge; channels tune from their
            /// programs and their menu instead.
            func collectionView(_: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
                indexPath.item > 0
            }

            func indexPathForPreferredFocusedView(in _: UICollectionView) -> IndexPath? {
                defer { preferredFocusIndexPath = nil }
                return preferredFocusIndexPath ?? lastFocusedIndexPath
            }

            private var lastFocusedIndexPath: IndexPath? {
                guard let model, let program = lastFocusedProgram,
                      let row = model.row(of: program.channelIdentity),
                      let match = model.program(at: program.startDate, row: row)
                else { return nil }
                return IndexPath(item: match.index + 1, section: row)
            }

            func collectionView(
                _ collectionView: UICollectionView,
                didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                with _: UIFocusAnimationCoordinator,
            ) {
                guard let model, let next = context.nextFocusedIndexPath, next.item > 0 else { return }
                let program = model.rows[next.section][next.item - 1]
                let heading = context.focusHeading
                if heading.contains(.up) || heading.contains(.down), let anchor = focusAnchorDate {
                    // Moving between channels keeps the time in focus instead of the nearest cell.
                    if !program.isAiring(at: anchor),
                       let match = model.program(at: anchor, row: next.section),
                       match.index + 1 != next.item
                    {
                        preferredFocusIndexPath = IndexPath(item: match.index + 1, section: next.section)
                        collectionView.setNeedsFocusUpdate()
                        collectionView.updateFocusIfNeeded()
                        return
                    }
                } else if !heading.isEmpty || focusAnchorDate == nil {
                    // A move without a heading was requested by the grid, and keeps the anchor it set.
                    let visibleStart = layout.visibleDate(in: collectionView.bounds) ?? model.start
                    focusAnchorDate = max(program.startDate, visibleStart)
                }
                lastFocusedProgram = program
                actions?.focusProgram(program)
            }
        #endif
    }

    /// Fixed channel column and time ruler over a grid of programs placed by time.
    final class LiveTVGuideLayout: UICollectionViewLayout {
        var model: LiveTVGuideGridModel? {
            didSet {
                slots = model?.geometry.slots ?? []
                frames = []
            }
        }

        var now = Date()
        private(set) var slots: [Date] = []
        /// Program frames per row, before the sticky offsets.
        private var frames: [[CGRect]] = []

        private var rowStride: CGFloat {
            LiveTVGuideMetrics.rowHeight + LiveTVGuideMetrics.rowSpacing
        }

        func rowY(_ row: Int) -> CGFloat {
            LiveTVGuideMetrics.rulerHeight + LiveTVGuideMetrics.rowSpacing + CGFloat(row) * rowStride
        }

        func firstVisibleRow(in bounds: CGRect) -> Int {
            max(0, Int((bounds.minY + LiveTVGuideMetrics.rulerHeight) / rowStride))
        }

        func visibleDate(in bounds: CGRect) -> Date? {
            model?.geometry.date(atX: bounds.minX + LiveTVGuideMetrics.channelColumnWidth)
        }

        override var collectionViewContentSize: CGSize {
            guard let model else { return .zero }
            return CGSize(
                width: model.geometry.contentWidth,
                height: rowY(model.channels.count) + LiveTVGuideMetrics.rowSpacing,
            )
        }

        override func prepare() {
            super.prepare()
            guard let model, frames.isEmpty else { return }
            let geometry = model.geometry
            frames = model.rows.enumerated().map { row, programs in
                let y = rowY(row)
                return programs.map { program in
                    let frame = geometry.frame(of: program)
                    return CGRect(
                        x: frame.x + 2,
                        y: y,
                        width: max(frame.width - 4, 2),
                        height: LiveTVGuideMetrics.rowHeight,
                    )
                }
            }
        }

        override func shouldInvalidateLayout(forBoundsChange _: CGRect) -> Bool {
            true
        }

        override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
            guard let model, let collectionView else { return nil }
            let bounds = collectionView.bounds
            var result: [UICollectionViewLayoutAttributes] = []
            let firstRow = max(0, Int((rect.minY - LiveTVGuideMetrics.rulerHeight) / rowStride) - 1)
            let lastRow = min(model.channels.count - 1, Int(rect.maxY / rowStride) + 1)
            if firstRow <= lastRow {
                for row in firstRow ... lastRow {
                    result.append(channelAttributes(row: row, bounds: bounds))
                    for (index, frame) in frames[row].enumerated() where frame.intersects(rect) {
                        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(
                            item: index + 1,
                            section: row,
                        ))
                        attributes.frame = LiveTVGuideGeometry.visibleCellFrame(frame, scrollX: bounds.minX)
                        attributes.zIndex = 1
                        result.append(attributes)
                    }
                }
            }
            let geometry = model.geometry
            for (index, slot) in slots.enumerated() {
                let x = geometry.x(for: slot)
                guard x + LiveTVGuideMetrics.width(of: 1800) >= rect.minX, x <= rect.maxX else { continue }
                if let attributes = rulerAttributes(index: index, bounds: bounds) {
                    result.append(attributes)
                }
            }
            if let attributes = nowAttributes(bounds: bounds) {
                result.append(attributes)
            }
            result.append(cornerAttributes(bounds: bounds))
            return result
        }

        override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            guard let collectionView, frames.indices.contains(indexPath.section) else { return nil }
            if indexPath.item == 0 {
                return channelAttributes(row: indexPath.section, bounds: collectionView.bounds)
            }
            let row = frames[indexPath.section]
            guard row.indices.contains(indexPath.item - 1) else { return nil }
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = LiveTVGuideGeometry.visibleCellFrame(
                row[indexPath.item - 1],
                scrollX: collectionView.bounds.minX,
            )
            attributes.zIndex = 1
            return attributes
        }

        override func layoutAttributesForSupplementaryView(
            ofKind elementKind: String,
            at indexPath: IndexPath,
        ) -> UICollectionViewLayoutAttributes? {
            guard let collectionView else { return nil }
            let bounds = collectionView.bounds
            switch elementKind {
            case LiveTVGuideGridController.rulerKind: return rulerAttributes(index: indexPath.item, bounds: bounds)
            case LiveTVGuideGridController.cornerKind: return cornerAttributes(bounds: bounds)
            default: return nowAttributes(bounds: bounds)
            }
        }

        private func channelAttributes(row: Int, bounds: CGRect) -> UICollectionViewLayoutAttributes {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: row))
            attributes.frame = CGRect(
                x: bounds.minX,
                y: rowY(row),
                width: LiveTVGuideMetrics.channelColumnWidth,
                height: LiveTVGuideMetrics.rowHeight,
            )
            attributes.zIndex = 10
            return attributes
        }

        private func rulerAttributes(index: Int, bounds: CGRect) -> UICollectionViewLayoutAttributes? {
            guard let model, slots.indices.contains(index) else { return nil }
            let attributes = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: LiveTVGuideGridController.rulerKind,
                with: IndexPath(item: index, section: 0),
            )
            attributes.frame = CGRect(
                x: model.geometry.x(for: slots[index]),
                y: bounds.minY,
                width: LiveTVGuideMetrics.width(of: 1800),
                height: LiveTVGuideMetrics.rulerHeight,
            )
            attributes.zIndex = 20
            return attributes
        }

        private func cornerAttributes(bounds: CGRect) -> UICollectionViewLayoutAttributes {
            let attributes = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: LiveTVGuideGridController.cornerKind,
                with: IndexPath(item: 0, section: 0),
            )
            attributes.frame = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: LiveTVGuideMetrics.channelColumnWidth,
                height: LiveTVGuideMetrics.rulerHeight,
            )
            attributes.zIndex = 30
            return attributes
        }

        private func nowAttributes(bounds: CGRect) -> UICollectionViewLayoutAttributes? {
            guard let model, now >= model.start, now < model.end else { return nil }
            let x = model.geometry.x(for: now)
            guard x >= bounds.minX + LiveTVGuideMetrics.channelColumnWidth else { return nil }
            let attributes = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: LiveTVGuideGridController.nowKind,
                with: IndexPath(item: 0, section: 0),
            )
            attributes.frame = CGRect(x: x - 1, y: bounds.minY, width: 2, height: bounds.height)
            attributes.zIndex = 5
            return attributes
        }
    }

    final class LiveTVGuideSupplementaryView: UICollectionReusableView {
        private var host: UIHostingController<AnyView>?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func show(_ content: some View) {
            if let host {
                host.rootView = AnyView(content)
                return
            }
            let host = UIHostingController(rootView: AnyView(content))
            host.view.backgroundColor = .clear
            host.view.frame = bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(host.view)
            self.host = host
        }

        override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
            super.apply(layoutAttributes)
            // The ruler and corner sit over the scrolling cells, so they carry the page background.
            let kind = layoutAttributes.representedElementKind
            backgroundColor = kind == LiveTVGuideGridController.nowKind ? .clear : UIColor(named: "Background")
        }
    }
#else
    typealias LiveTVGuideGrid = LiveTVGuideSwiftUIGrid
#endif
