import Foundation
import AVFoundation

@objc public protocol PlayerControllable: class {
    weak var delegate: PlayerControlDelegate? { get set }
    
    var playerItem: AVPlayerItem? { get set }
    
    func play()
    func pause()
    var isPlaying: Bool { get }
    
    var rate: Float { get set }
    
    var currentTime: CMTime { get }
    var duration: CMTime { get }
    var isSeeking: Bool { get }
    func seek(to: CMTime)
    func seek(to: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime)
    
    var loadedTimeRanges: [CMTimeRange] { get }
    
    var volume: Float { get set }
}

@objc public protocol PlayerControlDelegate: class {
    @objc optional func playerItemDidChangeStatus(_ player: PlayerControllable, playerItem: AVPlayerItem)
    @objc optional func playerItemDidChangeLoadedTimeRanges(_ player: PlayerControllable, playerItem: AVPlayerItem)
    
    @objc optional func playerItemStalled(_ player: PlayerControllable, playerItem: AVPlayerItem)
    @objc optional func playerItemFailedToPlayToEnd(_ player: PlayerControllable, playerItem: AVPlayerItem)
    @objc optional func playerItemDidPlayToEndTime(_ player: PlayerControllable, playerItem: AVPlayerItem)
    
    @objc optional func playerDidFinishSeeking(_ player: PlayerControllable)
    @objc optional func playerDidFailSeeking(_ player: PlayerControllable)
    
    @objc optional func playerDidChangePlayTimePeriodic(_ player: PlayerControllable)
    
    @objc optional func playerDidChangeRate(_ player: PlayerControllable)
    
    @objc optional func playerDidChangeVolume(_ player: PlayerControllable)
}
