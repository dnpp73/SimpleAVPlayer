// UIKit 依存はないが CADisplayLink が Mac では利用できず、 CVDisplayLink を使わないといけないため。
#if canImport(UIKit)

import Foundation
import AVFoundation
import CoreImage

public protocol ImageRendererDelegate: AnyObject {
    func imageRendererDidUpdateImage(_ renderer: AVPlayerBasedCIImageRenderer)
}

public final class AVPlayerBasedCIImageRenderer: PlayerControllable {

    public weak var delegate: PlayerControlDelegate?
    public weak var imageRendererDelegate: ImageRendererDelegate?

    public private(set) var image: CIImage? {
        didSet {
            imageRendererDelegate?.imageRendererDidUpdateImage(self)
        }
    }

    public var playerItem: AVPlayerItem? {
        willSet {
            wasPlaying = isPlaying
            pause()
            image = nil

            playerItemObservations.removeAll() // NSKeyValueObservation の deinit を発行させるだけで良い。

            if let playerItem = playerItem {
                playerItem.remove(videoOutput)
            }
        }
        didSet {
            guard let playerItem = playerItem else {
                wasPlaying = false
                player.replaceCurrentItem(with: nil)
                return
            }

            playerItemObservations.append(playerItem.observe(\.status, options: [.new, .old]) { [weak self] (playerItem, changes) in
                onMainThreadAsync {
                    guard let self = self else {
                        return
                    }
                    self.delegate?.playerItemDidChangeStatus(self, playerItem: playerItem)
                }
            })

            playerItemObservations.append(playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .old]) { (playerItem, changes) in
                // print("[KVO PlayerItem] playbackLikelyToKeepUp")
            })

            playerItemObservations.append(playerItem.observe(\.loadedTimeRanges, options: [.new, .old]) { [weak self] (playerItem, changes) in
                onMainThreadAsync {
                    guard let self = self else {
                        return
                    }
                    self.delegate?.playerItemDidChangeLoadedTimeRanges(self, playerItem: playerItem)
                }
            })

            playerItem.loadPreferredCGImagePropertyOrientation { [weak self] (success: Bool, preferredCGImagePropertyOrientation: Int32) -> Void in
                onMainThreadAsync {
                    guard let self = self else {
                        return
                    }
                    self.preferredCGImagePropertyOrientation = preferredCGImagePropertyOrientation

                    self.player.replaceCurrentItem(with: playerItem)
                    playerItem.add(self.videoOutput)

                    // MEMO:
                    // maybe AVAssetImageGenerator only local URL. should be fail when remote streaming URL.
                    // There is Color difference between videoOutput.copyPixelBuffer and AVAssetImageGenerator.copyCGImage. I guess it is Color Management problem ...
                    let cgImage = try? AVAssetImageGenerator(asset: playerItem.asset).copyCGImage(at: .zero, actualTime: nil)
                    if let cgImage = cgImage {
                        self.image = CIImage(cgImage: cgImage).oriented(forExifOrientation: self.preferredCGImagePropertyOrientation)
                    }

                    // MEMO: magical DispatchQueue.main.asyncAfter ...
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if self.isPlaying == false && self.isSeeking == false {
                            self.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                    }

                    if self.wasPlaying {
                        self.wasPlaying = false
                        self.play()
                    }
                }
            }

        }
    }

    // MARK: - Player Control

    public func play() {
        guard let _ = playerItem else {
            pause()
            return
        }
        if isPlaying {
            return
        }
        let displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkCallback(_:)))
        displayLink.add(to: .main, forMode: .common) // いつも忘れるけど .main に .default の指定をするとスクロール中とかで止まるよ。
        displayLink.isPaused = false
        // displayLink.frameInterval = 60 // これをやると 1 Hz になる
        self.displayLink = displayLink
        player.play()
    }

    public func pause() {
        player.pause()
        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
    }

    public var isPlaying: Bool {
        if player.currentItem == nil {
            return false
        }
        return player.rate != 0.0
    }

    public var rate: Float {
        get {
            player.rate
        }
        set {
            if newValue == 0.0 {
                pause()
            } else if player.rate == 0.0 && newValue > 0.0 {
                play()
            }
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

    public func seek(to: CMTime, toleranceBefore: CMTime = .positiveInfinity, toleranceAfter: CMTime = .positiveInfinity, force: Bool = false, completionHandler: ((Bool) -> Void)? = nil) {
        if !force && isSeeking {
            completionHandler?(false)
            delegate?.playerDidFailSeeking(self)
            return
        }
        // ドキュメントによると kCMTimePositiveInfinity を放り込めば単純に seek(to:) と同じらしい。
        isSeeking = true
        let wasDisplayLinkPaused = displayLink?.isPaused ?? true
        displayLink?.isPaused = false
        player.seek(to: to, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] (success: Bool) -> Void in
            guard let self = self else {
                onMainThreadAsync {
                    completionHandler?(success)
                }
                return
            }
            self.isSeeking = false
            onMainThreadAsync {
                if success && self.isPlaying == false {
                    if let pixelBuffer: CVPixelBuffer = self.videoOutput.copyPixelBuffer(forItemTime: to, itemTimeForDisplay: nil) {
                        self.image = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: self.preferredCGImagePropertyOrientation)
                    }
                }
                self.displayLink?.isPaused = wasDisplayLinkPaused

                completionHandler?(success)
                if success {
                    self.delegate?.playerDidFinishSeeking(self)
                } else {
                    self.delegate?.playerDidFailSeeking(self)
                }
            }
        }
    }

    public var loadedTimeRanges: [CMTimeRange] {
        guard let loadedTimeRangeValues = player.currentItem?.loadedTimeRanges else {
            return []
        }
        return loadedTimeRangeValues.map { (loadedTimeRangeValue: NSValue) -> CMTimeRange in
            loadedTimeRangeValue.timeRangeValue
        }
    }

    public var volume: Float {
        get {
            player.volume
        }
        set {
            player.volume = newValue
        }
    }

    // MARK: - Private Vars

    private var displayLink: CADisplayLink?

    private var wasPlaying: Bool = false

    private let player = AVPlayer()

    private var timeObserver: AnyObject?
    private var playerItemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []

    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)

    private var preferredCGImagePropertyOrientation: Int32 = 1

    // MARK: - Initializer

    deinit {
        cleanupPlayer() // なんとなく displayLink を止めてからにしておく
        NotificationCenter.default.removeObserver(self)
    }

    public init(delegate: PlayerControlDelegate? = nil, imageRendererDelegate: ImageRendererDelegate? = nil) {
        self.delegate = delegate
        self.imageRendererDelegate = imageRendererDelegate
        setupAVPlayer()
        setupAVPlayerItemNotifications()
    }

    private func setupAVPlayer() {
        playerObservations.append(player.observe(\.rate, options: [.new, .old]) { [weak self] (player, changes) in
            guard let self = self else {
                return
            }
            onMainThreadAsync {
                self.delegate?.playerDidChangeRate(self)
            }
        })
        playerObservations.append(player.observe(\.volume, options: [.new, .old]) { [weak self] (player, changes) in
            guard let self = self else {
                return
            }
            onMainThreadAsync {
                self.delegate?.playerDidChangeVolume(self)
            }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: Int32(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] (time: CMTime) -> Void in
            self?.playerDidChangePlayTimePeriodic()
        } as AnyObject?
        player.allowsExternalPlayback = false
        /*
        playerObservations.append(player.observe(\.isExternalPlaybackActive, options: [.new, .old]) { (player, changes) in
            // print("[KVO Player] externalPlaybackActive")
        })
        */
    }

    private func cleanupPlayer() {
        playerObservations.removeAll() // NSKeyValueObservation の deinit を発行させるだけで良い。
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        playerItem = nil
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

    @objc
    private func handle(playerItemNotification notification: Notification) {
        guard let object = notification.object as? AVPlayerItem, let currentItem = player.currentItem, object == currentItem, let delegate = delegate else {
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

    // MARK: - CADisplayLink

    @objc
    private func displayLinkCallback(_ displayLink: CADisplayLink) {
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
        self.image = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: preferredCGImagePropertyOrientation)
    }

}

#endif
