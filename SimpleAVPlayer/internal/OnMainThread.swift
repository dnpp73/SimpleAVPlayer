import Foundation

func onMainThread(execute work: @escaping @convention(block) () -> Swift.Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
