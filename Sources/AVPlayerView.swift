import UIKit
import AVFoundation

public final class AVPlayerView: UIView, PlayerControllable {

    // MARK: - Public Vars

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
            playerItemObservations.removeAll() // NSKeyValueObservation の deinit を発行させるだけで良い。
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
                guard let self = self else {
                    return
                }

                self.preferredCGImagePropertyOrientation = preferredCGImagePropertyOrientation

                self.playerItemObservations.append(playerItem.observe(\.status, options: [.new, .old], changeHandler: { [weak self] (playerItem, changes) in
                    onMainThreadAsync {
                        if let s = self, let d = s.delegate {
                            d.playerItemDidChangeStatus(s, playerItem: playerItem)
                        }
                    }
                }))
                /*
                self.playerItemObservations.append(playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .old], changeHandler: { (playerItem, changes) in
                    // print("[KVO PlayerItem] playbackLikelyToKeepUp")
                }))
                 */
                self.playerItemObservations.append(playerItem.observe(\.loadedTimeRanges, options: [.new, .old], changeHandler: { [weak self] (playerItem, changes) in
                    onMainThreadAsync {
                        if let s = self, let d = s.delegate {
                            d.playerItemDidChangeLoadedTimeRanges(s, playerItem: playerItem)
                        }
                    }
                }))

                player.replaceCurrentItem(with: playerItem)
                playerItem.add(self.output)

                if self.wasPlaying {
                    self.wasPlaying = false
                    self.play()
                }
            }
        }
    }

    // MARK: - Player Control

    public func play() {
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public var isPlaying: Bool {
        guard let player = player, let _ = player.currentItem else {
            return false
        }
        return player.rate != 0.0
    }

    public var rate: Float {
        get {
            guard let player = player else {
                return .nan
            }
            return player.rate
        }
        set {
            guard let player = player else {
                return
            }
            player.rate = newValue
        }
    }

    public var currentTime: CMTime {
        guard let currentTime = player?.currentItem?.currentTime(), currentTime.isValid else {
            return .invalid
        }
        return currentTime
    }

    public var duration: CMTime {
        guard let duration = player?.currentItem?.duration, duration.isValid else {
            return .invalid
        }
        return duration
    }

    public private(set) var isSeeking: Bool = false

    public func seek(to: CMTime, toleranceBefore: CMTime = .positiveInfinity, toleranceAfter: CMTime = .positiveInfinity, force: Bool = false, completionHandler: ((Bool) -> Void)? = nil) {
        guard let player = player else {
            completionHandler?(false)
            delegate?.playerDidFailSeeking(self)
            return
        }
        if !force && isSeeking {
            completionHandler?(false)
            delegate?.playerDidFailSeeking(self)
            return
        }
        // ドキュメントによると kCMTimePositiveInfinity を放り込めば単純に seek(to:) と同じらしい。
        isSeeking = true
        player.seek(to: to, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] (success: Bool) -> Void in
            guard let self = self, let delegate = self.delegate else {
                onMainThreadAsync {
                    completionHandler?(success)
                }
                return
            }
            self.isSeeking = false
            onMainThreadAsync {
                completionHandler?(success)
                if success {
                    delegate.playerDidFinishSeeking(self)
                } else {
                    delegate.playerDidFailSeeking(self)
                }
            }
        }
    }

    public var loadedTimeRanges: [CMTimeRange] {
        guard let loadedTimeRangeValues = player?.currentItem?.loadedTimeRanges else {
            return []
        }
        return loadedTimeRangeValues.map { (loadedTimeRangeValue: NSValue) -> CMTimeRange in
            loadedTimeRangeValue.timeRangeValue
        }
    }

    public var volume: Float {
        get {
            guard let player = player else {
                return .nan
            }
            return player.volume
        }
        set {
            guard let player = player else {
                return
            }
            player.volume = newValue
        }
    }

    // MARK: - ScreenShot

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

    // MARK: - AVPlayerLayer

    override public class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            fatalError("must not here")
        }
        return playerLayer
    }

    private var player: AVPlayer? {
        get {
            playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
    }

    // MARK: - Private Vars

    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [String: AnyObject]())

    private var timeObserver: AnyObject?
    private var playerItemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []

    // MARK: - Initializer

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupPlayer()
    }

    public required init?(coder aDecoder: NSCoder) {
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
        playerObservations.append(player.observe(\.rate, options: [.new, .old], changeHandler: { [weak self] (player, changes) in
            if let s = self, let d = s.delegate {
                onMainThreadAsync {
                    d.playerDidChangeRate(s)
                }
            }
        }))
        playerObservations.append(player.observe(\.volume, options: [.new, .old], changeHandler: { [weak self] (player, changes) in
            if let s = self, let d = s.delegate {
                onMainThreadAsync {
                    d.playerDidChangeVolume(s)
                }
            }
        }))
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [unowned self] (time: CMTime) -> Void in
            self.playerDidChangePlayTimePeriodic()
        } as AnyObject?
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        /*
        playerObservations.append(player.observe(\.isExternalPlaybackActive, options: [.new, .old], changeHandler: { (player, changes) in
            // print("[KVO Player] externalPlaybackActive")
        }))
         */
        self.player = player
    }

    private func cleanupPlayer() {
        guard let player = player else {
            return
        }
        playerObservations.removeAll() // NSKeyValueObservation の deinit を発行させるだけで良い。
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        playerItem = nil
        self.player = nil
    }

    // MARK: - UIView

    override public var contentMode: UIView.ContentMode {
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

    // MARK: - Notification

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
        onMainThreadAsync {
            switch notification.name {
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

}
