import Foundation
import AVFoundation

internal extension AVPlayerItem {

    private func loadPreferredTransform(completion: @escaping (Bool, CGAffineTransform) -> Void) {
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            guard self?.asset.statusOfValue(forKey: "tracks", error: nil) == .loaded else {
                completion(false, .identity)
                return
            }
            guard let videoTrack = self?.asset.tracks(withMediaType: .video).first else {
                completion(false, .identity)
                return
            }
            videoTrack.loadValuesAsynchronously(forKeys: ["preferredTransform"]) {
                guard videoTrack.statusOfValue(forKey: "preferredTransform", error: nil) == .loaded else {
                    completion(false, .identity)
                    return
                }
                completion(true, videoTrack.preferredTransform)
            }
        }
    }

    func loadPreferredCGImagePropertyOrientation(completion: @escaping (Bool, Int32) -> Void) {
        loadPreferredTransform { (success: Bool, preferredTransform: CGAffineTransform) -> Void in
            guard success else {
                completion(false, 1)
                return
            }

            let radians = atan2(preferredTransform.b, preferredTransform.a)
            let degrees = Int(radians * 180.0 / CGFloat.pi)
            let preferredCGImagePropertyOrientation: Int32

            switch degrees {
            case   0: preferredCGImagePropertyOrientation = 1 // Top, left
            case  90: preferredCGImagePropertyOrientation = 6 // Right, top
            case 180: preferredCGImagePropertyOrientation = 3 // Bottom, right
            case -90: preferredCGImagePropertyOrientation = 8 // Left, Bottom
            default : preferredCGImagePropertyOrientation = 1
            }

            // print("radians: \(radians), degrees: \(degrees), orientation: \(preferredCGImagePropertyOrientation)")
            completion(true, preferredCGImagePropertyOrientation)
        }

    }

}
