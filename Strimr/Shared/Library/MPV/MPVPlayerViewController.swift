import Foundation
import UIKit
import Libmpv

// warning: metal API validation has been disabled to ignore crash when playing HDR videos.
// Edit Scheme -> Run -> Diagnostics -> Metal API Validation -> Turn it off
// https://github.com/KhronosGroup/MoltenVK/issues/2226
final class MPVPlayerViewController: UIViewController {
    var metalLayer = MetalLayer()
    var mpv: OpaquePointer?
    var playDelegate: MPVPlayerDelegate?
    lazy var queue = DispatchQueue(label: "mpv", qos: .userInitiated)
    
    var playUrl: URL?
    var hdrAvailable : Bool = false
    var hdrEnabled = false {
        didSet {
            // FIXME: target-colorspace-hint does not support being changed at runtime.
            // this option should be set as early as possible otherwise can cause issues
            // not recommended to use this way.
            guard let mpv else { return }
            if hdrEnabled {
                checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
            } else {
                checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "no"))
            }
        }
    }

    deinit {
        destruct()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        metalLayer.frame = view.frame
        print(view.bounds)
        print(view.frame)
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        
        view.layer.addSublayer(metalLayer)
        
        setupMpv()
        
        if let url = playUrl {
            loadFile(url)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        metalLayer.frame = view.frame
    }
    
    func setupMpv() {
        mpv = mpv_create()
        guard let mpv else {
            print("failed creating context\n")
            exit(1)
        }
        
        // https://mpv.io/manual/stable/#options
#if DEBUG
        checkError(mpv_request_log_messages(mpv, "debug"))
#else
        checkError(mpv_request_log_messages(mpv, "no"))
#endif
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer))
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))

//        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes")) // HDR passthrough
//        checkError(mpv_set_option_string(mpv, "tone-mapping-visualize", "yes"))  // only for debugging purposes
//        checkError(mpv_set_option_string(mpv, "profile", "fast"))   // can fix frame drop in poor device when play 4k

        
        checkError(mpv_initialize(mpv))
        
        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsSigPeak, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.demuxerCacheDuration, MPV_FORMAT_DOUBLE)
        mpv_set_wakeup_callback(mpv, { (ctx) in
            let client = unsafeBitCast(ctx, to: MPVPlayerViewController.self)
            client.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        setupNotification()
    }
    
    public func setupNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc public func enterBackground() {
        // fix black screen issue when app enter foreground again
        guard let mpv else { return }
        pause()
        checkError(mpv_set_option_string(mpv, "vid", "no"))
    }
    
    @objc public func enterForeground() {
        guard let mpv else { return }
        checkError(mpv_set_option_string(mpv, "vid", "auto"))
        play()
    }
    
    
    func loadFile(
        _ url: URL
    ) {
        var args = [url.absoluteString]
        var options = [String]()
        
        args.append("replace")
        
        if !options.isEmpty {
            args.append(options.joined(separator: ","))
        }
        
        command("loadfile", args: args)
    }
    
    func togglePause() {
        getFlag(MPVProperty.pause) ? play() : pause()
    }
    
    func play() {
        setFlag(MPVProperty.pause, false)
    }
    
    func pause() {
        setFlag(MPVProperty.pause, true)
    }

    func seek(to time: Double) {
        setDouble(MPVProperty.timePos, time)
    }

    func seek(by delta: Double) {
        guard mpv != nil else { return }
        command(
            "seek",
            args: [
                String(delta),
                "relative",
                "exact"
            ]
        )
    }

    func setAudioTrack(id: Int?) {
        setTrackProperty("aid", trackID: id)
    }

    func setSubtitleTrack(id: Int?) {
        setTrackProperty("sid", trackID: id)
    }

    func trackList() -> [MPVTrack] {
        guard let mpv else { return [] }

        var node = mpv_node()
        guard mpv_get_property(mpv, "track-list", MPV_FORMAT_NODE, &node) >= 0 else { return [] }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list?.pointee else { return [] }

        var tracks: [MPVTrack] = []
        for index in 0..<Int(list.num) {
            let entry = list.values[index]
            guard entry.format == MPV_FORMAT_NODE_MAP, let map = entry.u.list?.pointee else { continue }
            let values = parseMap(map)

            guard
                let typeString = values["type"] as? String,
                let type = MPVTrack.TrackType(rawValue: typeString),
                let id = values["id"] as? Int
            else {
                continue
            }

            let track = MPVTrack(
                id: id,
                ffIndex: values["ff-index"] as? Int,
                type: type,
                title: values["title"] as? String,
                language: values["lang"] as? String,
                codec: values["codec"] as? String,
                isDefault: values["default"] as? Bool ?? false,
                isSelected: values["selected"] as? Bool ?? false
            )

            tracks.append(track)
        }

        return tracks
    }
    
    private func getDouble(_ name: String) -> Double {
        guard let mpv else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }
    
    private func getString(_ name: String) -> String? {
        guard let mpv else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }
    
    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }
    
    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    }

    private func setTrackProperty(_ name: String, trackID: Int?) {
        let value = trackID.map(String.init) ?? "no"
        command("set", args: [name, value])
    }
    
    
    func command(
        _ command: String,
        args: [String?] = [],
        checkForErrors: Bool = true,
        returnValueCallback: ((Int32) -> Void)? = nil
    ) {
        guard let mpv else {
            return
        }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }
        //print("\(command) -- \(args)")
        let returnValue = mpv_command(mpv, &cargs)
        if checkForErrors {
            checkError(returnValue)
        }
        if let cb = returnValueCallback {
            cb(returnValue)
        }
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        if !args.isEmpty, args.last == nil {
            fatalError("Command do not need a nil suffix")
        }
        
        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)
        
        return strArgs
    }
    
    func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            
            while true {
                guard let mpv = self.mpv else { break }
                let event = mpv_wait_event(mpv, 0)
                if event?.pointee.event_id == MPV_EVENT_NONE {
                    break
                }
                
                switch event!.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    let dataOpaquePtr = OpaquePointer(event!.pointee.data)
                    if let property = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
                        let propertyName = String(cString: property.name)
                        switch propertyName {
                        case MPVProperty.videoParamsSigPeak:
                            if let sigPeak = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                                DispatchQueue.main.async {
                                    let maxEDRRange = self.view.window?.screen.potentialEDRHeadroom ?? 1.0
                                    // display screen support HDR and current playing HDR video
                                    self.hdrAvailable = maxEDRRange > 1.0 && sigPeak > 1.0
                                    self.playDelegate?.propertyChange(mpv: mpv, propertyName: propertyName, data: sigPeak)
                                }
                            }
                        case MPVProperty.pause:
                            let pausedValue = UnsafePointer<Int64>(OpaquePointer(property.data))?.pointee ?? 0
                            let isPaused = pausedValue > 0
                            DispatchQueue.main.async {
                                self.playDelegate?.propertyChange(mpv: mpv, propertyName: propertyName, data: isPaused)
                            }
                        case MPVProperty.pausedForCache:
                            let buffering = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? true
                            DispatchQueue.main.async {
                                self.playDelegate?.propertyChange(mpv: mpv, propertyName: propertyName, data: buffering)
                            }
                        case MPVProperty.timePos, MPVProperty.duration, MPVProperty.demuxerCacheDuration:
                            let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee
                            DispatchQueue.main.async {
                                self.playDelegate?.propertyChange(mpv: mpv, propertyName: propertyName, data: value)
                            }
                        default: break
                        }
                    }
                case MPV_EVENT_SHUTDOWN:
                    print("event: shutdown\n");
                    destruct()
                    break
                case MPV_EVENT_LOG_MESSAGE:
                    let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event!.pointee.data))
                    print("[\(String(cString: (msg!.pointee.prefix)!))] \(String(cString: (msg!.pointee.level)!)): \(String(cString: (msg!.pointee.text)!))", terminator: "")
                default:
                    let eventName = mpv_event_name(event!.pointee.event_id )
                    print("event: \(String(cString: (eventName)!))");
                }
                
            }
        }
    }

    func destruct() {
        NotificationCenter.default.removeObserver(self)
        guard let mpv else { return }

        // Drop the wakeup callback to avoid mpv calling back into a deallocated controller.
        mpv_set_wakeup_callback(mpv, nil, nil)

        let mpvHandle = mpv
        self.mpv = nil

        queue.async {
            mpv_terminate_destroy(mpvHandle)
        }
    }

    private func parseMap(_ map: mpv_node_list) -> [String: Any] {
        var values: [String: Any] = [:]

        for index in 0..<Int(map.num) {
            guard let keyPointer = map.keys?[index] else { continue }
            let key = String(cString: keyPointer)
            let valueNode = map.values[index]

            switch valueNode.format {
            case MPV_FORMAT_STRING:
                if let pointer = valueNode.u.string {
                    values[key] = String(cString: pointer)
                }
            case MPV_FORMAT_INT64:
                values[key] = Int(valueNode.u.int64)
            case MPV_FORMAT_DOUBLE:
                values[key] = valueNode.u.double_
            case MPV_FORMAT_FLAG:
                values[key] = valueNode.u.flag != 0
            default:
                continue
            }
        }

        return values
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("MPV API error: \(String(cString: mpv_error_string(status)))\n")
        }
    }
    
}
