import Foundation

internal func onMainThreadAsync(execute work: @escaping @convention(block) () -> Swift.Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}

internal func onMainThreadSync(execute work: () -> Swift.Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.sync(execute: work)
    }
}
