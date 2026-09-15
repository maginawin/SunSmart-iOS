import Foundation
#if SUNSMART_PERFORMANCE
import os.signpost
#endif

/// Opt-in profiling only. Normal Release builds neither emit events nor read a clock.
enum AppPerformance {
    struct Sample {
        let name: String
        let seconds: TimeInterval
        let main: Bool
        let value: Int
    }
    #if SUNSMART_PERFORMANCE
    private static let log = OSLog(subsystem: "com.sunsmart.performance", category: .pointsOfInterest)
    private static let lock = NSLock()
    private static var observer: ((Sample) -> Void)?
    static func observe(_ callback: ((Sample) -> Void)?) {
        lock.lock(); observer = callback; lock.unlock()
    }
    private static func publish(_ sample: Sample) {
        lock.lock(); let callback = observer; lock.unlock()
        callback?(sample)
    }
    #endif

    struct Interval {
        #if SUNSMART_PERFORMANCE
        let name: StaticString
        let id: OSSignpostID
        let started: TimeInterval
        let main: Bool
        func end() {
            let seconds = ProcessInfo.processInfo.systemUptime - started
            os_signpost(.end, log: AppPerformance.log, name: name, signpostID: id)
            AppPerformance.publish(.init(name: name.description, seconds: seconds, main: main, value: 0))
        }
        #else
        func end() {}
        #endif
    }

    static func begin(_ name: StaticString) -> Interval {
        #if SUNSMART_PERFORMANCE
        let interval = Interval(name: name, id: OSSignpostID(log: log),
                                started: ProcessInfo.processInfo.systemUptime, main: Thread.isMainThread)
        os_signpost(.begin, log: log, name: name, signpostID: interval.id)
        return interval
        #else
        return Interval()
        #endif
    }

    static func event(_ name: StaticString, value: Int = 1) {
        #if SUNSMART_PERFORMANCE
        os_signpost(.event, log: log, name: name, "%{public}ld", value)
        publish(.init(name: name.description, seconds: 0, main: Thread.isMainThread, value: value))
        #endif
    }
}
