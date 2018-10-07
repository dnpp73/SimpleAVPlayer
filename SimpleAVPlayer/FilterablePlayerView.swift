import UIKit
import AVFoundation
import GPUCIImageView
import CIFilterExtension

public final class FilterablePlayerView: UIView, PlayerControllable {

    public weak var delegate: PlayerControlDelegate? // Xcode のバグで Swift Protocol は @IBOutlet に出来ない

    public var filter: CIFilterExtension.Filter? {
        didSet {
            resetImageView()
        }
    }

    private var image: CIImage? {
        didSet {
            resetImageView()
        }
    }

    private func resetImageView() {
        if let image = image {
            if let filter = filter {
                imageView.image = filter(image)
            } else {
                imageView.image = image
            }
        } else {
            imageView.image = nil
        }
    }

    private var wasPlaying: Bool = false

    public var playerItem: AVPlayerItem? {
        willSet {
            wasPlaying = isPlaying
            pause()
            image = nil

            guard let playerItem = playerItem else {
                player.replaceCurrentItem(with: nil)
                return
            }

            playerItem.remove(videoOutput)
            for keyPath in playerItemKVOKeyPaths {
                playerItem.removeObserver(self, forKeyPath: keyPath, context: nil)
            }
        }
        didSet {
            guard let playerItem = playerItem else {
                wasPlaying = false
                return
            }
            playerItem.loadPreferredCGImagePropertyOrientation { [weak self] (success: Bool, preferredCGImagePropertyOrientation: Int32) -> Void in
                guard let self = self else {
                    return
                }

                self.preferredCGImagePropertyOrientation = preferredCGImagePropertyOrientation

                for keyPath in self.playerItemKVOKeyPaths {
                    playerItem.addObserver(self, forKeyPath: keyPath, options: [.new, .old], context: nil)
                }
                self.player.replaceCurrentItem(with: playerItem)
                playerItem.add(self.videoOutput)

                if self.wasPlaying {
                    self.wasPlaying = false
                    self.play()
                }
            }
        }
    }

    // MARK: - Player Control

    public func play() {
        displayLink?.isPaused = false
        player.play()
    }

    public func pause() {
        player.pause()
        displayLink?.isPaused = true
    }

    public var isPlaying: Bool {
        if player.currentItem == nil {
            return false
        }
        return player.rate != 0.0
    }

    public var rate: Float {
        get {
            return player.rate
        }
        set {
            player.rate = newValue
        }
    }

    public var currentTime: CMTime {
        guard let currentTime = player.currentItem?.currentTime(), currentTime.isValid else {
            return .invalid
        }
        return currentTime
    }

    public var duration: CMTime {
        guard let duration = player.currentItem?.duration, duration.isValid else {
            return .invalid
        }
        return duration
    }

    public private(set) var isSeeking: Bool = false

    public func seek(to: CMTime) {
        seek(to: to, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
    }

    public func seek(to: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        // ドキュメントによると kCMTimePositiveInfinity を放り込めば単純に seek(to:) と同じらしい。
        isSeeking = true
        let wasDisplayLinkPaused = displayLink?.isPaused ?? true
        displayLink?.isPaused = false
        player.seek(to: to, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] (success: Bool) -> Void in
            guard let self = self, let delegate = self.delegate else {
                return
            }
            self.isSeeking = false
            onMainThread {
                self.displayLink?.isPaused = wasDisplayLinkPaused
                if success {
                    delegate.playerDidFinishSeeking(self)
                } else {
                    delegate.playerDidFailSeeking(self)
                }
            }
        }
    }

    public var loadedTimeRanges: [CMTimeRange] {
        guard let loadedTimeRangeValues = player.currentItem?.loadedTimeRanges else {
            return []
        }
        return loadedTimeRangeValues.map { (loadedTimeRangeValue: NSValue) -> CMTimeRange in
            return loadedTimeRangeValue.timeRangeValue
        }
    }

    public var volume: Float {
        get {
            return player.volume
        }
        set {
            player.volume = newValue
        }
    }

    // MARK: - Private Vars

    private var displayLink: CADisplayLink?

    private let player = AVPlayer()
    private var timeObserver: AnyObject?

    /*
     NSDictionary* pixBuffAttributes = @{
         (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
     };
     */
    // private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [String(kCVPixelBufferPixelFormatTypeKey) : NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange as UInt32)])
    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)

    private let playerItemKVOKeyPaths: [String] = [
        "status",
        "playbackLikelyToKeepUp",
        "loadedTimeRanges"
    ]

    private var preferredCGImagePropertyOrientation: Int32 = 1

    // MARK: - Initializer

    deinit {
        cleanupPlayer() // なんとなく displayLink を止めてからにしておく
        NotificationCenter.default.removeObserver(self)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    private func commonInit() {
        addSubview(imageView)
        setupAVPlayer()
        setupAVPlayerItemNotifications()
    }

    private let imageView = GLCIImageView()

    private func setupAVPlayer() {
        player.addObserver(self, forKeyPath: "rate", options: [.new, .old], context: nil)
        player.addObserver(self, forKeyPath: "volume", options: [.new, .old], context: nil)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [unowned self] (time: CMTime) -> Void in
            self.playerDidChangePlayTimePeriodic()
        } as AnyObject?
        player.allowsExternalPlayback = false
        player.addObserver(self, forKeyPath: "externalPlaybackActive", options: [.new, .old], context: nil)
    }

    private func cleanupPlayer() {
        player.removeObserver(self, forKeyPath: "rate", context: nil)
        player.removeObserver(self, forKeyPath: "volume", context: nil)
        player.removeObserver(self, forKeyPath: "externalPlaybackActive", context: nil)
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        playerItem = nil
    }

    private func setupDisplayLink() {
        displayLink = { Void -> CADisplayLink in
            let displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkCallback(_:)))
            displayLink.add(to: .current, forMode: .common)
            displayLink.isPaused = true
            // displayLink.frameInterval = 60 // これをやると 1 Hz になる
            return displayLink
        }(())
    }

    // MARK: - Notification

    private func setupAVPlayerItemNotifications() {
        let notifications: [Notification.Name] = [
            .AVPlayerItemDidPlayToEndTime,
            .AVPlayerItemFailedToPlayToEndTime,
            .AVPlayerItemPlaybackStalled
        ]
        notifications.forEach { name in
            NotificationCenter.default.addObserver(self, selector: #selector(self.handle(playerItemNotification:)), name: name, object: nil)
        }
    }

    @objc private func handle(playerItemNotification notification: Notification) {
        guard let object = notification.object as? AVPlayerItem, let currentItem = player.currentItem, object == currentItem, let delegate = delegate else {
            return
        }
        onMainThread {
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

    // MARK: - KVO

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
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
        } else if let keyPath = keyPath, let playerItem = object as? AVPlayerItem, playerItem == player.currentItem, let delegate = delegate {
            onMainThread {
                switch keyPath {
                case "status":

                    if  playerItem.status == .readyToPlay,
                        self.image == nil,
                        let pixelBuffer: CVPixelBuffer = self.videoOutput.copyPixelBuffer(forItemTime: .zero, itemTimeForDisplay: nil) {
                        self.image = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: self.preferredCGImagePropertyOrientation)
                    }

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
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // MARK: - UIView

    public override func removeFromSuperview() {
        displayLink?.isPaused = true
        displayLink?.invalidate()
        pause()
        super.removeFromSuperview()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if let _ = superview {
            setupDisplayLink()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    public override var contentMode: UIView.ContentMode {
        didSet {
            imageView.contentMode = contentMode
        }
    }

    // MARK: - CADisplayLink

    @objc private func displayLinkCallback(_ displayLink: CADisplayLink) {
        let nextVSync: CFTimeInterval = (displayLink.timestamp + displayLink.duration)
        let outputItemTime: CMTime = videoOutput.itemTime(forHostTime: nextVSync)

        // 60 fps で 60 Hz なので毎回あるはずだけど、タイミングの問題や、動画の fps の問題で
        // 毎回新しい pixelBuffer がない可能性があるので、あった場合だけ描画する
        guard videoOutput.hasNewPixelBuffer(forItemTime: outputItemTime) else {
            return
        }
        // CVPixelBuffer == CVImageBuffer == CVBuffer
        guard let pixelBuffer: CVPixelBuffer = videoOutput.copyPixelBuffer(forItemTime: outputItemTime, itemTimeForDisplay: nil) else {
            return
        }

        // AVCaptureMovieFileOutput を使用して撮った動画等では画素自体は向きが横固定で、縦で撮ったりした場合はメタデータで回転情報だけ持っている。
        // そのため、pixelBuffer からそのまま ciImage を作ると必ず横長の画像が生成されてしまう。
        // loadValuesAsynchronously を駆使して preferredTransform を取っておき、そこから Orientation を計算しておくことによって解決する。
        // preferredTransform をそのまま放り込むと変になるという辛さ。
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: preferredCGImagePropertyOrientation)

        // そのまま放り込むと結構デカかったりするのでよしなにリサイズしときたい
        let screenScale: CGFloat = imageView.window?.screen.scale ?? 1.0
        let limitSize = imageView.bounds.size.applying(CGAffineTransform(scaleX: screenScale, y: screenScale))
        let limitWidth  = limitSize.width
        let limitHeight = limitSize.height
        let imageWidth  = image.extent.width
        let imageHeight = image.extent.height
        let scaleWidth  = limitWidth / imageWidth
        let scaleHeight = limitHeight / imageHeight
        let scale = min(scaleWidth, scaleHeight)
        let imageScale = min(1.0, scale)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: imageScale, y: imageScale))

        self.image = scaledImage
    }

}
