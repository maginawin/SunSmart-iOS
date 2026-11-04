import UIKit

/// Network/UI adapter. The Store and response/identity types remain Foundation-only.
final class SiteTimeZoneService {
    static let shared = SiteTimeZoneService()
    let store: SiteTimeZoneStore
    private var timer: Timer?
    private var tokens: [NSObjectProtocol] = []

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cache = SiteTimeZoneCache(directory: root.appendingPathComponent("SiteTimeZones/v1"))
        store = SiteTimeZoneStore(read: cache.read, write: cache.write) { identifier, date, completion in
            let region = UserData.currentServerRegion
            Task { @MainActor in
                let result = await NetworkRequest.shared.request(
                    .siteDST(timezone: identifier, date: SiteTimeZoneSnapshot.requestDateString(date), region: region), maximumDuration: 10)
                completion(result.mapError { $0 as Error })
            }
        }
        SiteTimeZoneValue.snapshotProvider = { [store] identifier, _ in store.snapshot(for: identifier) }
        let center = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification, .NSSystemTimeZoneDidChange] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.store.refreshObserved(retry: true)
            })
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard UIApplication.shared.applicationState == .active else { return }
            self?.store.refreshObserved()
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    @discardableResult func observe(_ value: SiteTimeZoneValue, callback: @escaping () -> Void) -> UUID {
        let token = store.observe(identifier: value.ianaId, callback: callback)
        store.refresh(identifier: value.ianaId)
        return token
    }
    func removeObserver(_ token: UUID?) { if let token { store.removeObserver(token) } }
    @MainActor func prepare(_ value: SiteTimeZoneValue?) async -> SiteTimeZoneSnapshot? {
        guard let value else { return nil }
        return await withCheckedContinuation { continuation in
            store.refresh(identifier: value.ianaId) { continuation.resume(returning: $0) }
        }
    }
    @MainActor func prepare(siteID: String) async -> SiteTimeZoneSnapshot? {
        await prepare(SiteData.load(siteId: siteID)?.timezone.flatMap(SiteTimeZoneValue.init(storageValue:)))
    }
}
