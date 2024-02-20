import Foundation
import AVFoundation

@MainActor
public protocol PlayerControllable: AnyObject {
    var delegate: PlayerControlDelegate? { get set }

    var playerItem: AVPlayerItem? { get set }

    func play()
    func pause()
    var isPlaying: Bool { get }

    var rate: Float { get set }

    var currentTime: CMTime { get }
    var duration: CMTime { get }

    var isSeeking: Bool { get }
    func seek(to: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, force: Bool, completionHandler: (@Sendable (Bool) -> Void)?)

    var loadedTimeRanges: [CMTimeRange] { get }

    var volume: Float { get set }
}

@MainActor
public protocol PlayerControlDelegate: AnyObject {
    func playerItemDidChangeStatus(_ player: PlayerControllable, playerItem: AVPlayerItem)
    func playerItemDidChangeLoadedTimeRanges(_ player: PlayerControllable, playerItem: AVPlayerItem)

    func playerItemStalled(_ player: PlayerControllable, playerItem: AVPlayerItem)
    func playerItemFailedToPlayToEnd(_ player: PlayerControllable, playerItem: AVPlayerItem)
    func playerItemDidPlayToEndTime(_ player: PlayerControllable, playerItem: AVPlayerItem)

    func playerDidFinishSeeking(_ player: PlayerControllable)
    func playerDidFailSeeking(_ player: PlayerControllable)

    func playerDidChangePlayTimePeriodic(_ player: PlayerControllable)

    func playerDidChangeRate(_ player: PlayerControllable)

    func playerDidChangeVolume(_ player: PlayerControllable)
}
