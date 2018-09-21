import UIKit
import AVFoundation

public final class AVPlayerView: UIView, PlayerControllable {

    // MARK:- Public Vars

    public weak var delegate: PlayerControlDelegate? // Xcode のバグで Swift Protocol は @IBOutlet に出来ない

    private var wasPlaying: Bool = false

    public var playerItem: AVPlayerItem? {
        willSet {
            if let player = player {
                wasPlaying = isPlaying
                player.pause()
            }
            guard let playerItem = playerItem else {
                if let player = player {
                    player.replaceCurrentItem(with: nil)
                }
                return
            }

            playerItem.remove(output)
            for keyPath in playerItemKVOKeyPaths {
                playerItem.removeObserver(self, forKeyPath: keyPath, context: nil)
            }
        }
        didSet {
            guard let player = player else {
                return
            }
            guard let playerItem = playerItem else {
                wasPlaying = false
                return
            }
            playerItem.loadPreferredCGImagePropertyOrientation { [weak self] (success: Bool, preferredCGImagePropertyOrientation: Int32) -> Void in
                guard let `self` = self else { return }

                self.preferredCGImagePropertyOrientation = preferredCGImagePropertyOrientation

                for keyPath in self.playerItemKVOKeyPaths {
                    playerItem.addObserver(self, forKeyPath: keyPath, options: [.new, .old], context: nil)
                }
                player.replaceCurrentItem(with: playerItem)
                playerItem.add(self.output)

                if self.wasPlaying {
                    self.wasPlaying = false
                    self.play()
                }
            }
        }
    }

    // MARK:- Player Control

    public func play() {
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public var isPlaying: Bool {
        get {
            guard let player = player, let _ = player.currentItem else {
                return false
            }
            return player.rate != 0.0
        }
    }

    public var rate: Float {
        get {
            guard let player = player else {
                fatalError()
            }
            return player.rate
        }
        set {
            guard let player = player else {
                fatalError()
            }
            player.rate = newValue
        }
    }

    public var currentTime: CMTime {
        get {
            guard let currentTime = player?.currentItem?.currentTime() , currentTime.isValid else {
                return .invalid
            }
            return currentTime
        }
    }

    public var duration: CMTime {
        get {
            guard let duration = player?.currentItem?.duration , duration.isValid else {
                return .invalid
            }
            return duration
        }
    }

    public private(set) var isSeeking: Bool = false

    public func seek(to: CMTime) {
        seek(to: to, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
    }

    public func seek(to: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        guard let player = player else {
            return
        }
        // ドキュメントによると kCMTimePositiveInfinity を放り込めば単純に seek(to:) と同じらしい。
        isSeeking = true
        player.seek(to: to, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] (success: Bool) -> Void in
            guard let `self` = self, let delegate = self.delegate else {
                return
            }
            self.isSeeking = false
            onMainThread {
                if success {
                    delegate.playerDidFinishSeeking(self)
                } else {
                    delegate.playerDidFailSeeking(self)
                }
            }
        }
    }

    public var loadedTimeRanges: [CMTimeRange] {
        get {
            guard let loadedTimeRangeValues = player?.currentItem?.loadedTimeRanges else {
                return []
            }
            return loadedTimeRangeValues.map { (loadedTimeRangeValue: NSValue) -> CMTimeRange in
                return loadedTimeRangeValue.timeRangeValue
            }
        }
    }

    public var volume: Float {
        get {
            guard let player = player else {
                fatalError()
            }
            return player.volume
        }
        set {
            guard let player = player else {
                fatalError()
            }
            player.volume = newValue
        }
    }

    // MARK:- ScreenShot

    private let cicontext = CIContext(options: nil)

    private var preferredCGImagePropertyOrientation: Int32 = 1

    public func createScreenShot() -> UIImage? {
        guard let _ = player?.currentItem else {
            return nil
        }

        guard let time = player?.currentTime() else {
            return nil
        }

        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: preferredCGImagePropertyOrientation)
        guard let cgImage = cicontext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        return image
    }

    // MARK:- AVPlayerLayer

    override public class var layerClass : AnyClass {
        return AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        get {
            guard let playerLayer = layer as? AVPlayerLayer else {
                fatalError()
            }
            return playerLayer
        }
    }

    private var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
    }

    // MARK:- Private Vars

    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes:Dictionary<String, AnyObject>())

    private var timeObserver: AnyObject?

    private let playerItemKVOKeyPaths: [String] = [
        "status",
        "playbackLikelyToKeepUp",
        "loadedTimeRanges"
    ]

    // MARK:- Initializer

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupPlayer()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupAVPlayer()
        setupAVPlayerItemNotifications()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAVPlayer()
        setupAVPlayerItemNotifications()
    }

    private func setupAVPlayer() {
        if self.player != nil {
            return
        }
        let player = AVPlayer()
        player.addObserver(self, forKeyPath: "rate", options: [.new, .old], context: nil)
        player.addObserver(self, forKeyPath: "volume", options: [.new, .old], context: nil)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [unowned self] (time: CMTime) -> Void in
            self.playerDidChangePlayTimePeriodic()
        } as AnyObject?
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.addObserver(self, forKeyPath: "externalPlaybackActive", options: [.new, .old], context: nil)
        self.player = player
    }

    private func cleanupPlayer() {
        guard let player = player else {
            return
        }
        player.removeObserver(self, forKeyPath: "rate", context: nil)
        player.removeObserver(self, forKeyPath: "volume", context: nil)
        player.removeObserver(self, forKeyPath: "externalPlaybackActive", context: nil)
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        playerItem = nil
        self.player = nil
    }

    // MARK:- UIView

    public override var contentMode: UIView.ContentMode {
        didSet {
            let videoGravity: AVLayerVideoGravity
            switch contentMode {
            case .scaleToFill:     videoGravity = .resize
            case .scaleAspectFit:  videoGravity = .resizeAspect
            case .scaleAspectFill: videoGravity = .resizeAspectFill
            default:               videoGravity = .resizeAspect // AVPlayerLayer's Default
            }

            // 何故か CoreAnimation の暗黙の action っぽくはないアニメーションが走る
            // AVCaptureVideoPreviewLayer とは違うんだな…
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer {
                CATransaction.commit()
            }
            playerLayer.videoGravity = videoGravity
        }
    }

    // MARK:- Notification

    private func setupAVPlayerItemNotifications() {
        [
            Notification.Name.AVPlayerItemDidPlayToEndTime,
            Notification.Name.AVPlayerItemFailedToPlayToEndTime,
            Notification.Name.AVPlayerItemPlaybackStalled
        ].forEach { name in
            NotificationCenter.default.addObserver(self, selector: #selector(self.handle(playerItemNotification:)), name: name, object: nil)
        }
    }

    @objc private func handle(playerItemNotification notification: Notification) {
        guard let object = notification.object as? AVPlayerItem, let currentItem = player?.currentItem, object == currentItem, let delegate = delegate else {
            return
        }
        onMainThread {
            switch (notification.name) {
            case .AVPlayerItemPlaybackStalled:
                delegate.playerItemStalled(self, playerItem: currentItem)
            case .AVPlayerItemFailedToPlayToEndTime:
                delegate.playerItemFailedToPlayToEnd(self, playerItem: currentItem)
            case .AVPlayerItemDidPlayToEndTime:
                delegate.playerItemDidPlayToEndTime(self, playerItem: currentItem)
            default:
                break
            }
        }
    }

    private func playerDidChangePlayTimePeriodic() {
        // addPeriodicTimeObserver で指定しているので必ずメインスレッドから来る
        delegate?.playerDidChangePlayTimePeriodic(self)
    }

    //MARK:-  KVO

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let keyPath = keyPath, let player = object as? AVPlayer, player == self.player, let delegate = delegate {
            onMainThread {
                switch keyPath {
                case "rate":
                    delegate.playerDidChangeRate(self)
                case "volume":
                    delegate.playerDidChangeVolume(self)
                case "externalPlaybackActive":
                    // print("[KVO Player] externalPlaybackActive")
                    break
                default:
                    break
                }
            }
        }
        else if let keyPath = keyPath, let playerItem = object as? AVPlayerItem, playerItem == player?.currentItem, let delegate = delegate {
            onMainThread {
                switch keyPath {
                case "status":
                    delegate.playerItemDidChangeStatus(self, playerItem: playerItem)
                case "playbackLikelyToKeepUp":
                    // print("[KVO PlayerItem] playbackLikelyToKeepUp")
                    break
                case "loadedTimeRanges":
                    delegate.playerItemDidChangeLoadedTimeRanges(self, playerItem: playerItem)
                default:
                    break
                }
            }
        }
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

}
