import Foundation

private final class Provider: SiteCurrentLocationProviding {
    var authorization: SiteLocationAuthorization = .authorized
    var servicesEnabled = true
    var autoInitialize = true, autoCompleteChecks = true, initialized = false
    var accessChanged: (() -> Void)?
    var result: ((Result<SiteLocationSample, SiteLocationFailure>) -> Void)?
    var authorizations = 0, locations = 0, cancellations = 0
    var queries: [(Bool) -> Void] = []
    private var completedQueries = 0
    lazy var resolver: SiteLocationAccessResolver = {
        let resolver = SiteLocationAccessResolver(
            readAuthorization: { [unowned self] in authorization },
            queryServices: { [unowned self] in queries.append($0) })
        resolver.changed = { [weak self] in self?.accessChanged?() }
        return resolver
    }()
    var authorizationChanged: (() -> Void)? {
        { [weak self] in
            guard let self else { return }
            self.initialized = true
            self.resolver.authorizationDidChange()
            self.finishChecks()
        }
    }
    func refreshAccess(recheckServices: Bool) -> SiteLocationAccess {
        resolver.refresh(recheckServices: recheckServices)
    }
    func finishChecks() {
        guard autoCompleteChecks else { return }
        while completedQueries < queries.count {
            let callback = queries[completedQueries]
            completedQueries += 1
            callback(servicesEnabled)
        }
    }
    func send(_ value: Result<SiteLocationSample, SiteLocationFailure>) {
        if case .failure(.denied) = value { resolver.locationWasDenied() }
        result?(value)
        finishChecks()
    }
    func requestAuthorization() { authorizations += 1 }
    func requestLocation() { locations += 1 }
    func cancel() { cancellations += 1; resolver.cancel() }
}

private final class Harness {
    var valid = true, active = true
    var source = Provider()
    var sources: [Provider] = []
    var prompts: [SiteCurrentLocationRequest.Prompt] = []
    var decisions: [(Bool) -> Void] = []
    var settings: [(Bool) -> Void] = []
    var timeouts: [() -> Void] = []
    var results: [Result<SiteLocationSample, SiteCurrentLocationRequest.Failure>] = []
    var now = Date(timeIntervalSince1970: 10_000)
    lazy var request: SiteCurrentLocationRequest = {
        let request = SiteCurrentLocationRequest(
            makeProvider: { [unowned self] in sources.append(source); return source },
            contextIsValid: { [unowned self] in valid }, isActive: { [unowned self] in active },
            openSettings: { [unowned self] in settings.append($0) }, now: { [unowned self] in now },
            scheduleTimeout: { [unowned self] callback in timeouts.append(callback); return {} })
        request.showPrompt = { [unowned self] prompt, callback in prompts.append(prompt); decisions.append(callback) }
        request.completed = { [unowned self] in results.append($0) }
        return request
    }()
    func start() {
        request.start()
        if source.autoInitialize && !source.initialized { source.authorizationChanged?() }
        source.finishChecks()
    }
    func activate() {
        active = true
        request.didBecomeActive()
        source.finishChecks()
    }
    func sample(age: TimeInterval = 0, reduced: Bool = false, accuracy: Double = 12,
                latitude: Double = -1.234567, longitude: Double = 0) -> SiteLocationSample {
        .init(latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy,
              timestamp: now.addingTimeInterval(-age), isReducedAccuracy: reduced)
    }
    func expectFailure(_ failure: SiteCurrentLocationRequest.Failure) {
        precondition(results.count == 1)
        guard case .failure(let actual) = results[0] else { preconditionFailure("Expected failure") }
        precondition(actual == failure && request.phase == .idle)
    }
}

@main enum SiteCurrentLocationRequestTests {
    static func main() {
        authorizedAndRepeatedTap()
        permissionChoices()
        settingsReturn()
        cancellationAndLateCallbacks()
        availabilityAndSamples()
        foregroundOrdering()
        pendingResultFreshness()
        pendingResultAccessAndCancellation()
        initialAccessCheck()
        asynchronousDenialChecks()
        accessVersionsAndCancellation()
        denialErrorBeforeAuthorization()
        locationWaitingForAccess()
        settingsReturnDuringCheck()
        serviceQueryThreading()
        print("PASS: current-location lifecycle, async access/denial checks, stale-query isolation, deadlines, freshness and background-query/main-thread delivery")
    }

    static func authorizedAndRepeatedTap() {
        let h = Harness()
        h.start(); h.start()
        precondition(h.source.locations == 1 && h.prompts.isEmpty)
        h.source.authorizationChanged?()
        precondition(h.source.locations == 1, "Accuracy changes do not restart location")
        let late = h.source.result!
        h.source.send(.success(h.sample()))
        late(.success(h.sample()))
        h.timeouts.last!()
        precondition(h.results.count == 1 && h.request.phase == .idle && h.source.cancellations == 1)
        precondition(h.source.queries.isEmpty, "Authorized location never queries global services")
    }

    static func permissionChoices() {
        let h = Harness(); h.source.authorization = .notDetermined
        h.start()
        precondition(h.prompts == [.permission] && h.source.authorizations == 0)
        h.decisions[0](false)
        precondition(h.request.phase == .idle && h.results.isEmpty)
        h.source = Provider(); h.source.authorization = .notDetermined
        h.start(); h.decisions[1](true)
        precondition(h.source.authorizations == 1 && h.request.phase == .authorizing)
        h.source.authorizationChanged?()
        precondition(h.request.phase == .authorizing && h.results.isEmpty, "Initial notDetermined is not denial")
        h.source.authorization = .authorized; h.source.authorizationChanged?()
        precondition(h.source.locations == 1)
        h.source.send(.success(h.sample()))
        precondition(h.results.count == 1)

        let denied = Harness(); denied.source.authorization = .notDetermined
        denied.start(); denied.decisions[0](true)
        denied.source.authorization = .denied; denied.source.authorizationChanged?()
        denied.expectFailure(.denied)
        precondition(denied.prompts.count == 1 && denied.settings.isEmpty)
    }

    static func settingsReturn() {
        for completionBeforeReturn in [true, false] {
            let h = Harness(); h.source.authorization = .denied
            h.start(); precondition(h.prompts == [.settings]); h.decisions[0](true)
            if completionBeforeReturn { h.settings[0](true) }
            h.request.didBecomeActive()
            precondition(h.source.locations == 0, "Opening completion is not a return")
            h.active = false; h.request.didEnterBackground()
            h.source.authorization = .authorized; h.source.authorizationChanged?()
            precondition(h.source.locations == 0)
            h.activate()
            if !completionBeforeReturn { h.settings[0](true) }
            h.source.authorizationChanged?(); h.request.didBecomeActive()
            precondition(h.source.locations == 1 && h.request.phase == .locating)
        }
        let denied = Harness(); denied.source.authorization = .denied
        denied.start(); denied.decisions[0](true); denied.settings[0](true)
        denied.active = false; denied.request.didEnterBackground()
        denied.activate()
        precondition(denied.request.phase == .idle && denied.results.isEmpty && denied.prompts.count == 1)
        let failed = Harness(); failed.source.authorization = .denied
        failed.start(); failed.decisions[0](true); failed.settings[0](false)
        failed.expectFailure(.settingsUnavailable)
        failed.request.didBecomeActive(); precondition(failed.source.locations == 0)
    }

    static func cancellationAndLateCallbacks() {
        let h = Harness(); h.start()
        let oldResult = h.source.result!, oldAuthorization = h.source.authorizationChanged!, oldTimeout = h.timeouts.last!
        h.request.cancel() // The page invokes this on coordinate editing, city/country change, CREATE and exit.
        h.source = Provider(); h.start()
        oldResult(.success(h.sample())); oldResult(.failure(.denied)); oldAuthorization(); oldTimeout()
        precondition(h.results.isEmpty && h.request.phase == .locating && h.source.locations == 1)
        h.source.send(.success(h.sample()))
        precondition(h.results.count == 1)

        let prompt = Harness(); prompt.source.authorization = .notDetermined
        prompt.start(); let allow = prompt.decisions[0]
        prompt.request.cancel(); allow(true)
        precondition(prompt.source.authorizations == 0 && prompt.results.isEmpty)
        let context = Harness(); context.start(); context.valid = false
        context.source.send(.success(context.sample()))
        precondition(context.results.isEmpty && context.request.phase == .idle)
        let background = Harness(); background.start()
        background.active = false; background.request.didEnterBackground()
        background.activate()
        precondition(background.request.phase == .idle && background.results.isEmpty)
        let timeout = Harness(); timeout.start(); let late = timeout.source.result!
        timeout.timeouts.last!(); late(.success(timeout.sample())); timeout.expectFailure(.unavailable)
    }

    static func availabilityAndSamples() {
        let off = Harness(); off.source.servicesEnabled = false; off.source.authorization = .denied
        off.start(); off.expectFailure(.servicesDisabled); precondition(off.prompts.isEmpty)
        let restricted = Harness(); restricted.source.authorization = .restricted
        restricted.start(); restricted.expectFailure(.restricted)
        let midflight = Harness(); midflight.start(); midflight.source.servicesEnabled = false
        midflight.source.send(.failure(.denied)); midflight.expectFailure(.servicesDisabled)
        let expired = Harness(); expired.start(); expired.source.authorization = .notDetermined
        expired.source.send(.success(expired.sample())); expired.expectFailure(.denied)
        let sample = Harness()
        for value in [sample.sample(), sample.sample(latitude: 90, longitude: -180), sample.sample(age: 900, reduced: true)] {
            precondition(value.isUsable(at: sample.now))
        }
        for value in [sample.sample(age: 61), sample.sample(age: -60), sample.sample(accuracy: -1),
                      sample.sample(accuracy: .infinity), sample.sample(latitude: .nan), sample.sample(longitude: 181)] {
            precondition(!value.isUsable(at: sample.now))
        }
        let approximate = Harness(); approximate.start()
        approximate.source.send(.success(approximate.sample(age: 900, reduced: true)))
        precondition((try? approximate.results[0].get()) != nil)
    }

    static func foregroundOrdering() {
        let h = Harness(); h.source.authorization = .notDetermined
        h.start(); h.decisions[0](true)
        h.active = false // System sheet makes the app inactive, not backgrounded.
        h.source.authorization = .authorized; h.source.authorizationChanged?()
        precondition(h.source.locations == 0)
        h.activate(); h.source.authorizationChanged?()
        precondition(h.source.locations == 1)
        h.active = false; h.source.send(.success(h.sample()))
        precondition(h.results.isEmpty)
        h.activate(); precondition(h.results.count == 1)

        let denied = Harness(); denied.source.authorization = .notDetermined
        denied.start(); denied.decisions[0](true); denied.active = false
        denied.source.authorization = .denied; denied.source.authorizationChanged?()
        precondition(denied.results.isEmpty)
        denied.activate(); denied.expectFailure(.denied)
    }

    static func pendingResultFreshness() {
        let scenarios: [(age: TimeInterval, delay: TimeInterval, reduced: Bool, succeeds: Bool)] = [
            (59, 1, false, true), // The 60-second boundary remains usable.
            (59, 5, false, false), // Valid on receipt, expired while inactive.
            (0, 120, false, false),
            (900, 1200, true, true) // Reduced accuracy keeps its existing freshness exception.
        ]
        for scenario in scenarios {
            let h = Harness(); h.start()
            let late = h.source.result!, timeout = h.timeouts.last!
            let sample = h.sample(age: scenario.age, reduced: scenario.reduced)
            h.active = false; h.source.send(.success(sample))
            precondition(h.results.isEmpty && h.request.phase == .locating)
            h.now = h.now.addingTimeInterval(scenario.delay)
            timeout() // A pending result owns completion, even after its timestamp expires.
            precondition(h.results.isEmpty)
            h.activate(); h.request.didBecomeActive()
            precondition(h.results.count == 1 && h.request.phase == .idle && h.source.cancellations == 1)
            if scenario.succeeds {
                guard case .success(let delivered) = h.results[0] else { preconditionFailure("Expected usable pending location") }
                precondition(delivered.timestamp == sample.timestamp && delivered.latitude == sample.latitude
                             && delivered.longitude == sample.longitude)
            } else {
                h.expectFailure(.unavailable)
                h.source = Provider(); h.start()
                late(.success(h.sample())); timeout()
                precondition(h.results.count == 1 && h.request.phase == .locating && h.source.locations == 1)
                h.source.send(.success(h.sample()))
                precondition(h.results.count == 2 && h.request.phase == .idle)
                guard case .success = h.results[1] else { preconditionFailure("Retry must accept a fresh location") }
            }
        }
    }

    static func pendingResultAccessAndCancellation() {
        let denied = Harness(); denied.start(); denied.active = false
        denied.source.send(.success(denied.sample(age: 59)))
        denied.now = denied.now.addingTimeInterval(5)
        denied.source.authorization = .denied
        denied.activate(); denied.expectFailure(.denied)

        let failed = Harness(); failed.start(); failed.active = false
        failed.source.send(.failure(.unavailable))
        failed.now = failed.now.addingTimeInterval(120)
        failed.activate(); failed.expectFailure(.unavailable)

        for invalidContext in [false, true] {
            let h = Harness(); h.start(); h.active = false
            h.source.send(.success(h.sample(age: 59)))
            h.now = h.now.addingTimeInterval(5)
            if invalidContext { h.valid = false } else { h.request.didEnterBackground() }
            h.activate()
            precondition(h.results.isEmpty && h.request.phase == .idle && h.source.cancellations == 1)
        }
    }

    static func initialAccessCheck() {
        let h = Harness(); h.source.autoInitialize = false
        h.start(); h.start()
        precondition(h.sources.count == 1 && h.request.phase == .checkingAccess)
        precondition(h.source.locations == 0 && h.source.queries.isEmpty && h.prompts.isEmpty)
        let initialTimeout = h.timeouts.last!
        h.active = false; h.source.authorizationChanged?()
        initialTimeout()
        precondition(h.source.locations == 0 && h.results.isEmpty)
        h.activate(); h.source.authorizationChanged?()
        precondition(h.source.locations == 1 && h.source.queries.isEmpty)

        let timeout = Harness(); timeout.source.autoInitialize = false; timeout.start()
        timeout.active = false; timeout.timeouts.last!()
        timeout.source.authorizationChanged?()
        precondition(timeout.results.isEmpty && timeout.source.locations == 0)
        timeout.activate(); timeout.expectFailure(.unavailable)
        timeout.source = Provider(); timeout.start()
        precondition(timeout.source.locations == 1, "Initial callback timeout allows a new attempt")

        let undetermined = Harness(); undetermined.source.authorization = .notDetermined
        undetermined.start(); undetermined.timeouts.last!()
        precondition(undetermined.prompts == [.permission] && undetermined.results.isEmpty)
        precondition(undetermined.source.queries.isEmpty, "User permission has no automatic check timeout")
    }

    static func asynchronousDenialChecks() {
        for servicesEnabled in [false, true] {
            let h = Harness(); h.source.authorization = .denied; h.source.autoCompleteChecks = false
            h.start(); h.start()
            _ = h.source.refreshAccess(recheckServices: false)
            _ = h.source.refreshAccess(recheckServices: false)
            precondition(h.source.queries.count == 1 && h.source.locations == 0)
            precondition(h.prompts.isEmpty && h.results.isEmpty && h.request.phase == .checkingAccess)
            let reply = h.source.queries[0]
            reply(servicesEnabled); reply(!servicesEnabled)
            if servicesEnabled { precondition(h.prompts == [.settings] && h.results.isEmpty) }
            else { h.expectFailure(.servicesDisabled) }
        }

        let h = Harness(); h.source.authorization = .notDetermined; h.start(); h.decisions[0](true)
        h.source.autoCompleteChecks = false; h.source.authorization = .denied
        h.active = false; h.source.authorizationChanged?()
        precondition(h.request.phase == .checkingAccess && h.source.queries.count == 1)
        h.source.queries[0](true)
        h.activate(); h.source.queries.last!(true)
        h.expectFailure(.denied)
        precondition(h.prompts == [.permission], "System denial must not stack a Settings prompt")
    }

    static func accessVersionsAndCancellation() {
        for notifyChange in [true, false] {
            let h = Harness(); h.source.authorization = .denied; h.source.autoCompleteChecks = false; h.start()
            let old = h.source.queries[0]
            h.source.authorization = .authorized
            if notifyChange { h.source.authorizationChanged?() }
            old(false)
            precondition(h.source.locations == 1 && h.results.isEmpty && h.request.phase == .locating)
            h.source.authorization = .denied; h.source.authorizationChanged?()
            old(false)
            precondition(h.results.isEmpty && h.source.queries.count == 2)
            h.source.queries[1](true); h.expectFailure(.denied)
        }

        let sameStatus = Harness(); sameStatus.source.authorization = .denied
        sameStatus.source.autoCompleteChecks = false; sameStatus.start()
        sameStatus.source.authorizationChanged?() // A global toggle can keep the same denied status.
        sameStatus.source.queries[0](false)
        precondition(sameStatus.prompts.isEmpty && sameStatus.results.isEmpty)
        sameStatus.source.queries[1](true)
        precondition(sameStatus.prompts == [.settings] && sameStatus.results.isEmpty)

        let h = Harness(); h.source.authorization = .denied; h.source.autoCompleteChecks = false; h.start()
        let old = h.source.queries[0], oldTimeout = h.timeouts.last!, oldAccess = h.source.accessChanged!
        h.request.cancel(); h.source = Provider(); h.start()
        old(false); oldTimeout(); oldAccess()
        precondition(h.source.locations == 1 && h.results.isEmpty && h.request.phase == .locating)

        for background in [false, true] {
            let pending = Harness(); pending.source.authorization = .denied
            pending.source.autoCompleteChecks = false; pending.start()
            if background { pending.active = false; pending.request.didEnterBackground() }
            else { pending.valid = false }
            pending.source.queries[0](false)
            pending.activate()
            precondition(pending.results.isEmpty && pending.request.phase == .idle)
        }
    }

    static func denialErrorBeforeAuthorization() {
        for servicesEnabled in [false, true] {
            let h = Harness(); h.start(); h.source.autoCompleteChecks = false
            let locationTimeout = h.timeouts.last!, timeoutCount = h.timeouts.count
            h.source.send(.failure(.denied)) // The authorization property still says authorized.
            _ = h.source.refreshAccess(recheckServices: false)
            _ = h.source.refreshAccess(recheckServices: false)
            precondition(h.source.queries.count == 1 && h.results.isEmpty && h.source.locations == 1)
            precondition(h.timeouts.count == timeoutCount, "An access check cannot extend the location deadline")
            h.source.queries[0](servicesEnabled)
            h.expectFailure(servicesEnabled ? .denied : .servicesDisabled)
            locationTimeout(); precondition(h.results.count == 1)
        }

        let h = Harness(); h.start(); h.source.autoCompleteChecks = false
        h.source.send(.failure(.denied)); let late = h.source.queries[0]
        h.timeouts.last!(); h.expectFailure(.unavailable)
        h.source = Provider(); h.start(); late(false)
        precondition(h.results.count == 1 && h.source.locations == 1 && h.request.phase == .locating)

        let initial = Harness(); initial.source.authorization = .denied
        initial.source.autoCompleteChecks = false; initial.start()
        let initialLate = initial.source.queries[0]
        initial.timeouts.last!(); initialLate(false); initial.expectFailure(.unavailable)

        let overlap = Harness(); overlap.start(); overlap.source.autoCompleteChecks = false
        overlap.source.authorization = .denied; overlap.source.authorizationChanged?()
        overlap.source.send(.failure(.denied))
        overlap.source.queries[0](true)
        precondition(overlap.results.isEmpty, "A new denial event invalidates the earlier service observation")
        overlap.source.queries[1](false); overlap.expectFailure(.servicesDisabled)
    }

    static func locationWaitingForAccess() {
        for reduced in [false, true] {
            let h = Harness(); h.start(); h.source.autoCompleteChecks = false
            h.source.authorization = .denied; h.source.authorizationChanged?()
            let late = h.source.queries[0], originalTimeoutCount = h.timeouts.count
            h.source.send(.success(h.sample(age: 59, reduced: reduced)))
            h.source.send(.success(h.sample())) // Cannot replace the first pending result.
            precondition(h.results.isEmpty && h.timeouts.count == originalTimeoutCount)
            h.now = h.now.addingTimeInterval(5)
            h.source.authorization = .authorized; h.source.authorizationChanged?(); late(false)
            if reduced {
                precondition(h.results.count == 1 && (try? h.results[0].get()) != nil)
            } else { h.expectFailure(.unavailable) }
            precondition(h.source.locations == 1)
        }

        let h = Harness(); h.start(); h.source.autoCompleteChecks = false
        h.source.authorization = .denied; h.source.authorizationChanged?()
        h.source.send(.success(h.sample())); h.timeouts.last!()
        h.source.queries[0](true); h.expectFailure(.unavailable)
    }

    static func settingsReturnDuringCheck() {
        for authorized in [false, true] {
            let h = Harness(); h.source.authorization = .denied; h.start()
            h.decisions[0](true); h.settings[0](true)
            h.source.autoCompleteChecks = false
            h.active = false; h.request.didEnterBackground(); h.source.authorizationChanged?()
            let late = h.source.queries.last!
            h.activate()
            precondition(h.request.phase == .checkingAccess && h.source.locations == 0)
            if authorized { h.source.authorization = .authorized; h.source.authorizationChanged?() }
            late(false)
            if !authorized {
                precondition(h.request.phase == .checkingAccess, "Pre-return queries cannot decide the resumed state")
                h.source.queries.last!(false)
            }
            h.request.didBecomeActive()
            precondition(h.results.isEmpty && h.prompts == [.settings])
            precondition(h.source.locations == (authorized ? 1 : 0))
            precondition(h.request.phase == (authorized ? .locating : .idle))
        }

        let failed = Harness(); failed.source.authorization = .denied; failed.start()
        failed.decisions[0](true); failed.active = false; failed.settings[0](false)
        precondition(failed.results.isEmpty)
        failed.activate(); failed.expectFailure(.settingsUnavailable)
        precondition(failed.source.locations == 0 && failed.source.queries.count == 1)
    }

    static func serviceQueryThreading() {
        var completed = false
        SiteCurrentLocationProvider.queryServicesEnabled(read: {
            precondition(!Thread.isMainThread, "System services query must run off the main thread")
            return false
        }, completion: { enabled in
            precondition(Thread.isMainThread && !enabled, "Access result must return to the main thread")
            completed = true
        })
        let deadline = Date().addingTimeInterval(3)
        while !completed && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        precondition(completed)
    }
}
